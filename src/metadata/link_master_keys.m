function tables = link_master_keys(tables, identities)
% LINK_MASTER_KEYS Many-to-one lookup, preserving row count and recording IDs.
    if numel(unique(identities.source_subject_id))~=height(identities)
        error('MAGMA:Metadata:IdentityKey','Identity map must have unique source_subject_id.');
    end
    targets=master_table_names(tables); targets(strcmp(targets,'Subjects'))=[];
    for t=1:numel(targets)
        name=targets{t}; T=tables.(name); count=height(T);
        [matched,index]=ismember(T.source_subject_id,identities.source_subject_id);
        T.participant_id=strings(count,1); T.visit_id=strings(count,1);
        T.visit_number=nan(count,1);
        T.participant_id(matched)=identities.participant_id(index(matched));
        T.visit_id(matched)=identities.visit_id(index(matched));
        T.visit_number(matched)=identities.visit_number(index(matched));
        if strcmp(name,'StressTest')
            keys={'participant_id','source_subject_id','visit_id','visit_number','stress_test_record_id'};
        elseif ~strcmp(name,'Questionnaire')
            T.longitudinal_measure_number=2*(T.visit_number-1)+T.measure;
            T.longitudinal_measure=strings(count,1);
            known=isfinite(T.longitudinal_measure_number);
            T.longitudinal_measure(known)="M"+string(T.longitudinal_measure_number(known));
            keys={'participant_id','source_subject_id','visit_id','visit_number','measure', ...
                'longitudinal_measure','longitudinal_measure_number','recording_id'};
        else
            keys={'participant_id','source_subject_id','visit_id','visit_number','questionnaire_record_id'};
        end
        rest=setdiff(T.Properties.VariableNames,keys,'stable');
        tables.(name)=T(:,[keys rest]);
        assert(height(tables.(name))==count,'MAGMA:Metadata:RowMultiplication','Identity lookup changed row count.');
    end
end
