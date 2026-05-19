
%---- SETTINGS ----
subjects = 80:81;
remove_subjects = [3 30 91];
subjects(ismember(subjects, remove_subjects)) = [];

measurements = [1, 2]; % 1: pre-rehab-pre-stress, 2: pre-rehab-post-stress, 3:post-rehab-pre-stress, 4:post-rehab-post-stress

% add src to path
src_root = fileparts(mfilename('fullpath'));
if ~isempty(src_root)
    addpath(genpath(src_root));
end

% load config structure
config = get_config();

%---- MEASUREMENT AND SUBJECT LOOPS
for isub = 1:length(subjects)
    for imeasure = 1:length(measurements)
        config.subject = subjects(isub);
        config.measure = measurements(imeasure);
        
        % LOAD DATA
        [data_raw, config, do_analysis] = load_raw_data(config);
        if ~do_analysis
            continue;
        end
        
        % PREPROCESS DATA
        [data, config] = preprocess_data(data_raw, config);

        % columns = [6];
        % trange = [2 4];
        % data = modify_data_to_test(data, config.new_fs, columns, trange, 'shallow_breathing', true);

        % EXTRACT OR LOAD FEATURES (manually checked breath peaks/troughs + SpO2)
        resp_feat = load_or_extract_respiratory_features(data, config);

        % COMPUTE BASELINES
        baseline = compute_baseline(data, config);
        baseline = add_rolling_resp_baseline(baseline, resp_feat, size(data,1), config);
        
        % EXTRACT SPO2 FEATURES
        spo2_feat = extract_spo2_features(data, baseline, config);

        % LABEL DETECTIONS
        events_ShB = detect_shallow_breathing(data, baseline, resp_feat, spo2_feat, config);
        events_IrB = detect_irregular_breathing(data, resp_feat, config);
        events_SlB = detect_slow_breathing(data, baseline, resp_feat, spo2_feat, config);
        events_RaB = detect_rapid_breathing(data, baseline, resp_feat, spo2_feat, config);
        [events_ReA, diagnostics_ReA] = detect_respiratory_asynchrony(data, baseline, resp_feat, config);
        events_Des = detect_desaturation(data, baseline, spo2_feat, config);
        events_Apn = detect_apnea(data, baseline, resp_feat, spo2_feat, config);
        events_Sigh = detect_sigh(data, baseline, resp_feat, spo2_feat, config);
        events_CSR = detect_periodic_breathing(data, resp_feat, config);

        % JOIN EVENTS FOR SUBJECT, MEASUREMENT
        sub_events = merge_events({events_ShB, events_IrB, events_SlB, events_RaB, events_ReA, events_Des, events_Apn, events_Sigh, events_CSR});
        sub_events = normalize_event_types_and_meta(sub_events);
        
        N = size(data,1); 
        [label_mask, label_names] = events_to_time_mask(sub_events, N, config);
        plot_label_mask(label_mask, label_names, config);
        diagnostic_signals = compute_label_diagnostic_signals(data, baseline, resp_feat, spo2_feat, config, diagnostics_ReA);
        
        % if ~isempty(events_IrB)
        %     disp(['Found a subject with irr breathing. Its ' num2str(config.subject) ' | M ' num2str(config.measure)])
        % end

        % SAVE
        results.subject = config.subject;
        results.measure = config.measure;
        results.events = sub_events;
        results.mask   = label_mask;
        results.label_names = label_names;
        results.resp_feat = resp_feat;
        results.spo2_feat = spo2_feat;
        results.diagnostic_signals = diagnostic_signals;
        results.baseline = baseline;
        results.config = config;
        save(fullfile(config.sub_results_path, config.sub_results_filename), '-struct', 'results');
        
        disp(['Successfully finished label detection for: Sub ' num2str(config.subject) ' | Measurement: ' num2str(config.measure) ])
    end
end

save([config.path_results_out, filesep, 'analysis_configuration.mat'], "config")
