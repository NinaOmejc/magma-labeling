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
    resp_feat = load_or_extract_respiratory_features(data, config);

    verifySize(testCase, data, size(data_raw));
    verifyEqual(testCase, config.fs, 200);
    removed_rate_field = ['new_' 'fs'];
    verifyFalse(testCase, isfield(config, removed_rate_field));
    verifyEqual(testCase, numel(resp_feat.lungs.x0), size(data_raw,1));
    verifyEqual(testCase, numel(resp_feat.diaph.x0), size(data_raw,1));

    % Phase-3 end-to-end smoke: common evidence plus every detector. The
    % short excerpt may lack the protocol session interval; unavailable
    % amplitude evidence must skip cleanly without changing other streams.
    config.baseline_location = 'first';
    config.baseline_sec = 60;
    baseline = compute_baseline(data, config);
    resp_ref = compute_respiratory_reference(resp_feat, config);
    spo2_feat = extract_spo2_features(data, baseline, config);
    phys_feat = compute_physiological_features( ...
        data, resp_feat, resp_ref, spo2_feat, config);

    events_ShB = detect_shallow_breathing(data, phys_feat, baseline, spo2_feat, config);
    events_IrB = detect_irregular_breathing(data, phys_feat, config);
    events_SlB = detect_slow_breathing(data, phys_feat, config);
    events_RaB = detect_rapid_breathing(data, phys_feat, config);
    [events_ReA, diagnostics_ReA] = detect_respiratory_asynchrony( ...
        data, baseline, resp_feat, config);
    events_Des = detect_desaturation(data, baseline, spo2_feat, config);
    events_Apn = detect_apnea(data, phys_feat, config);
    events_Sigh = detect_sigh( ...
        data, phys_feat, resp_feat, baseline, spo2_feat, config);
    events_CSR = detect_periodic_breathing(data, resp_feat, config);

    events = normalize_event_types_and_meta(merge_events({ ...
        events_ShB, events_IrB, events_SlB, events_RaB, events_ReA, ...
        events_Des, events_Apn, events_Sigh, events_CSR}));
    [mask, label_names] = events_to_time_mask(events, size(data,1), config);
    diagnostic = compute_label_diagnostic_signals( ...
        phys_feat, baseline, spo2_feat, config, diagnostics_ReA);

    verifyEqual(testCase, size(mask,1), size(data,1));
    verifyEqual(testCase, size(mask,2), numel(label_names));
    verifyEqual(testCase, phys_feat.resp.lungs.peak_idx, resp_feat.lungs.peak_idx);
    verifyEqual(testCase, diagnostic.time_sec, phys_feat.resp.time_sec);
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
