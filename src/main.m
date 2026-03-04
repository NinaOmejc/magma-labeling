
%---- SETTINGS ----
config = get_config();
subjects = [42];
conditions = [1, 2]; % pre, post

%---- CONDITION AND SUBJECT LOOPS
for isub = 1:length(subjects)
    for icond = 1:length(conditions)
        config.subject = subjects(isub);
        config.condition = conditions(icond);
        disp(['Working on: Sub ' num2str(config.subject) ' | Cond: ' num2str(config.condition) ])
        
        % LOAD DATA
        filename = ['ECG1_ECG2_SpO2_RespL_BP_RespD_fs200_Sub' num2str(config.subject) '_Pom' num2str(config.condition) '_DeTr_Norm.dat'];
        data = load([config.path_data_in filesep filename]);
        data = reshape(data, [], 6);
        
        % PREPARE OUTPUT FOLDER
        config.sub_results_path = [config.path_results_out filesep 'Sub' num2str(config.subject) '_Cond' num2str(config.condition)];
        isfolder(config.sub_results_path) || mkdir(config.sub_results_path);
        
        % PLOT RAW DATA
        [fig, ax, ph] = plot_raw_data(data, config);
        
        % COMPUTE BASELINE 
        baseline = compute_baseline(data, config);
        
        % EXTRACT FEATURES (detect breathing peaks + per-breath amplitudes)
        [breaths_lungs, breaths_diaph] = extract_respiration_features(data, baseline, config);
        spo2_feat = extract_spo2_features(data, baseline, config);
        
        % LABEL DETECTIONS
        events_ShB = detect_shallow_breathing(data, baseline, breaths_lungs, breaths_diaph, spo2_feat, config);
        events_IrB = detect_irregular_breathing(data, breaths_lungs, breaths_diaph, config);
        events_SlB = detect_slow_breathing(data, baseline, breaths_lungs, breaths_diaph, spo2_feat, config);
        events_RaB = detect_rapid_breathing(data, baseline, breaths_lungs, breaths_diaph, spo2_feat, config);
        events_ReA = detect_respiratory_asynchrony(data, config);
        events_Des = detect_desaturation(data, baseline, spo2_feat, config);
        events_Apn = detect_apnea(data, baseline, breaths_lungs, breaths_diaph, spo2_feat, config);
        events_Sig = detect_sigh(data, breaths_lungs, breaths_diaph, config);
        
        % JOIN EVENTS FOR SUBJECT, CONDITION
        sub_events = merge_events({events_ShB, events_IrB, events_SlB, events_RaB, ...
                                   events_ReA, events_Des, events_Apn, events_Sig});
        sub_events = normalize_event_types_and_meta(sub_events);
        
        N = size(data,1); 
        label_mask = events_to_time_mask(sub_events, N);
        
        % SAVE
        results.subject = config.subject;
        results.condition = config.condition;
        results.events = sub_events;
        results.mask   = label_mask;
        results.baseline = baseline;
        results.config = config;
        save(fullfile(config.sub_results_path,'labels_results.mat'), '-struct', 'results');
    end
end
