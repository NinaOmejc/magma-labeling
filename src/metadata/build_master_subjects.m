function [tables, audit] = build_master_subjects(tables, identities, config)
% BUILD_MASTER_SUBJECTS Verified participant characteristics, never visit imputation.
    audit=master_audit_entry(); Q=tables.Questionnaire;
    participants=unique(identities.participant_id(identities.participant_id~=""));
    [~,order]=sort(str2double(erase(participants,'Sub'))); participants=participants(order);
    n=numel(participants);
    S=table(participants,participants,repmat("Unknown",n,1),nan(n,1), ...
        repmat("unknown",n,1),false(n,1),strings(n,1),strings(n,1),strings(n,1),strings(n,1), ...
        'VariableNames',{'participant_id','baseline_subject_id','study_group','grp', ...
        'group_status','baseline_questionnaire_present','source_subject_ids', ...
        'questionnaire_group_values','recording_group_values','participant_metadata_provenance'});
    values=cell(n,numel(config.participant_fields)); provenance=strings(n,numel(config.participant_fields));
    for p=1:n
        rows=find(Q.participant_id==participants(p));
        baseline=rows(Q.source_subject_id(rows)==participants(p));
        S.baseline_questionnaire_present(p)=~isempty(baseline);
        S.source_subject_ids(p)=strjoin(identities.source_subject_id(identities.participant_id==participants(p)),'; ');
        if ~isempty(baseline)
            S.participant_metadata_provenance(p)=row_refs(Q,baseline);
        else
            audit=[audit; entry('warning','missing_baseline_questionnaire',participants(p),'', ...
                'No original participant questionnaire row; no baseline responses manufactured.')]; %#ok<AGROW>
        end
        qgroups=Q.import_group_code(rows); qgroups=qgroups(isfinite(qgroups));
        summary_groups=zeros(0,1); original_summary=strings(0,1);
        for target={'Label_burden','Phenotypes'}
            T=tables.(target{1}); selected=find(T.participant_id==participants(p));
            summary_groups=[summary_groups;T.import_group_code(selected)]; %#ok<AGROW>
            if ismember('subject_group',T.Properties.VariableNames)
                for r=selected'
                    original_summary(end+1,1)=T.source_subject_id(r)+":"+master_cell_text(master_table_value(T,'subject_group',r)); %#ok<AGROW>
                end
            end
        end
        S.recording_group_values(p)=strjoin(unique(original_summary,'stable'),'; ');
        qprovenance=strings(0,1);
        for r=rows'
            qprovenance(end+1,1)=Q.source_subject_id(r)+":"+string(Q.import_group_code(r)); %#ok<AGROW>
        end
        S.questionnaire_group_values(p)=strjoin(unique(qprovenance,'stable'),'; ');
        confirmed=unique(qgroups); observed=unique([qgroups;summary_groups(isfinite(summary_groups))]);
        if numel(observed)>1
            S.group_status(p)="conflict";
            audit=[audit; entry('warning','conflicting_group_classification',participants(p),'study_group', ...
                'Contradictory nonmissing classifications retained in provenance; participant group left Unknown.')]; %#ok<AGROW>
        elseif numel(confirmed)==1
            S.grp(p)=confirmed;
            if confirmed==1, S.study_group(p)="Patient"; else, S.study_group(p)="Control"; end
            S.group_status(p)="verified_questionnaire";
        end
        for f=1:numel(config.participant_fields)
            field=config.participant_fields{f};
            if ~ismember(field,Q.Properties.VariableNames), continue; end
            selected=cell(0,1); selected_rows=zeros(0,1);
            for r=rows'
                value=master_table_value(Q,field,r);
                if master_value_missing(value), continue; end
                if isempty(selected) || ~any(cellfun(@(x) isequaln(x,value),selected))
                    selected{end+1,1}=value; %#ok<AGROW>
                    selected_rows(end+1,1)=r; %#ok<AGROW>
                end
            end
            if numel(selected)==1
                values{p,f}=selected{1};
                provenance(p,f)=row_refs(Q,selected_rows);
            elseif numel(selected)>1
                audit=[audit; entry('warning','conflicting_participant_characteristic',participants(p),field, ...
                    'Conflicting original values remain in Questionnaire; no participant value selected.')]; %#ok<AGROW>
            end
        end
    end
    for f=1:numel(config.participant_fields)
        field=config.participant_fields{f};
        S.(field)=master_typed_column(values(:,f));
        S.([field '_provenance'])=provenance(:,f);
    end
    Q.questionnaire_record_role=repmat("baseline",height(Q),1);
    Q.baseline_information_scope=repmat("source_baseline_response",height(Q),1);
    followup=Q.source_subject_id~=Q.participant_id & Q.participant_id~="";
    Q.questionnaire_record_role(followup)="followup_scope_unverified";
    Q.baseline_information_scope(followup)="followup_scope_unverified";
    collected=followup & isfinite(Q.import_baseline_content_present) & Q.import_baseline_content_present==1;
    Q.questionnaire_record_role(collected)="followup_questionnaire_content";
    partial=followup & Q.import_baseline_content_present==0;
    Q.questionnaire_record_role(partial)="followup_observations_only";
    Q.baseline_information_scope(partial)="participant_baseline_not_repeated";
    Q.baseline_information_scope(collected)="actual_followup_source_response";
    tables.Subjects=S; tables.Questionnaire=Q;
end

function text=row_refs(T,rows)
    refs=T.import_source_file(rows)+":"+T.import_source_sheet(rows)+":"+T.import_source_row(rows);
    text=strjoin(unique(refs,'stable'),'; ');
end

function row=entry(severity,code,id,field,detail)
    row=master_audit_entry(severity,code,'Subjects',id,field,'','',NaN,detail);
end
