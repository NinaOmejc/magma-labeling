function tests = test_session_respiratory_reference
% Regression tests for the unified session physiological reference.
    tests = functiontests(localfunctions);
end

function testProtocolIntervalsFollowMeasurementExactly(testCase)
    cases = [1 180 360; 2 1140 1320; 3 180 360; 4 1140 1320];
    for i = 1:size(cases, 1)
        config = session_test_config(cases(i, 1), 10);
        reference = get_session_reference_interval(1400 * config.fs, config);
        verifyTrue(testCase, reference.available);
        verifyTrue(testCase, reference.complete);
        verifyFalse(testCase, reference.truncated);
        verifyEqual(testCase, reference.reference_start_idx, ...
            cases(i, 2) * config.fs + 1);
        verifyEqual(testCase, reference.reference_end_idx, ...
            cases(i, 3) * config.fs);
        verifyEqual(testCase, reference.reference_start_t, cases(i, 2));
        verifyEqual(testCase, reference.reference_end_t, cases(i, 3));
        verifyEqual(testCase, reference.reference_duration_sec, 180);
        verifyEqual(testCase, reference.measurement, cases(i, 1));
        verifyEqual(testCase, reference.reference_schema_version, ...
            'session_physiological_reference_v1');
    end
end

function testRespiratoryReferenceUsesReviewedBreathsInsideHalfOpenInterval(testCase)
    config = session_test_config(1, 10);
    config.reference.resp_min_breaths = 5;
    t = (0:3:600)';
    lungs_amp = 9 * ones(size(t));
    diaph_amp = 7 * ones(size(t));
    in_reference = t >= 180 & t < 360;
    lungs_amp(in_reference) = 2;
    diaph_amp(in_reference) = 4;
    lungs_amp(t == 210) = NaN;
    lungs_amp(t == 240) = 0;
    lungs_amp(t == 360) = 99;
    diaph_amp(t == 360) = 88;

    reference = get_session_reference_interval(601 * config.fs, config);
    resp_ref = compute_respiratory_reference( ...
        make_resp_feat(t, lungs_amp, t, diaph_amp), reference, config);

    verifyEqual(testCase, resp_ref.lungs.session.value, 2, 'AbsTol', eps);
    verifyEqual(testCase, resp_ref.diaph.session.value, 4, 'AbsTol', eps);
    verifyEqual(testCase, resp_ref.lungs.session.n_breaths, ...
        nnz(in_reference) - 2);
    verifyEqual(testCase, resp_ref.diaph.session.n_breaths, nnz(in_reference));
    verifyNotEqual(testCase, resp_ref.lungs.global.value, ...
        resp_ref.lungs.session.value);
end

function testRespiratoryReferencesRemainIndependent(testCase)
    config = session_test_config(1, 10);
    t = (180:3:357)';
    reference = get_session_reference_interval(400 * config.fs, config);
    resp_ref = compute_respiratory_reference( ...
        make_resp_feat(t, 3 * ones(size(t)), t, 1.2 * ones(size(t))), ...
        reference, config);

    verifyTrue(testCase, resp_ref.lungs.session.available);
    verifyTrue(testCase, resp_ref.diaph.session.available);
    verifyEqual(testCase, resp_ref.lungs.session.value, 3, 'AbsTol', eps);
    verifyEqual(testCase, resp_ref.diaph.session.value, 1.2, 'AbsTol', eps);
end

function testRespiratoryReferenceNeverFallsBackToWholeRecord(testCase)
    config = session_test_config(1, 10);
    t = (0:3:120)';
    reference = get_session_reference_interval(400 * config.fs, config);
    resp_ref = compute_respiratory_reference( ...
        make_resp_feat(t, ones(size(t)), [], []), reference, config);

    verifyTrue(testCase, resp_ref.lungs.global.available);
    verifyFalse(testCase, resp_ref.lungs.session.available);
    verifyTrue(testCase, isnan(resp_ref.lungs.session.value));
    verifyEqual(testCase, resp_ref.lungs.reference_quality, ...
        'insufficient_breaths');
end

function testSpO2ReferenceUsesTheSameInterval(testCase)
    config = session_test_config(1, 1);
    data = zeros(400, 6);
    data(:, config.channels.spo2_idx) = 70;
    data(181:360, config.channels.spo2_idx) = 96;
    data(200, config.channels.spo2_idx) = NaN;
    reference = get_session_reference_interval(size(data, 1), config);

    spo2_ref = compute_spo2_reference(data, reference, config);
    spo2_feat = extract_spo2_features(data, spo2_ref, config);

    verifyTrue(testCase, spo2_ref.available);
    verifyEqual(testCase, spo2_ref.median_percent, 96, 'AbsTol', eps);
    verifyEqual(testCase, spo2_ref.n_interval_samples, 180);
    verifyEqual(testCase, spo2_ref.n_valid_samples, 179);
    verifyTrue(testCase, spo2_feat.reference_available);
end

function testUnavailableSpO2DoesNotInvalidateRespiratoryReference(testCase)
    config = session_test_config(1, 1);
    data = zeros(400, 6);
    data(:, config.channels.spo2_idx) = NaN;
    t = (180:3:357)';
    reference = get_session_reference_interval(size(data, 1), config);
    resp_ref = compute_respiratory_reference( ...
        make_resp_feat(t, 2 * ones(size(t)), [], []), reference, config);
    spo2_ref = compute_spo2_reference(data, reference, config);

    verifyTrue(testCase, resp_ref.lungs.session.available);
    verifyFalse(testCase, spo2_ref.available);
    verifyEqual(testCase, spo2_ref.quality, 'insufficient_valid_samples');
end

function testSpO2ReferenceNeverFallsBackOutsideInterval(testCase)
    config = session_test_config(1, 1);
    data = zeros(400, 6);
    data(:, config.channels.spo2_idx) = 96;
    data(181:360, config.channels.spo2_idx) = NaN;
    reference = get_session_reference_interval(size(data, 1), config);

    spo2_ref = compute_spo2_reference(data, reference, config);
    spo2_feat = extract_spo2_features(data, spo2_ref, config);

    verifyFalse(testCase, spo2_ref.available);
    verifyEqual(testCase, spo2_ref.quality, 'insufficient_valid_samples');
    verifyFalse(testCase, spo2_feat.reference_available);
    verifyFalse(testCase, spo2_feat.detection_available);
end

function testShortRecordingsAreExplicitlyTruncatedOrUnavailable(testCase)
    config = session_test_config(1, 10);
    partial = get_session_reference_interval(240 * config.fs, config);
    verifyTrue(testCase, partial.available);
    verifyFalse(testCase, partial.complete);
    verifyTrue(testCase, partial.truncated);
    verifyEqual(testCase, partial.reference_start_t, 180);
    verifyEqual(testCase, partial.reference_end_t, 240);
    verifyEqual(testCase, partial.reference_duration_sec, 60);
    verifyEqual(testCase, partial.truncation_reason, ...
        'recording_ends_inside_reference_interval');

    missing = get_session_reference_interval(120 * config.fs, config);
    verifyFalse(testCase, missing.available);
    verifyTrue(testCase, missing.truncated);
    verifyEqual(testCase, missing.reference_duration_sec, 0);
    verifyEqual(testCase, missing.truncation_reason, ...
        'recording_ends_before_reference_start');
end

function testReAReferenceMaskUsesCommonInterval(testCase)
    config = session_test_config(1, 10);
    config.grid_step_sec = 1;
    config.ReA.analysis_fs = 10;
    data = make_synthetic_master_data(400 * config.fs, config.fs);
    reference = get_session_reference_interval(size(data, 1), config);

    rea = compute_respiratory_asynchrony_metrics(data, [], reference, config);
    expected = rea.time_sec >= reference.reference_start_t & ...
        rea.time_sec < reference.reference_end_t;
    verifyEqual(testCase, rea.reference_mask, expected);
    verifyTrue(testCase, rea.reference_available, rea.error_message);
    verifyEqual(testCase, rea.reference_quality, 'good');
end

function testReAUnavailableReferenceDoesNotMove(testCase)
    config = session_test_config(1, 10);
    data = make_synthetic_master_data(120 * config.fs, config.fs);
    reference = get_session_reference_interval(size(data, 1), config);

    rea = compute_respiratory_asynchrony_metrics(data, [], reference, config);
    verifyFalse(testCase, rea.valid_analysis);
    verifyFalse(testCase, rea.reference_available);
    verifyFalse(testCase, any(rea.reference_mask));
    verifyEqual(testCase, rea.reference_quality, ...
        'reference_interval_unavailable');
end

function testRawApneaReferenceUsesCommonInterval(testCase)
    config = session_test_config(1, 10);
    config.grid_step_sec = 1;
    config.Apn.do_plot = false;
    N = 400 * config.fs;
    t = (0:N-1)' / config.fs;
    data = zeros(N, 6);
    data(:, config.channels.lungs_idx) = 8 * sin(2*pi*0.2*t);
    data(:, config.channels.diaph_idx) = 6 * sin(2*pi*0.2*t + 0.1);
    in_reference = t >= 180 & t < 360;
    data(in_reference, config.channels.lungs_idx) = sin(2*pi*0.2*t(in_reference));
    data(in_reference, config.channels.diaph_idx) = ...
        0.7 * sin(2*pi*0.2*t(in_reference) + 0.1);
    reference = get_session_reference_interval(N, config);
    phys = raw_only_phys_fixture(N, config);

    [~, diagnostics] = detect_apnea(data, phys, reference, config);
    x_lungs = data(reference.reference_start_idx:reference.reference_end_idx, ...
        config.channels.lungs_idx);
    expected_motion = prctile(x_lungs, 95) - prctile(x_lungs, 5);
    expected_slope = median(abs(diff(x_lungs)), 'omitnan');

    verifyTrue(testCase, diagnostics.raw_flat.lungs.reference_available);
    verifyEqual(testCase, ...
        diagnostics.raw_flat.lungs.session_motion_reference, ...
        expected_motion, 'AbsTol', 1e-12);
    verifyEqual(testCase, ...
        diagnostics.raw_flat.lungs.session_slope_reference, ...
        expected_slope, 'AbsTol', 1e-12);
    verifyEqual(testCase, diagnostics.raw_flat.lungs.reference_source, ...
        'common_session_reference_interval');
end

function testRawApneaReferenceNeverFallsBackWhenIntervalIsUnavailable(testCase)
    config = session_test_config(1, 10);
    config.grid_step_sec = 1;
    config.Apn.do_plot = false;
    N = 120 * config.fs;
    t = (0:N-1)' / config.fs;
    data = zeros(N, 6);
    data(:, config.channels.lungs_idx) = sin(2*pi*0.2*t);
    data(:, config.channels.diaph_idx) = ...
        0.7 * sin(2*pi*0.2*t + 0.1);
    reference = get_session_reference_interval(N, config);
    phys = raw_only_phys_fixture(N, config);

    [~, diagnostics] = detect_apnea(data, phys, reference, config);

    verifyFalse(testCase, reference.available);
    verifyFalse(testCase, diagnostics.raw_flat.lungs.reference_available);
    verifyFalse(testCase, diagnostics.raw_flat.diaph.reference_available);
    verifyEqual(testCase, diagnostics.raw_flat.lungs.reference_quality, ...
        'reference_interval_unavailable');
    verifyEqual(testCase, diagnostics.raw_flat.diaph.reference_quality, ...
        'reference_interval_unavailable');
end

function testSighKeepsWholeRecordAmplitudeReference(testCase)
    config = session_test_config(1, 1);
    N = 601;
    t = (0:3:600)';
    amp = 2 * ones(size(t));
    amp(t >= 180 & t < 360) = 1;
    reference = get_session_reference_interval(N, config);
    resp_feat = make_resp_feat(t, amp, [], []);
    resp_ref = compute_respiratory_reference(resp_feat, reference, config);
    phys = compute_physiological_features( ...
        zeros(N, 6), resp_feat, resp_ref, struct(), config);

    verifyEqual(testCase, phys.resp.lungs.session_reference_value, 1, ...
        'AbsTol', eps);
    verifyEqual(testCase, phys.resp.lungs.global_reference_value, 2, ...
        'AbsTol', eps);
    verifyEqual(testCase, phys.resp.lungs.amp_ratio_global, ...
        amp / 2, 'AbsTol', eps);
end

function testNoObsoleteReferenceConfigurationOrHelperRemains(testCase)
    config = get_config();
    verifyFalse(testCase, isfield(config, 'baseline_sec'));
    verifyFalse(testCase, isfield(config, 'baseline_location'));
    verifyFalse(testCase, isfield(config, 'resp_ref'));

    repo_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    verifyFalse(testCase, isfile(fullfile(repo_root, 'src', 'utils', ...
        'get_static_baseline_interval.m')));
    verifyFalse(testCase, isfile(fullfile(repo_root, 'src', ...
        'feature_extraction', 'compute_baseline.m')));

    interval_helpers = dir(fullfile(repo_root, 'src', '**', ...
        '*reference_interval*.m'));
    verifyEqual(testCase, {interval_helpers.name}, ...
        {'get_session_reference_interval.m'});

    forbidden = {'baseline_sec', 'baseline_location', ...
        'get_static_baseline_interval', 'static_baseline', ...
        'resp_ref.session_pre_start_min', 'resp_ref.session_pre_end_min', ...
        'resp_ref.session_post_start_min', 'resp_ref.session_post_end_min'};
    source_files = dir(fullfile(repo_root, 'src', '**', '*.m'));
    for i = 1:numel(source_files)
        source = fileread(fullfile(source_files(i).folder, source_files(i).name));
        for j = 1:numel(forbidden)
            verifyFalse(testCase, contains(source, forbidden{j}), ...
                sprintf('%s still contains %s', source_files(i).name, forbidden{j}));
        end
    end
end

function config = session_test_config(measure, fs)
    config = make_test_config();
    config.measure = measure;
    config.fs = fs;
    config.reference.resp_min_breaths = 10;
    config.reference.do_plot = false;
    config = resolve_signal_channels(config);
end

function resp_feat = make_resp_feat(t_lungs, amp_lungs, t_diaph, amp_diaph)
    resp_feat = struct();
    resp_feat.lungs = reviewed_belt(t_lungs, amp_lungs);
    resp_feat.diaph = reviewed_belt(t_diaph, amp_diaph);
end

function belt = reviewed_belt(peak_t, amp)
    peak_t = peak_t(:);
    amp = amp(:);
    belt = struct('ok', ~isempty(peak_t), 'peak_t', peak_t, 'amp', amp, ...
        'peak_idx', round(peak_t) + 1, 'ibi', diff(peak_t), ...
        'rr_bpm', 60 ./ diff(peak_t));
end

function phys = raw_only_phys_fixture(N, config)
    t_grid = (0:config.grid_step_sec:(N-1)/config.fs)';
    belt = struct('ignored', false, 'session_amplitude_available', false);
    phys = struct('resp', struct('time_sec', t_grid, ...
        'lungs', belt, 'diaph', belt));
end
