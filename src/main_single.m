
%---- SETTINGS ----
config = get_config();

%---- MEASUREMENT AND SUBJECT LOOPS
for isub = 1:length(config.subjects)
    for imeasure = 1:length(config.measurements)

        config.subject = config.subjects(isub);
        config.measure = config.measurements(imeasure);
        
        % LOAD DATA
        [data_raw, config, do_analysis] = load_raw_data(config);
        if ~do_analysis
            continue;
        end
        
        % PREPROCESS DATA
        [data, config] = preprocess_data(data_raw, config);

        % RESPIRATORY CYCLES
        resp_cycles = load_or_extract_respiratory_cycles(data, config);

        % MODALITY-SPECIFIC REFERENCES FROM THE COMMON INTERVAL
        session_reference = get_session_reference_interval(size(data, 1), config);
        resp_ref = compute_respiratory_reference(resp_cycles, session_reference, config);
        spo2_ref = compute_spo2_reference(data, session_reference, config);
        plot_session_reference(data, resp_cycles, resp_ref, spo2_ref, session_reference, config);

        % RESPIRATORY FEATURES (derived; no peak redetection)
        resp_features = compute_respiratory_features(data, resp_cycles, resp_ref, config);

        % LABEL DETECTIONS        
        [events_shallow, boundary_shallow] = detect_shallow_breathing(data, resp_features, config);
        [events_deep, boundary_deep] = detect_deep_breathing(data, resp_features, config);
        [events_thoracic, boundary_thoracic] = detect_thoracic_dominant_breathing(data, resp_features, config);
        [events_irregular, boundary_irregular] = detect_irregular_breathing(data, resp_features, config);
        [events_slow, boundary_slow] = detect_slow_breathing(data, resp_features, config);
        [events_rapid, boundary_rapid] = detect_rapid_breathing(data, resp_features, config);
        [events_async, diagnostics_async] = detect_respiratory_asynchrony(data, session_reference, resp_cycles, config);
        [events_desat, diagnostics_desat] = detect_desaturation(data, spo2_ref, session_reference, config);
        [events_apnea, diagnostics_apnea, boundary_apnea] = detect_apnea(data, resp_features, session_reference, config);
        [~, diagnostics_sigh, sigh_review] = detect_sigh(data, resp_features, resp_cycles, spo2_ref, session_reference, diagnostics_desat, config);
        [events_csr, diagnostics_csr] = detect_periodic_breathing(data, resp_cycles, config);
 
        % FINALIZE LABELS
        detections.events = struct( ...
            'shallow', events_shallow, ...
            'deep', events_deep, ...
            'slow', events_slow, ...
            'rapid', events_rapid, ...
            'irregular', events_irregular, ...
            'apnea', events_apnea, ...
            'csr', events_csr, ...
            'thoracic', events_thoracic, ...
            'async', events_async, ...
            'desat', events_desat);
        detections.boundaries = struct( ...
            'shallow', boundary_shallow, ...
            'deep', boundary_deep, ...
            'slow', boundary_slow, ...
            'rapid', boundary_rapid, ...
            'irregular', boundary_irregular, ...
            'apnea', boundary_apnea, ...
            'thoracic', boundary_thoracic);
        detections.diagnostics = struct( ...
            'async', diagnostics_async, ...
            'desat', diagnostics_desat, ...
            'apnea', diagnostics_apnea, ...
            'sigh', diagnostics_sigh, ...
            'csr', diagnostics_csr);

        label_results = finalize_label_results( ...
            data, resp_cycles, resp_features, spo2_ref, session_reference, detections, sigh_review, config);

        plot_label_mask(label_results.mask_automatic, label_results.label_names, config);
        
        % SAVE
        results = build_recording_results( ...
            config, resp_cycles, resp_ref, session_reference, spo2_ref, resp_features, label_results);
        save_recording_results(results, data_raw, data, config);
        disp(['Successfully finished label detection for: Sub ' num2str(config.subject) ' | Measurement: ' num2str(config.measure) ])
    end
end

save([config.path_results_out, filesep, 'analysis_configuration.mat'], "config")
