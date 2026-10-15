function [source, audit] = normalize_master_source_keys(source, config)
% NORMALIZE_MASTER_SOURCE_KEYS Validate recording identities independently of data.
    T = source.table; s = source.spec; n = height(T);
    audit = master_audit_entry();
    subject_col = master_source_column(source,s.subject_column);
    recording_col = master_source_column(source,s.recording_column);
    measure_col = master_source_column(source,s.measure_column);
    group_col = master_source_column(source,s.group_column);
    date_col = master_source_column(source,s.study_date_column);
    ids = strings(n,1); recordings = strings(n,1); measures = nan(n,1);
    group_codes = nan(n,1); study_dates = NaT(n,1);
    for r = 1:n
        ids(r) = master_subject_id(master_table_value(T,subject_col,r));
        if ids(r)==""
            audit = [audit; issue('warning','unresolved_subject_id',r,subject_col,'Source row retained without a guessed identity.')]; %#ok<AGROW>
        end
        if ismember(s.target,{'Physiology','Label_burden','Phenotypes'})
            measures(r) = s.fixed_measure;
            if ~isempty(measure_col)
                measures(r) = str2double(master_cell_text(master_table_value(T,measure_col,r)));
            end
            if ~ismember(measures(r),[1 2])
                audit = [audit; issue('error','invalid_measure',r,'measure','Within-visit measure must be 1 or 2.')]; %#ok<AGROW>
            end
            expected = ids(r) + "_M" + string(measures(r));
            if isempty(recording_col)
                if ids(r)~="" && ismember(measures(r),[1 2]), recordings(r) = expected; end
            else
                recordings(r) = master_cell_text(master_table_value(T,recording_col,r));
                if recordings(r)~=expected
                    audit = [audit; issue('error','recording_key_mismatch',r,'recording_id','Original recording ID disagrees with subject/measure; no rewrite applied.')]; %#ok<AGROW>
                end
            end
        end
        if ~isempty(group_col)
            value = lower(master_cell_text(master_table_value(T,group_col,r)));
            if strcmp(s.target,'Questionnaire')
                if value=="0", group_codes(r)=0; elseif value=="1", group_codes(r)=1;
                elseif ~master_value_missing(value)
                    audit = [audit; issue('warning','invalid_group_code',r,group_col,'Questionnaire grp must be 0 or 1; original value retained.')]; %#ok<AGROW>
                end
            else
                if value=="control", group_codes(r)=0; elseif value=="patient", group_codes(r)=1;
                elseif ~master_value_missing(value)
                    audit = [audit; issue('warning','unrecognized_source_group',r,group_col,'Original classification retained without reinterpretation.')]; %#ok<AGROW>
                end
            end
        end
        if ~isempty(date_col)
            raw_date = master_table_value(T,date_col,r);
            if ~master_value_missing(raw_date)
                if isdatetime(raw_date)
                    study_dates(r) = dateshift(raw_date,'start','day');
                else
                    for f = 1:numel(config.study_date_formats)
                        try
                            study_dates(r) = datetime(master_cell_text(raw_date),'InputFormat',config.study_date_formats{f});
                            break;
                        catch
                        end
                    end
                    if isnat(study_dates(r))
                        audit = [audit; issue('warning','unparsed_study_date',r,date_col,'No configured complete date format matched; original date retained.')]; %#ok<AGROW>
                    end
                end
            end
        end
    end
    T.source_subject_id = ids;
    T.import_group_code = group_codes;
    T.import_study_date = study_dates;
    if strcmp(s.target,'Questionnaire')
        T.questionnaire_record_id = string(s.source_id) + ":" + string(s.sheet) + ":" + T.import_source_row;
        for r=1:n
            prior=find(ids(1:r-1)==ids(r) & ~ismissing(ids(1:r-1)));
            for p=prior'
                if isequaln(source.raw_cells(source.source_rows(p),:),source.raw_cells(source.source_rows(r),:))
                    audit=[audit; issue('warning','duplicate_questionnaire_source_record',r, ...
                        'questionnaire_record_id','Identical original questionnaire rows are both preserved; verify the source duplication.')]; %#ok<AGROW>
                    break;
                end
            end
        end
        start = find(source.mapping.original_name==string(config.baseline_content_start),1);
        finish = find(source.mapping.original_name==string(config.baseline_content_end),1);
        % Unrecognized future questionnaire schemas are never called structurally absent.
        T.import_baseline_content_present = nan(n,1);
        if ~isempty(start) && ~isempty(finish) && start<=finish
            T.import_baseline_content_present = false(n,1);
            for r=1:n
                for c=start:finish
                    value = master_table_value(T,char(source.mapping.output_column(c)),r);
                    T.import_baseline_content_present(r) = T.import_baseline_content_present(r) || ~master_value_missing(value);
                end
            end
        end
    elseif strcmp(s.target,'StressTest')
        % Test no. belongs to the source test, never to respiratory M1/M2.
        % Keep all observations, including repeated tests and unavailable rows.
        T.stress_test_record_id = string(s.source_id) + ":" + string(s.sheet) + ":" + T.import_source_row;
        for r=1:n
            prior=find(ids(1:r-1)==ids(r) & ids(r)~="");
            for p=prior'
                if isequaln(source.raw_cells(source.source_rows(p),:),source.raw_cells(source.source_rows(r),:))
                    audit=[audit; issue('warning','duplicate_stress_test_source_record',r, ...
                        'stress_test_record_id','Identical original stress-test rows are both preserved; verify the source duplication.')]; %#ok<AGROW>
                    break;
                end
            end
        end
    else
        if ~isempty(measure_col) && ~strcmp(measure_col,'measure')
            % Preserve the original differently named key alongside the standard key.
            T.measure = measures;
        elseif ~ismember('measure',T.Properties.VariableNames)
            T.measure = measures;
        elseif ~isequaln(T.measure,measures)
            T.original_measure = T.measure; T.measure = measures;
        end
        T.recording_id = recordings;
    end
    source.table = T;

    function row = issue(severity, code, r, field, detail)
        row = master_audit_entry(severity,code,s.target,ids(r),field,s.file,s.sheet,source.source_rows(r),detail);
    end
end
