function tests = test_example_pipeline_smoke
% Test I: non-interactive preprocessing and breath extraction smoke test.
    tests = functiontests(localfunctions);
end

function testExampleRecordingRunsAtMasterRate(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    example_file = fullfile(repo_root, 'example_data', ...
        'ECG1_ECG2_SpO2_RespL_BP_RespD_fs200_Sub42_Pom1_DeTr_Norm.dat');
    assumeTrue(testCase, isfile(example_file), 'Example recording is not available.');

    output_dir = tempname;
    mkdir(output_dir);
    cleanup_dir = onCleanup(@() rmdir(output_dir, 's'));
    config = make_test_config(output_dir);
    config.subject = 42;
    config.measure = 1;
    config.overwrite_features = true;

    n_rows = 120 * config.fs;
    data_raw = read_first_rows(example_file, numel(config.data_columns), n_rows);
    verifyEqual(testCase, size(data_raw,2), numel(config.data_columns));

    [data, config] = preprocess_data(data_raw, config);
    resp_cycles = load_or_extract_respiratory_cycles(data, config);

    verifySize(testCase, data, size(data_raw));
    verifyEqual(testCase, config.fs, 200);
    removed_rate_field = ['new_' 'fs'];
    verifyFalse(testCase, isfield(config, removed_rate_field));
    verifyEqual(testCase, numel(resp_cycles.lungs.x0), size(data_raw,1));
    verifyEqual(testCase, numel(resp_cycles.diaph.x0), size(data_raw,1));

    % End-to-end smoke: common evidence plus every independent detector. The
    % short excerpt may lack the protocol session interval; unavailable
    % amplitude evidence must skip cleanly without changing other streams.
    session_reference = get_session_reference_interval(size(data, 1), config);
    resp_ref = compute_respiratory_reference( ...
        resp_cycles, session_reference, config);
    spo2_ref = compute_spo2_reference(data, session_reference, config);
    resp_features = compute_respiratory_features( ...
        data, resp_cycles, resp_ref, config);

    [events_shallow, boundary_shallow] = detect_shallow_breathing(data, resp_features, config);
    [events_deep, boundary_deep] = detect_deep_breathing(data, resp_features, config);
    [events_thoracic, boundary_thoracic] = detect_thoracic_dominant_breathing(data, resp_features, config);
    [events_irregular, boundary_irregular] = detect_irregular_breathing(data, resp_features, config);
    [events_slow, boundary_slow] = detect_slow_breathing(data, resp_features, config);
    [events_rapid, boundary_rapid] = detect_rapid_breathing(data, resp_features, config);
    [events_async, diagnostics_async] = detect_respiratory_asynchrony( ...
        data, session_reference, resp_cycles, config);
    [events_desat, diagnostics_desat] = detect_desaturation( ...
        data, spo2_ref, session_reference, config);
    [events_apnea, diagnostics_apnea, boundary_apnea] = detect_apnea( ...
        data, resp_features, session_reference, config);
    [events_sigh, diagnostics_sigh, sigh_review] = detect_sigh( ...
        data, resp_features, resp_cycles, spo2_ref, session_reference, ...
        diagnostics_desat, config);
    [events_csr, diagnostics_csr] = detect_periodic_breathing( ...
        data, resp_cycles, config);

    events = normalize_event_types_and_meta(merge_events({ ...
        events_shallow, events_irregular, events_slow, events_rapid, events_async, ...
        events_desat, events_apnea, events_sigh, events_csr, events_deep, events_thoracic}), ...
        config.fs);
    [mask, label_names] = events_to_time_mask(events, size(data,1), config);
    [label_available, reasons] = compute_label_availability( ...
        label_names, resp_features, diagnostics_desat, diagnostics_async, ...
        diagnostics_apnea, diagnostics_sigh, diagnostics_csr);
    diagnostic = compute_label_diagnostic_signals( ...
        resp_features, spo2_ref, diagnostics_desat, config, diagnostics_async, ...
        diagnostics_apnea, diagnostics_sigh, diagnostics_csr);
    detector_diagnostics = struct('async', diagnostics_async, ...
        'desat', diagnostics_desat, ...
        'apnea', diagnostics_apnea, 'sigh', diagnostics_sigh, ...
        'csr', diagnostics_csr);
    burden = compute_recording_label_burden( ...
        mask, label_names, label_available, events, config.fs);
    overlaps = compute_label_overlap_summary( ...
        mask, label_names, label_available, config.fs);
    evidence = build_label_evidence_summary( ...
        label_names, label_available, reasons, resp_features, diagnostic, ...
        detector_diagnostics, burden);
    phenotypes = build_db_phenotype_evidence(burden, overlaps, evidence);

    detections.events = struct( ...
        'shallow', events_shallow, 'deep', events_deep, ...
        'slow', events_slow, 'rapid', events_rapid, ...
        'irregular', events_irregular, 'apnea', events_apnea, ...
        'csr', events_csr, 'thoracic', events_thoracic, ...
        'async', events_async, 'desat', events_desat);
    detections.boundaries = struct( ...
        'shallow', boundary_shallow, 'deep', boundary_deep, ...
        'slow', boundary_slow, 'rapid', boundary_rapid, ...
        'irregular', boundary_irregular, 'apnea', boundary_apnea, ...
        'thoracic', boundary_thoracic);
    detections.diagnostics = detector_diagnostics;
    label_results = finalize_label_results( ...
        data, resp_cycles, resp_features, spo2_ref, session_reference, ...
        detections, sigh_review, config);
    export_results = build_recording_results( ...
        config, resp_cycles, resp_ref, session_reference, spo2_ref, ...
        resp_features, label_results);
    hdf5_file = fullfile(output_dir,'example_pipeline.h5');
    export_results_hdf5(hdf5_file,export_results,data_raw,data);

    verifyEqual(testCase, size(mask,1), size(data,1));
    verifyEqual(testCase, size(mask,2), numel(label_names));
    verifyEqual(testCase, resp_features.resp.lungs.peak_idx, resp_cycles.lungs.peak_idx);
    verifyEqual(testCase, diagnostic.time_sec, resp_features.resp.time_sec);
    verifyEqual(testCase, numel(reasons), 11);
    verifyEqual(testCase, phenotypes.version, 'magma_db_phenotype_evidence_v1');
    verifyEqual(testCase, label_results.events_automatic, events);
    verifyEqual(testCase, label_results.mask_automatic, mask);
    verifyFalse(testCase, any(label_results.review_coverage_mask(:)));
    verifySize(testCase, label_results.assessable_mask, size(mask));
    verifyEqual(testCase, label_results.assessability_info.version, ...
        'label_assessability_v1');
    verifyEqual(testCase, read_hdf5_text(hdf5_file,'/labels/names'),label_names);
    verifyEqual(testCase, logical(h5read(hdf5_file,'/labels/automatic_mask')),mask);
    verifyEqual(testCase, h5read(hdf5_file,'/meta/fs'),config.fs);
    verifyEqual(testCase, read_hdf5_text(hdf5_file, ...
        '/session_reference/reference_schema_version'), ...
        {'session_physiological_reference_v1'});
end

function data = read_first_rows(filename, n_columns, n_rows)
    fid = fopen(filename, 'r');
    if fid < 0
        error('Could not open example recording: %s', filename);
    end
    cleanup_file = onCleanup(@() fclose(fid));
    format = repmat('%f', 1, n_columns);
    values = textscan(fid, format, n_rows, 'CollectOutput', true);
    data = values{1};
end
