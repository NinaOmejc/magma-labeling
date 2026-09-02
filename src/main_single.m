
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

        % EXTRACT OR LOAD FEATURES (manually checked breath peaks/troughs + SpO2)
        resp_feat = load_or_extract_respiratory_features(data, config);

        % DIAGNOSTIC RESPIRATORY AMPLITUDE REFERENCE (not used by detectors)
        resp_ref = compute_respiratory_reference(resp_feat, config);
        plot_respiratory_reference(resp_feat, resp_ref, config);

        %temp
        continue

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

        % Optional final manual event-interval editing.
        % Sigh is intentionally excluded because it has its own breath-level GUI.
        event_sets = struct( ...
            'shallowB', events_ShB, ...
            'irregB', events_IrB, ...
            'slowB', events_SlB, ...
            'rapidB', events_RaB, ...
            'asyncB', events_ReA, ...
            'desat', events_Des, ...
            'apnea', events_Apn, ...
            'CSR', events_CSR);
        [event_sets, manual_label_edit] = manual_edit_label_events(data, config, event_sets);
        
        events_ShB = event_sets.shallowB;
        events_IrB = event_sets.irregB;
        events_SlB = event_sets.slowB;
        events_RaB = event_sets.rapidB;
        events_ReA = event_sets.asyncB;
        events_Des = event_sets.desat;
        events_Apn = event_sets.apnea;
        events_CSR = event_sets.CSR;

        % JOIN EVENTS FOR SUBJECT, MEASUREMENT
        sub_events = merge_events({events_ShB, events_IrB, events_SlB, events_RaB, events_ReA, events_Des, events_Apn, events_Sigh, events_CSR});
        sub_events = normalize_event_types_and_meta(sub_events);
        
        N = size(data,1); 
        [label_mask, label_names] = events_to_time_mask(sub_events, N, config);
        diagnostic_signals = compute_label_diagnostic_signals(data, baseline, resp_feat, spo2_feat, config, diagnostics_ReA);
        rewritten_manual_label_figures = rewrite_changed_manual_label_figures( ...
            data, baseline, resp_feat, spo2_feat, diagnostic_signals, event_sets, manual_label_edit, config);
        plot_label_mask(label_mask, label_names, config);
        
        % SAVE
        results.subject = config.subject;
        results.measure = config.measure;
        results.events = sub_events;
        results.mask   = label_mask;
        results.label_names = label_names;
        results.resp_feat = resp_feat;
        results.resp_ref = resp_ref;
        results.spo2_feat = spo2_feat;
        results.diagnostic_signals = diagnostic_signals;
        results.manual_label_edit = manual_label_edit;
        results.rewritten_manual_label_figures = rewritten_manual_label_figures;
        results.baseline = baseline;
        results.input_config = config.input_config;
        results.config = config;
        save(fullfile(config.sub_results_path, config.sub_results_filename), '-struct', 'results');
        
        disp(['Successfully finished label detection for: Sub ' num2str(config.subject) ' | Measurement: ' num2str(config.measure) ])
    end
end

save([config.path_results_out, filesep, 'analysis_configuration.mat'], "config")
