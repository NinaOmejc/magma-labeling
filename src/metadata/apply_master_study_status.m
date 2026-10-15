function [tables, audit, source] = apply_master_study_status(tables, identities, audit, config)
% APPLY_MASTER_STUDY_STATUS Current confirmed administrative status, without row removal.
% Confirmation date is provenance, never an inferred dropout/recording date.
    S=tables.Subjects;
    S.study_status=repmat("unknown",height(S),1);
    S.study_status_confirmed_on=NaT(height(S),1);
    S.study_status_provenance=strings(height(S),1);
    S.study_status_notes=strings(height(S),1);
    source=struct('file','','table',table());
    if ~isfield(config,'study_status_overrides_file') || ~isfile(config.study_status_overrides_file)
        tables.Subjects=S; return;
    end
    file=char(config.study_status_overrides_file);
    T=readtable(file,'Delimiter',',','ReadVariableNames',true,'NumHeaderLines',0, ...
        'TextType','string','VariableNamingRule','preserve');
    source=struct('file',file,'table',T);
    required={'source_subject_id','study_status','confirmed'};
    if ~all(ismember(required,T.Properties.VariableNames))
        error('MAGMA:Metadata:StudyStatus','Study status overrides require source_subject_id, study_status, confirmed.');
    end
    for r=1:height(T)
        confirmed=lower(master_cell_text(master_table_value(T,'confirmed',r)));
        if ~ismember(confirmed,["true","1","yes"]), continue; end
        id=master_subject_id(master_table_value(T,'source_subject_id',r));
        status=lower(master_cell_text(master_table_value(T,'study_status',r)));
        visit=find(identities.source_subject_id==id,1); participant=[];
        if ~isempty(visit), participant=find(S.participant_id==identities.participant_id(visit),1); end
        if isempty(participant)
            audit=[audit; entry('warning','unused_study_status_override',id,r,'No known participant matched this source ID; override retained.')]; %#ok<AGROW>
            continue;
        end
        if ~ismember(status,["dropped_out","withdrawn","active","completed"])
            audit=[audit; entry('error','invalid_study_status',id,r,'Use a documented current study status: dropped_out, withdrawn, active, completed.')]; %#ok<AGROW>
            continue;
        end
        if S.study_status(participant)~="unknown" && S.study_status(participant)~=status
            audit=[audit; entry('error','conflicting_study_status',id,r,'One canonical participant has contradictory confirmed current study statuses.')]; %#ok<AGROW>
            continue;
        end
        date=NaT;
        if ismember('confirmed_on',T.Properties.VariableNames)
            raw=master_table_value(T,'confirmed_on',r);
            if ~master_value_missing(raw)
                if isdatetime(raw), date=raw;
                else
                    try, date=datetime(master_cell_text(raw),'InputFormat','yyyy-MM-dd');
                    catch
                        audit=[audit; entry('error','invalid_status_confirmation_date',id,r,'Confirmation date must be a complete yyyy-MM-dd date.')]; %#ok<AGROW>
                        continue;
                    end
                end
            end
        end
        S.study_status(participant)=status;
        S.study_status_confirmed_on(participant)=date;
        S.study_status_provenance(participant)=string(file)+":row "+string(r+1);
        if ismember('notes',T.Properties.VariableNames)
            S.study_status_notes(participant)=master_cell_text(master_table_value(T,'notes',r));
        end
        if status=="dropped_out"
            audit=[audit; entry('info','study_dropout_confirmed',S.participant_id(participant),r, ...
                'User-confirmed study dropout; original source rows and scientific values are retained.')]; %#ok<AGROW>
        end
    end
    S.study_status_confirmed_on.Format='yyyy-MM-dd';
    tables.Subjects=S;
    absence_codes=["missing_baseline_questionnaire","missing_source_modality","visit_without_physiology"];
    for a=1:height(audit)
        if ~ismember(audit.issue(a),absence_codes), continue; end
        key=erase(audit.key(a),'Visit_');
        key=regexprep(key,'_M[12]$','');
        id=master_subject_id(key);
        visit=find(identities.source_subject_id==id,1);
        if isempty(visit), continue; end
        participant=find(S.participant_id==identities.participant_id(visit),1);
        if ~isempty(participant) && S.study_status(participant)=="dropped_out"
            audit.severity(a)="info";
            audit.detail(a)=audit.detail(a)+" Participant has a user-confirmed study dropout; source-data absence remains recorded.";
        end
    end

    function row=entry(severity,code,id,r,detail)
        row=master_audit_entry(severity,code,'Subjects',id,'study_status',file,'',r+1,detail);
    end
end
