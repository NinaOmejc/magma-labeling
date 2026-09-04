
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
        [events_ShB, boundary_ShB] = detect_shallow_breathing(data, resp_features, config);
        [events_DeB, boundary_DeB] = detect_deep_breathing(data, resp_features, config);
        [events_TDB, boundary_TDB] = detect_thoracic_dominant_breathing(data, resp_features, config);
        [events_IrB, boundary_IrB] = detect_irregular_breathing(data, resp_features, config);
        [events_SlB, boundary_SlB] = detect_slow_breathing(data, resp_features, config);
        [events_RaB, boundary_RaB] = detect_rapid_breathing(data, resp_features, config);
        [events_ReA, diagnostics_ReA] = detect_respiratory_asynchrony(data, session_reference, resp_cycles, config);
        [events_Des, diagnostics_Des] = detect_desaturation(data, spo2_ref, session_reference, config);
        [events_Apn, diagnostics_Apn, boundary_Apn] = detect_apnea(data, resp_features, session_reference, config);
        [~, diagnostics_Sigh, sigh_review] = detect_sigh(data, resp_features, resp_cycles, spo2_ref, session_reference, diagnostics_Des, config);
        [events_CSR, diagnostics_CSR] = detect_periodic_breathing(data, resp_cycles, config);
 
        % Freeze automatic annotations before any interval editing.
        % Sigh is separate because it has its own breath-level GUI, whose
        % automatic candidates are retained in sigh_review.weak_events.
        weak_event_sets = struct( ...
            'shallow', events_ShB, ...
            'deep', events_DeB, ...
            'thoracic', events_TDB, ...
            'irregular', events_IrB, ...
            'slow', events_SlB, ...
            'rapid', events_RaB, ...
            'async', events_ReA, ...
            'desat', events_Des, ...
            'apnea', events_Apn, ...
            'csr', events_CSR);
        N = size(data,1);
        [reviewed_event_sets, manual_label_edit] = manual_edit_label_events(data, config, weak_event_sets);
        annotations = assemble_annotation_layers(weak_event_sets, reviewed_event_sets, manual_label_edit, sigh_review, N, config);
        events_weak = annotations.events_weak;
        mask_weak = annotations.mask_weak;
        events_reviewed = annotations.events_reviewed;
        mask_reviewed = annotations.mask_reviewed;
        gold_review_mask = annotations.gold_review_mask;
        label_names = annotations.label_names;

        [label_available, label_availability_reason] = ...
            compute_label_availability(label_names, resp_features, diagnostics_Des, ...
                diagnostics_ReA, diagnostics_Apn, diagnostics_Sigh, diagnostics_CSR);
        [label_assessable_mask, label_assessability_info] = ...
            compute_label_assessable_mask(N, label_names, label_available, ...
                diagnostics_Des, diagnostics_ReA, config);
        diagnostic_signals = compute_label_diagnostic_signals( ...
            resp_features, spo2_ref, diagnostics_Des, config, diagnostics_ReA, ...
            diagnostics_Apn, diagnostics_Sigh, diagnostics_CSR);
        detector_diagnostics = struct( ...
            'respiratory_asynchrony', diagnostics_ReA, ...
            'desaturation', diagnostics_Des, ...
            'apnea', diagnostics_Apn, ...
            'sigh', diagnostics_Sigh, ...
            'periodic_breathing', diagnostics_CSR);
        label_burden_weak = compute_recording_label_burden( ...
            mask_weak, label_names, label_available, events_weak, config.fs, ...
            label_assessable_mask);
        label_overlap_summary_weak = compute_label_overlap_summary( ...
            mask_weak, label_names, label_available, config.fs, label_assessable_mask);
        label_evidence_summary_weak = build_label_evidence_summary( ...
            label_names, label_available, label_availability_reason, ...
            resp_features, diagnostic_signals, detector_diagnostics, label_burden_weak);

        [reviewed_assessable_mask, reviewed_available, reviewed_reasons] = ...
            compute_reviewed_label_availability( ...
                label_available, label_availability_reason, ...
                label_assessable_mask, gold_review_mask);
        label_burden_reviewed = compute_recording_label_burden( ...
            mask_reviewed, label_names, reviewed_available, events_reviewed, ...
            config.fs, reviewed_assessable_mask);
        label_overlap_summary_reviewed = compute_label_overlap_summary( ...
            mask_reviewed, label_names, reviewed_available, config.fs, ...
            reviewed_assessable_mask);
        label_evidence_summary_reviewed = build_label_evidence_summary( ...
            label_names, reviewed_available, reviewed_reasons, resp_features, ...
            diagnostic_signals, detector_diagnostics, label_burden_reviewed);
        db_phenotype_evidence = build_db_phenotype_evidence_bundle( ...
            label_burden_weak, label_overlap_summary_weak, ...
            label_evidence_summary_weak, label_burden_reviewed, ...
            label_overlap_summary_reviewed, label_evidence_summary_reviewed);

        event_boundary_info = struct( ...
            'version', 'label_boundary_provenance_v1', ...
            'shallow', boundary_ShB, 'deep', boundary_DeB, ...
            'slow', boundary_SlB, 'rapid', boundary_RaB, ...
            'irregular', boundary_IrB, ...
            'apnea', boundary_Apn, ...
            'sigh', standard_boundary('sigh', 'detect_sigh', ...
                sigh_review.weak_events, 'breath_midpoint_cell', 1/config.fs, ...
                'automatic_sigh_candidate_breath'), ...
            'csr', standard_boundary('csr', 'detect_periodic_breathing', ...
                events_CSR, 'cycle_trough_to_trough', 1/config.fs, ...
                'breath_amplitude_envelope_cycles'), ...
            'thoracic', boundary_TDB, ...
            'async', standard_boundary('async', 'detect_respiratory_asynchrony', ...
                events_ReA, 'specialized_local_phase_coherence', NaN, ...
                'time_localized_wavelet_phase_coherence'), ...
            'desat', standard_boundary('desat', 'detect_desaturation', ...
                events_Des, 'native_spo2_threshold_run', 1/config.fs, 'native_spo2_samples'));
        rewritten_manual_label_figures = rewrite_changed_manual_label_figures( ...
            data, spo2_ref, session_reference, resp_cycles, diagnostics_Des, ...
            diagnostic_signals, reviewed_event_sets, manual_label_edit, config);
        plot_label_mask(mask_weak, label_names, config);
        
        % SAVE
        results = struct();
        results.subject = config.subject;
        results.measure = config.measure;
        results.annotation_schema_version = annotations.version;
        results.events_weak = events_weak;
        results.mask_weak = mask_weak;
        results.events_reviewed = events_reviewed;
        results.mask_reviewed = mask_reviewed;
        results.gold_review_mask = gold_review_mask;
        results.review_status = annotations.review_status;
        results.review_scope = annotations.review_scope;
        results.review_history = annotations.review_history;
        results.review_provenance = annotations.review_provenance;
        % Backward-compatible aliases now point to immutable automatic annotations.
        results.events = events_weak;
        results.mask = mask_weak;
        results.label_names = label_names;
        results.label_available = label_available;
        results.label_availability_reason = label_availability_reason;
        results.label_assessable_mask = label_assessable_mask;
        results.label_assessability_info = label_assessability_info;
        results.label_reviewed_available = reviewed_available;
        results.label_reviewed_availability_reason = reviewed_reasons;
        results.label_reviewed_assessable_mask = reviewed_assessable_mask;
        results.label_schema_version = config.label_schema_version;
        results.resp_cycles = resp_cycles;
        results.resp_ref = resp_ref;
        results.session_reference = session_reference;
        results.spo2_ref = spo2_ref;
        results.resp_features = resp_features;
        results.diagnostic_signals = diagnostic_signals;
        results.detector_diagnostics = detector_diagnostics;
        results.label_burden_weak = label_burden_weak;
        results.label_burden_reviewed = label_burden_reviewed;
        results.label_overlap_summary_weak = label_overlap_summary_weak;
        results.label_overlap_summary_reviewed = label_overlap_summary_reviewed;
        results.label_evidence_summary_weak = label_evidence_summary_weak;
        results.label_evidence_summary_reviewed = label_evidence_summary_reviewed;
        % Backward-compatible summary aliases use weak provenance.
        results.label_burden = label_burden_weak;
        results.label_overlap_summary = label_overlap_summary_weak;
        results.label_evidence_summary = label_evidence_summary_weak;
        results.db_phenotype_evidence = db_phenotype_evidence;
        results.event_boundary_info = event_boundary_info;
        results.manual_label_edit = manual_label_edit;
        results.manual_sigh_review = sigh_review;
        results.rewritten_manual_label_figures = rewritten_manual_label_figures;
        results.input_config = config.input_config;
        results.config = config;
        results.export_schema_version = get_config_value( ...
            config, 'HDF5', 'export_schema_version', 'magma_ml_hdf5_v3');
        results.upstream_input_preprocessing = get_config_value( ...
            config, 'HDF5', 'upstream_input_preprocessing', ...
            'external / not fully documented');
        save(fullfile(config.sub_results_path, config.sub_results_filename), '-struct', 'results');
        if get_config_value(config, 'HDF5', 'enabled', true)
            hdf5_suffix = get_config_value(config, 'HDF5', ...
                'filename_suffix', '_labels.h5');
            hdf5_filename = fullfile(config.sub_results_path, ...
                sprintf('Sub%d_M%d%s', config.subject, config.measure, hdf5_suffix));
            export_results_hdf5(hdf5_filename, results, data_raw, data);
        end
        
        disp(['Successfully finished label detection for: Sub ' num2str(config.subject) ' | Measurement: ' num2str(config.measure) ])
    end
end

save([config.path_results_out, filesep, 'analysis_configuration.mat'], "config")

function info = standard_boundary(label, detector, events, method, uncertainty, source)
    info = make_label_boundary_info(label, detector, method, events, events, ...
        uncertainty, source, [], [], []);
    if isnan(uncertainty)
        info.temporal_resolution_note = ...
            'detector-specific timing; no unsupported scalar uncertainty assigned';
    else
        info.temporal_resolution_note = '';
    end
end
