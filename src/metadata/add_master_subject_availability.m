function [tables, diagnostics] = add_master_subject_availability(tables)
% ADD_MASTER_SUBJECT_AVAILABILITY Count observed data, without changing source tables.
% Denominators are nominal targets, never caps on additional visits or tests.
    S=tables.Subjects;
    names={'Questionnaire','Physiology','Label_burden','Phenotypes','StressTest'};
    denominators=[0 4 4 4 2];
    diagnostics=table(strings(0,1),strings(0,1),strings(0,1),strings(0,1), ...
        'VariableNames',{'table_name','participant_id','recording_key','reason'});
    for k=1:numel(names)
        name=names{k}; counts=zeros(height(S),1);
        if isfield(tables,name)
            T=tables.(name); valid=data_rows(T,name); keys=unit_keys(T,name);
            known=ismember(string(T.participant_id),S.participant_id);
            missing_key=ismissing(keys) | strlength(keys)==0;
            bad=~known | (valid & missing_key);
            for r=find(bad)'
                reason="Canonical participant is absent from Subjects.";
                if known(r), reason="Available data have no measurement key."; end
                diagnostics(end+1,:)={string(name),string(T.participant_id(r)),keys(r),reason}; %#ok<AGROW>
            end
            for p=1:height(S)
                selected=valid & known & ~missing_key & string(T.participant_id)==S.participant_id(p);
                counts(p)=numel(unique(keys(selected)));
            end
        elseif strcmp(name,'StressTest')
            warning('MAGMA:Metadata:StressTestNotImported', ...
                'StressTest has not yet been imported. Subjects.StressTest=0/2 is a placeholder, not confirmed absence.');
        end
        if k==1, S.(name)=double(counts>0);
        else, S.(name)=string(counts)+"/"+string(denominators(k)); end
    end
    S=movevars(S,names,'After','grp');
    tables.Subjects=S;
    if ~isempty(diagnostics)
        warning('MAGMA:Metadata:AvailabilityKeys','%d availability rows have unmatched participants or missing measurement keys; see diagnostics.',height(diagnostics));
    end
end

function valid=data_rows(T,role)
    names=string(T.Properties.VariableNames); lower_names=lower(names);
    metadata=["participant_id","participant_number","source_subject_id","visit_id","visit_number", ...
        "recording_id","questionnaire_record_id","stress_test_record_id","subject","sub_code","id", ...
        "measure","measurement","longitudinal_measure","longitudinal_measure_number", ...
        "grp","study_group","subject_group","group_status","label","annotation_layer","analysis_id", ...
        "feature_index","feature_name","phenotype_group","feature_role","units","missing_reason", ...
        "available","availability","coverage","coverage_fraction","reviewed_coverage_fraction", ...
        "duration_sec","recording_duration_sec","questionnaire_record_role","baseline_information_scope", ...
        "repeated_measurement_flag","paired_sub_code","dt_study","st_1","st_2","st_1_date","st_2_date", ...
        "no","test_no","test_number","test_date","study_status","study_status_confirmed_on"];
    excluded=ismember(lower_names,metadata) | startsWith(lower_names,["import_","source_"]) | ...
        contains(lower_names,'provenance') | startsWith(lower_names,["available_","availability_","coverage_"]) | ...
        endsWith(lower_names,["_available","_availability","_coverage_fraction","_missing_reason","_id"]);
    if strcmp(role,'StressTest')
        % Clininet documentation has zero placeholders even for absent tests.
        excluded=excluded | ismember(lower_names,["clininet_pl_txt","clinical_note","notes","comment"]);
    end
    valid=false(height(T),1);
    for c=find(~excluded)
        field=char(names(c)); values=T.(field); present=false(height(T),1);
        for r=1:height(T), present(r)=value_valid(values(r,:)); end
        flags={['available_' field],['availability_' field],[field '_available'],[field '_availability']};
        if strcmp(role,'Label_burden') && startsWith(field,'automatic_'), flags{end+1}='automatic_available'; end
        if strcmp(role,'Label_burden') && startsWith(field,'reviewed_')
            flags{end+1}='reviewed_available';
            if ismember('reviewed_coverage_fraction',T.Properties.VariableNames)
                for r=1:height(T)
                    present(r)=present(r) && flag_positive(master_table_value(T,'reviewed_coverage_fraction',r));
                end
            end
        end
        for f=flags
            if ~ismember(f{1},T.Properties.VariableNames), continue; end
            for r=1:height(T), present(r)=present(r) && flag_positive(master_table_value(T,f{1},r)); end
        end
        valid=valid | present;
    end
    for flag={'available','availability'}
        if ~ismember(flag{1},T.Properties.VariableNames), continue; end
        for r=1:height(T), valid(r)=valid(r) && flag_positive(master_table_value(T,flag{1},r)); end
    end
end

function yes=value_valid(value)
    if iscell(value), yes=any(cellfun(@value_valid,value),'all');
    elseif isnumeric(value), yes=any(isfinite(value),'all');
    elseif islogical(value), yes=~isempty(value);
    elseif isdatetime(value) || isduration(value), yes=any(~ismissing(value),'all');
    elseif ischar(value) || isstring(value) || iscategorical(value)
        text=lower(strtrim(string(value)));
        missing_tokens=["","n/a","na","not reported","unknown","#n/a","nan","nat", ...
            "not recorded","not measured","not available","not performed","not done"];
        yes=any(~ismissing(text) & ~ismember(text,missing_tokens),'all');
    else, yes=false; end
end

function yes=flag_positive(value)
    if iscell(value), value=value{1}; end
    if isnumeric(value) || islogical(value), yes=isscalar(value) && isfinite(value) && value>0;
    else, yes=ismember(lower(strtrim(string(value))),["1","true","yes","available"]); end
end

function keys=unit_keys(T,role)
    keys=strings(height(T),1);
    if strcmp(role,'Questionnaire'), keys(:)="questionnaire"; return; end
    if ~strcmp(role,'StressTest'), keys=string(T.recording_id); return; end
    for r=1:height(T)
        if ismember('test_no',T.Properties.VariableNames) && value_valid(master_table_value(T,'test_no',r))
            test=lower(strtrim(master_cell_text(master_table_value(T,'test_no',r))));
            context="";
            if ismember('test_date',T.Properties.VariableNames)
                date=master_table_value(T,'test_date',r);
                if value_valid(date)
                    if isdatetime(date), date.Format='yyyy-MM-dd'; end
                    context="date:"+master_cell_text(date);
                end
            end
            if context=="" && ismember('visit_id',T.Properties.VariableNames), context="visit:"+string(T.visit_id(r)); end
            if context=="" && ismember('source_subject_id',T.Properties.VariableNames), context="source:"+string(T.source_subject_id(r)); end
            keys(r)=context+"|test:"+test;
        elseif ismember('stress_test_record_id',T.Properties.VariableNames)
            keys(r)=string(T.stress_test_record_id(r));
        elseif ismember('recording_id',T.Properties.VariableNames)
            keys(r)=string(T.recording_id(r));
        end
    end
end
