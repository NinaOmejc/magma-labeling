function key = master_primary_key(T, target)
% MASTER_PRIMARY_KEY No joins on participant alone for recording-level data.
    switch target
        case 'Subjects', key=T.participant_id;
        case 'Questionnaire', key=T.questionnaire_record_id;
        case 'StressTest', key=T.stress_test_record_id;
        case 'Physiology', key=T.recording_id;
        case 'Label_burden'
            key=T.recording_id + "|" + string(T.label);
        case 'Phenotypes'
            key=T.recording_id + "|" + string(T.annotation_layer);
        otherwise, error('MAGMA:Metadata:Target','Unsupported table: %s',target);
    end
end
