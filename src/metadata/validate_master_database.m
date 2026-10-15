function [audit, counts] = validate_master_database(tables, identities, sources, existing_audit)
% VALIDATE_MASTER_DATABASE Cardinality, keys, identities and source-value fidelity.
% Unconfirmed visits remain explicitly missing; fatal key/data conflicts prevent export.
    audit=master_audit_entry(); targets=master_table_names(tables);
    counts=table(string(targets)',zeros(numel(targets),1),zeros(numel(targets),1), ...
        'VariableNames',{'table_name','output_rows','input_rows'});
    for t=1:numel(targets)
        target=targets{t}; T=tables.(target); key=master_primary_key(T,target);
        counts.output_rows(t)=height(T);
        [unique_key,~,group]=unique(key);
        totals=accumarray(group,1);
        for g=find(totals>1)'
            audit=[audit; issue('error','duplicate_primary_key',target,unique_key(g),'primary_key','Output primary key is not unique.')]; %#ok<AGROW>
        end
        if any(T.participant_id=="")
            audit=[audit; issue('warning','unresolved_participant_identity',target,'','participant_id','Rows without an established participant identity are retained explicitly.')]; %#ok<AGROW>
        end
        known=T.participant_id~="";
        if any(~ismember(T.participant_id(known),tables.Subjects.participant_id))
            audit=[audit; issue('error','invalid_participant_foreign_key',target,'','participant_id','Participant foreign key is absent from Subjects.')]; %#ok<AGROW>
        end
        if ~strcmp(target,'Subjects')
            [matched,index]=ismember(T.source_subject_id,identities.source_subject_id);
            if any(T.participant_id(matched)~=identities.participant_id(index(matched))) || ...
                    any(T.visit_id(matched)~=identities.visit_id(index(matched))) || ...
                    ~isequaln(T.visit_number(matched),identities.visit_number(index(matched)))
                audit=[audit; issue('error','inconsistent_identity_link',target,'','source_subject_id','Shared identity lookup is inconsistent.')]; %#ok<AGROW>
            end
            resolved=isfinite(T.visit_number);
            if any(T.visit_number(resolved)<1 | T.visit_number(resolved)~=fix(T.visit_number(resolved)))
                audit=[audit; issue('error','invalid_visit_number',target,'','visit_number','Resolved visit numbers must be positive integers.')]; %#ok<AGROW>
            end
        end
        if ismember(target,{'Physiology','Label_burden','Phenotypes'})
            if any(T.recording_id=="") || any(~ismember(T.measure,[1 2]))
                audit=[audit; issue('error','invalid_recording_key',target,'','recording_id','Recording identities/within-visit measures must be explicit.')]; %#ok<AGROW>
            end
        end
        if strcmp(target,'Phenotypes') && any(~ismember(string(T.annotation_layer),["automatic","reviewed"]))
            audit=[audit; issue('error','invalid_annotation_layer',target,'','annotation_layer','Expected automatic or reviewed.')]; %#ok<AGROW>
        end
    end
    known=isfinite(identities.visit_number) & identities.participant_id~="";
    pairs=identities.participant_id(known)+":"+string(identities.visit_number(known));
    if numel(unique(pairs))~=numel(pairs)
        audit=[audit; issue('error','ambiguous_visit_number','Identity_map','','visit_number','Two source visits map to the same participant/visit number.')];
    end
    % Every input row must map to exactly one output row. Every nonmissing
    % original value must survive unchanged, except an audited precedence rule.
    for s=1:numel(sources)
        source=sources(s); target=source.spec.target; T=tables.(target);
        count_index=find(counts.table_name==string(target),1);
        counts.input_rows(count_index)=counts.input_rows(count_index)+height(source.table);
        keys=master_primary_key(source.table,target); output_keys=master_primary_key(T,target);
        for r=1:height(source.table)
            row=find(output_keys==keys(r));
            if numel(row)~=1
                audit=[audit; fidelity_issue('error','source_row_cardinality',source,r,'primary_key','Source row does not map to exactly one output row.')]; %#ok<AGROW>
                continue;
            end
            for c=1:height(source.mapping)
                field=char(source.mapping.output_column(c));
                before=source.raw_cells{source.source_rows(r),source.mapping.source_column(c)};
                after=master_table_value(T,field,row);
                if equivalent(before,after), continue; end
                allowed=any(existing_audit.issue=="configured_source_precedence" & ...
                    existing_audit.table_name==string(target) & existing_audit.key==keys(r) & existing_audit.field==string(field));
                complementary=master_value_missing(before) && ~master_value_missing(after) && ...
                    contains(T.import_source_id(row),'; ');
                if ~allowed && ~complementary
                    audit=[audit; fidelity_issue('error','changed_source_value',source,r,field,'Original observation or missing-value token changed during integration.')]; %#ok<AGROW>
                end
            end
        end
    end
    counts.input_rows(1)=height(tables.Subjects);
    if counts.output_rows(2)~=counts.input_rows(2)
        audit=[audit; issue('error','questionnaire_row_count','Questionnaire','','','Questionnaire rows must neither be merged nor manufactured.')];
    end
    index=find(counts.table_name=="StressTest",1);
    if ~isempty(index) && counts.output_rows(index)~=counts.input_rows(index)
        audit=[audit; issue('error','stress_test_row_count','StressTest','','','Stress-test rows must neither be merged nor manufactured.')];
    end
    recordings=unique([tables.Physiology.recording_id;tables.Label_burden.recording_id;tables.Phenotypes.recording_id]);
    for target={'Physiology','Label_burden','Phenotypes'}
        present=unique(tables.(target{1}).recording_id);
        absent=setdiff(recordings,present);
        for r=1:numel(absent)
            audit=[audit; issue('warning','missing_source_modality',target{1},absent(r),'recording_id','No matching recording in this configured source table; no row manufactured.')]; %#ok<AGROW>
        end
    end
    for i=1:height(identities)
        if ~any(tables.Physiology.source_subject_id==identities.source_subject_id(i))
            audit=[audit; issue('warning','visit_without_physiology','Physiology', ...
                identities.visit_id(i),'source_subject_id', ...
                'Source visit is known from metadata/mapping, but no physiological recording rows were supplied; no M1/M2 rows manufactured.')]; %#ok<AGROW>
        end
        if identities.participant_id(i)~=identities.source_subject_id(i) && ...
                ~any(tables.Questionnaire.source_subject_id==identities.source_subject_id(i))
            audit=[audit; issue('info','baseline_questionnaire_not_repeated','Questionnaire', ...
                identities.source_subject_id(i),'','Mapped repeat has no source questionnaire row. Participant characteristics remain joinable through Subjects.')]; %#ok<AGROW>
        end
    end
end

function yes=equivalent(a,b)
    if isempty(a) || (isscalar(a) && ismissing(a))
        yes=isempty(b) || (isscalar(b) && ismissing(b));
    else
        yes=isequaln(a,b);
        if (ischar(a)||isstring(a)) && (ischar(b)||isstring(b)), yes=isequal(string(a),string(b)); end
        if (isnumeric(a)||islogical(a)) && (isnumeric(b)||islogical(b)), yes=isequaln(double(a),double(b)); end
    end
end

function row=fidelity_issue(severity,code,source,r,field,detail)
    key=master_primary_key(source.table,source.spec.target);
    row=master_audit_entry(severity,code,source.spec.target,key(r),field, ...
        source.spec.file,source.spec.sheet,source.source_rows(r),detail);
end

function row=issue(severity,code,target,key,field,detail)
    row=master_audit_entry(severity,code,target,key,field,'','',NaN,detail);
end

