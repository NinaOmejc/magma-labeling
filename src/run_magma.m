
function run_magma(base_config)
% RUN_MAGMA Execute the MAGMA pipeline for configured recordings.
% The immutable caller-resolved configuration is saved once before any
% recording-specific fields are added. Each recording then starts from a
% fresh copy of that base configuration.

mode = execution_mode(base_config);
if ~isfolder(base_config.path_results_out)
    mkdir(base_config.path_results_out);
end
config = base_config;
save(fullfile(base_config.path_results_out, ...
    'analysis_configuration.mat'), 'config');

%---- MEASUREMENT AND SUBJECT LOOPS
for isub = 1:length(base_config.subjects)
    for imeasure = 1:length(base_config.measurements)

        config = base_config;
        config.subject = base_config.subjects(isub);
        config.measure = base_config.measurements(imeasure);
        
        % LOAD DATA
        [data_raw, config, do_analysis] = load_raw_data(config);
        if ~do_analysis
            continue;
        end

        if strcmp(mode, 'review_only')
            result_file = fullfile( ...
                config.sub_results_path, config.sub_results_filename);
            existing_results = load(result_file);
            review_config = config;
            if isfield(existing_results, 'config') && ...
                    isfield(existing_results.config, 'detrend')
                review_config.detrend = existing_results.config.detrend;
            end
            review_config.detrend.do_plot = false;
            [data, review_config] = preprocess_data(data_raw, review_config);
            config.times = review_config.times;
            results = review_existing_results(data, existing_results, config);
            save_recording_results(results, data_raw, data, config);
            log_message(config, 1, ...
                'Successfully finished manual review for: Sub %d | Measurement: %d', ...
                config.subject, config.measure);
            continue;
        end

        config.execution.analysis_id = create_analysis_id(config);
        
        % PREPROCESS DATA
        log_message(config, 2, 'Preprocessing signals...');
        [data, config] = preprocess_data(data_raw, config);

        % RESPIRATORY CYCLES
        log_message(config, 2, 'Extracting respiratory cycles...');
        resp_cycles = load_or_extract_respiratory_cycles(data, config);

        % MODALITY-SPECIFIC REFERENCES FROM THE COMMON INTERVAL
        log_message(config, 2, 'Computing respiratory reference...');
        session_reference = get_session_reference_interval(size(data, 1), config);
        resp_ref = compute_respiratory_reference(data, resp_cycles, session_reference, config);
        plot_session_reference(data, resp_cycles, resp_ref, session_reference, config);

        % RESPIRATORY FEATURES (derived; no peak redetection)
        log_message(config, 2, 'Computing respiratory features...');
        resp_features = compute_respiratory_features(data, resp_cycles, resp_ref, config);

        % LABEL DETECTIONS
        log_message(config, 2, 'Detecting shallow breathing...');
        [events_shallow, candidates_shallow] = detect_shallow_breathing(data, resp_features, config);
        log_message(config, 2, 'Detecting deep breathing...');
        [events_deep, candidates_deep] = detect_deep_breathing(data, resp_features, config);
        log_message(config, 2, 'Detecting thoracic dominance...');
        [events_thoracic, candidates_thoracic] = detect_thoracic_dominant_breathing(data, resp_features, config);
        log_message(config, 2, 'Detecting irregular breathing...');
        [events_irregular, candidates_irregular] = detect_irregular_breathing(data, resp_features, config);
        log_message(config, 2, 'Detecting slow breathing...');
        [events_slow, candidates_slow] = detect_slow_breathing(data, resp_features, config);
        log_message(config, 2, 'Detecting rapid breathing...');
        [events_rapid, candidates_rapid] = detect_rapid_breathing(data, resp_features, config);
        log_message(config, 2, 'Detecting respiratory asynchrony...');
        [events_async, diagnostics_async] = detect_respiratory_asynchrony(data, session_reference, resp_cycles, config);
        log_message(config, 2, 'Detecting desaturation...');
        [events_desat, diagnostics_desat, spo2_ref] = detect_desaturation(data, session_reference, config);
        log_message(config, 2, 'Detecting apnea...');
        [events_apnea, diagnostics_apnea, candidates_apnea] = detect_apnea(data, resp_features, resp_ref, config);
        log_message(config, 2, 'Detecting sighs...');
        [events_sigh, diagnostics_sigh] = detect_sigh( ...
            data, resp_features, resp_cycles, config);
        log_message(config, 2, 'Detecting periodic breathing...');
        [events_periodic, diagnostics_periodic, candidates_periodic] = detect_periodic_breathing(data, resp_cycles, config);
 
        % FINALIZE LABELS
        log_message(config, 2, 'Building final label masks...');
        detections.events = struct( ...
            'shallow', events_shallow, ...
            'deep', events_deep, ...
            'slow', events_slow, ...
            'rapid', events_rapid, ...
            'irregular', events_irregular, ...
            'apnea', events_apnea, ...
            'sigh', events_sigh, ...
            'periodic', events_periodic, ...
            'thoracic', events_thoracic, ...
            'async', events_async, ...
            'desat', events_desat);
        detections.candidate_events = struct( ...
            'shallow', candidates_shallow, ...
            'deep', candidates_deep, ...
            'slow', candidates_slow, ...
            'rapid', candidates_rapid, ...
            'irregular', candidates_irregular, ...
            'apnea', candidates_apnea, ...
            'sigh', empty_candidate_events(), ...
            'periodic', candidates_periodic, ...
            'thoracic', candidates_thoracic, ...
            'async', empty_candidate_events(), ...
            'desat', empty_candidate_events());
        detections.diagnostics = struct( ...
            'async', diagnostics_async, ...
            'desat', diagnostics_desat, ...
            'apnea', diagnostics_apnea, ...
            'sigh', diagnostics_sigh, ...
            'periodic', diagnostics_periodic);
        detections.spo2_ref = spo2_ref;

        label_results = finalize_label_results( ...
            data, resp_cycles, resp_features, session_reference, detections, config);

        plot_label_mask(label_results.mask_automatic, label_results.label_names, config);
        
        % SAVE
        log_message(config, 2, 'Computing summary measures...');
        results = build_recording_results( ...
            config, resp_cycles, resp_ref, session_reference, resp_features, label_results);
        save_recording_results(results, data_raw, data, config);
        log_message(config, 1, ...
            'Successfully finished label detection for: Sub %d | Measurement: %d', ...
            config.subject, config.measure);
        log_message(config, 2, 'Done.');
    end
end
end
