
%---- SETTINGS ----
config = get_config();

subjects = 1:100;
remove_subjects = [3 30 91];
subjects(ismember(subjects, remove_subjects)) = [];

measurements = [1, 2]; % 1: pre-rehab-pre-stress, 2: pre-rehab-post-stress, 3:post-rehab-pre-stress, 4:post-rehab-post-stress

%---- CONDITION AND SUBJECT LOOPS
for isub = 1:length(subjects)
    for imeasure = 1:length(measurements)
        config.subject = subjects(isub);
        config.measure = measurements(imeasure);
        
        % LOAD DATA
        [data_raw, config, do_analysis] = load_raw_data(config);
        if ~do_analysis
            continue;
        end
        
        % ADDITIONAL ROLLING DETREND
        [data, ~] = detrend_flow_flexible(data_raw, config);

        % columns = [6];
        % trange = [2 4];
        % data = modify_data_to_test(data, config.fs, columns, trange, 'shallow_breathing', true);

        % COMPUTE BASELINES
        baseline = compute_baseline(data, config);
        
        % EXTRACT FEATURES (detect breathing peaks + per-breath amplitudes)
        [breaths_lungs, breaths_diaph] = extract_respiration_features(data, baseline, config);
        spo2_feat = extract_spo2_features(data, baseline, config);

        baseline = add_rolling_resp_baseline(baseline, breaths_lungs, breaths_diaph, size(data,1), config);

        % LABEL DETECTIONS
        % events_ShB = detect_shallow_breathing(data, baseline, breaths_lungs, breaths_diaph, spo2_feat, config);
        % events_IrB = detect_irregular_breathing(data, breaths_lungs, breaths_diaph, config);
        % events_SlB = detect_slow_breathing(data, baseline, breaths_lungs, breaths_diaph, spo2_feat, config);
        % events_RaB = detect_rapid_breathing(data, baseline, breaths_lungs, breaths_diaph, spo2_feat, config);
        % events_ReA = detect_respiratory_asynchrony(data, config);
        % events_Des = detect_desaturation(data, baseline, spo2_feat, config);
        % events_Apn = detect_apnea(data, baseline, breaths_lungs, breaths_diaph, spo2_feat, config);
        events_Sigh = detect_sigh(data, breaths_lungs, breaths_diaph, config);

        % JOIN EVENTS FOR SUBJECT, CONDITION
        % sub_events = merge_events({events_ShB, events_IrB, events_SlB, events_RaB, ...
        %                            events_ReA, events_Des, events_Apn, events_Sigh});
        % sub_events = normalize_event_types_and_meta(sub_events);
        % 
        N = size(data,1); 
        % label_mask = events_to_time_mask(sub_events, N);
        % 
        % if ~isempty(events_IrB)
        %     disp(['Found a subject with irr breathing. Its ' num2str(config.subject) ' | M ' num2str(config.measure)])
        % end

        % SAVE
        % results.subject = config.subject;
        % results.condition = config.measure;
        % results.events = sub_events;
        % results.mask   = label_mask;
        % results.baseline = baseline;
        % results.config = config;
        % save(fullfile(config.sub_results_path, config.sub_results_filename), '-struct', 'results');
    end
end
