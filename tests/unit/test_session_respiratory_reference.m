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

    data = zeros(601 * config.fs, numel(config.data_columns));
    reference = get_session_reference_interval(size(data, 1), config);
    resp_ref = compute_respiratory_reference( ...
        data, make_resp_feat(t, lungs_amp, t, diaph_amp), reference, config);

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
    data = zeros(400 * config.fs, numel(config.data_columns));
    reference = get_session_reference_interval(size(data, 1), config);
    resp_ref = compute_respiratory_reference( ...
        data, make_resp_feat(t, 3 * ones(size(t)), t, 1.2 * ones(size(t))), ...
        reference, config);

    verifyTrue(testCase, resp_ref.lungs.session.available);
    verifyTrue(testCase, resp_ref.diaph.session.available);
    verifyEqual(testCase, resp_ref.lungs.session.value, 3, 'AbsTol', eps);
    verifyEqual(testCase, resp_ref.diaph.session.value, 1.2, 'AbsTol', eps);
end

function testRespiratoryReferenceNeverFallsBackToWholeRecord(testCase)
    config = session_test_config(1, 10);
    t = (0:3:120)';
    data = zeros(400 * config.fs, numel(config.data_columns));
    reference = get_session_reference_interval(size(data, 1), config);
    resp_ref = compute_respiratory_reference( ...
        data, make_resp_feat(t, ones(size(t)), [], []), reference, config);

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

    [~, diagnostics_desat] = detect_desaturation( ...
        data, reference, config);
    spo2_ref = diagnostics_desat.spo2_ref;

    verifyTrue(testCase, spo2_ref.available);
    verifyEqual(testCase, spo2_ref.median_percent, 96, 'AbsTol', eps);
    verifyEqual(testCase, spo2_ref.n_interval_samples, 180);
    verifyEqual(testCase, spo2_ref.n_valid_samples, 179);
    verifyTrue(testCase, diagnostics_desat.reference_available);
end

function testUnavailableSpO2DoesNotInvalidateRespiratoryReference(testCase)
    config = session_test_config(1, 1);
    data = zeros(400, 6);
    data(:, config.channels.spo2_idx) = NaN;
    t = (180:3:357)';
    reference = get_session_reference_interval(size(data, 1), config);
    resp_ref = compute_respiratory_reference( ...
        data, make_resp_feat(t, 2 * ones(size(t)), [], []), reference, config);
    [~, diagnostics_desat] = detect_desaturation(data, reference, config);
    spo2_ref = diagnostics_desat.spo2_ref;

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

    [~, diagnostics_desat] = detect_desaturation( ...
        data, reference, config);
    spo2_ref = diagnostics_desat.spo2_ref;

    verifyFalse(testCase, spo2_ref.available);
    verifyEqual(testCase, spo2_ref.quality, 'insufficient_valid_samples');
    verifyFalse(testCase, diagnostics_desat.reference_available);
    verifyFalse(testCase, diagnostics_desat.detection_available);
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
    config.async.analysis_fs = 10;
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
    config.apnea.do_plot = false;
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
    resp_ref = compute_respiratory_reference( ...
        data, make_resp_feat([], [], [], []), reference, config);

    [~, diagnostics] = detect_apnea(data, phys, resp_ref, config);
    x_lungs = data(reference.reference_start_idx:reference.reference_end_idx, ...
        config.channels.lungs_idx);
    expected_excursion = prctile(x_lungs, 95) - prctile(x_lungs, 5);
    expected_slope = median(abs(diff(x_lungs)), 'omitnan');

    verifyTrue(testCase, diagnostics.raw_flat.lungs.reference_available);
    verifyEqual(testCase, fieldnames(resp_ref.lungs.raw), ...
        {'available'; 'quality'; 'n_samples'; 'finite_fraction'; ...
         'excursion'; 'slope'});
    verifyTrue(testCase, isfield(resp_ref.diaph, 'raw'));
    verifyFalse(testCase, resp_ref.lungs.session.available);
    verifyTrue(testCase, resp_ref.lungs.raw.available);
    verifyEqual(testCase, ...
        resp_ref.lungs.raw.excursion, expected_excursion, 'AbsTol', 1e-12);
    verifyEqual(testCase, resp_ref.lungs.raw.slope, ...
        expected_slope, 'AbsTol', 1e-12);
    verifyEqual(testCase, resp_ref.lungs.raw.n_samples, numel(x_lungs));
    verifyEqual(testCase, resp_ref.lungs.raw.finite_fraction, 1);
    verifyEqual(testCase, ...
        diagnostics.raw_flat.lungs.session_excursion_reference, ...
        resp_ref.lungs.raw.excursion, 'AbsTol', 1e-12);
    verifyEqual(testCase, ...
        diagnostics.raw_flat.lungs.session_slope_reference, ...
        expected_slope, 'AbsTol', 1e-12);
    verifyEqual(testCase, diagnostics.raw_flat.lungs.reference_source, ...
        'common_session_reference_interval');
end

function testRawReferenceRejectsLowFiniteCoverage(testCase)
    config = session_test_config(1, 10);
    N = 400 * config.fs;
    t = (0:N-1)' / config.fs;
    data = zeros(N, numel(config.data_columns));
    data(:, config.channels.lungs_idx) = sin(2*pi*0.2*t);
    reference = get_session_reference_interval(N, config);
    interval_idx = reference.reference_start_idx:reference.reference_end_idx;
    data(interval_idx(1:ceil(0.21*numel(interval_idx))), ...
        config.channels.lungs_idx) = NaN;

    resp_ref = compute_respiratory_reference( ...
        data, make_resp_feat([], [], [], []), reference, config);

    verifyLessThan(testCase, resp_ref.lungs.raw.finite_fraction, 0.8);
    verifyFalse(testCase, resp_ref.lungs.raw.available);
    verifyEqual(testCase, resp_ref.lungs.raw.quality, ...
        'insufficient_finite_coverage');
end

function testRawReferenceMarksIgnoredAndMissingBeltsUnavailable(testCase)
    config = session_test_config(1, 10);
    config.problems.missing_lung_belt = [config.subject config.measure];
    N = 400 * config.fs;
    t = (0:N-1)' / config.fs;
    data = zeros(N, numel(config.data_columns));
    data(:, config.channels.lungs_idx) = sin(2*pi*0.2*t);
    data(:, config.channels.diaph_idx) = sin(2*pi*0.2*t + 0.1);
    reference = get_session_reference_interval(N, config);

    ignored = compute_respiratory_reference( ...
        data, make_resp_feat([], [], [], []), reference, config);
    verifyFalse(testCase, ignored.lungs.raw.available);
    verifyEqual(testCase, ignored.lungs.raw.quality, 'belt_ignored');
    verifyTrue(testCase, ignored.diaph.raw.available);

    config.problems.missing_lung_belt = zeros(0, 2);
    config.channels.diaph_idx = [];
    missing = compute_respiratory_reference( ...
        data, make_resp_feat([], [], [], []), reference, config);
    verifyFalse(testCase, missing.diaph.raw.available);
    verifyEqual(testCase, missing.diaph.raw.quality, 'channel_missing');
end

function testTruncatedRawReferenceRetainsWarning(testCase)
    config = session_test_config(1, 10);
    N = 240 * config.fs;
    t = (0:N-1)' / config.fs;
    data = zeros(N, numel(config.data_columns));
    data(:, config.channels.lungs_idx) = sin(2*pi*0.2*t);
    reference = get_session_reference_interval(N, config);

    resp_ref = compute_respiratory_reference( ...
        data, make_resp_feat([], [], [], []), reference, config);

    verifyTrue(testCase, resp_ref.lungs.raw.available);
    verifyEqual(testCase, resp_ref.lungs.raw.quality, ...
        'warning_truncated_interval');
end

function testApneaNormalizesCurrentRawMetricsByMatchingReferences(testCase)
    config = session_test_config(1, 10);
    config.grid_step_sec = 1;
    config.apnea.do_plot = false;
    N = 121 * config.fs;
    t_raw = (0:N-1)' / config.fs;
    data = zeros(N, numel(config.data_columns));
    data(:, config.channels.lungs_idx) = t_raw;
    phys = raw_only_phys_fixture(N, config);
    resp_ref = explicit_raw_resp_ref(10, 2, NaN, NaN);

    [~, diagnostics] = detect_apnea(data, phys, resp_ref, config);
    grid_idx = find(phys.time_sec == 10, 1);
    segment = data(1:10*config.fs+1, config.channels.lungs_idx);

    verifyEqual(testCase, ...
        diagnostics.raw_flat.lungs.excursion_reference_used(grid_idx), ...
        10, 'AbsTol', eps);
    verifyEqual(testCase, diagnostics.raw_flat.lungs.slope_reference_used(grid_idx), ...
        2, 'AbsTol', eps);
    verifyEqual(testCase, diagnostics.raw_flat.lungs.excursion_ratio(grid_idx), ...
        robust_resp_excursion(segment) / 10, 'AbsTol', 1e-12);
    verifyEqual(testCase, diagnostics.raw_flat.lungs.slope_ratio(grid_idx), ...
        raw_resp_slope_level(segment) / 2, 'AbsTol', 1e-12);
end

function testAdaptiveRawReferencesRemainFlooredByFixedReferences(testCase)
    config = session_test_config(1, 10);
    config.grid_step_sec = 1;
    config.apnea.do_plot = false;
    N = 161 * config.fs;
    t_raw = (0:N-1)' / config.fs;
    x = sin(2*pi*0.2*t_raw);
    prior = t_raw >= 30 & t_raw <= 90;
    x(prior) = 0.01 * sin(2*pi*0.2*t_raw(prior));
    data = zeros(N, numel(config.data_columns));
    data(:, config.channels.lungs_idx) = x;
    phys = raw_only_phys_fixture(N, config);
    resp_ref = explicit_raw_resp_ref(8, 1, NaN, NaN);

    [~, diagnostics] = detect_apnea(data, phys, resp_ref, config);
    grid_idx = find(phys.time_sec == 100, 1);

    verifyTrue(testCase, ...
        diagnostics.raw_flat.lungs.adaptive_reference_used(grid_idx));
    verifyEqual(testCase, ...
        diagnostics.raw_flat.lungs.excursion_reference_used(grid_idx), ...
        config.apnea.raw_flat_ref_floor_ratio * 8, 'AbsTol', 1e-12);
    verifyEqual(testCase, ...
        diagnostics.raw_flat.lungs.slope_reference_used(grid_idx), ...
        config.apnea.raw_flat_ref_floor_ratio, 'AbsTol', 1e-12);
end

function testAdaptiveRawReferencesUseLaggedRawMetrics(testCase)
    config = session_test_config(1, 10);
    config.grid_step_sec = 1;
    config.apnea.do_plot = false;
    N = 161 * config.fs;
    t_raw = (0:N-1)' / config.fs;
    x = sin(2*pi*0.2*t_raw);
    data = zeros(N, numel(config.data_columns));
    data(:, config.channels.lungs_idx) = x;
    phys = raw_only_phys_fixture(N, config);
    resp_ref = explicit_raw_resp_ref(4, 0.1, NaN, NaN);

    [~, diagnostics] = detect_apnea(data, phys, resp_ref, config);
    grid_idx = find(phys.time_sec == 100, 1);
    [i1, i2] = reference_window_indices(30, 90, config.fs, N);
    expected_excursion = robust_resp_excursion(x(i1:i2));
    expected_slope = raw_resp_slope_level(x(i1:i2));

    verifyTrue(testCase, ...
        diagnostics.raw_flat.lungs.adaptive_reference_used(grid_idx));
    verifyEqual(testCase, ...
        diagnostics.raw_flat.lungs.excursion_reference_used(grid_idx), ...
        expected_excursion, 'AbsTol', 1e-12);
    verifyEqual(testCase, ...
        diagnostics.raw_flat.lungs.slope_reference_used(grid_idx), ...
        expected_slope, 'AbsTol', 1e-12);
end

function testRawFlatBeltAvailabilityPreservesBothAndSingleBeltSemantics(testCase)
    config = session_test_config(1, 10);
    config.grid_step_sec = 1;
    config.apnea.do_plot = false;
    N = 121 * config.fs;
    t_raw = (0:N-1)' / config.fs;
    data = zeros(N, numel(config.data_columns));
    data(:, config.channels.lungs_idx) = sin(2*pi*0.2*t_raw);
    data(:, config.channels.diaph_idx) = sin(2*pi*0.2*t_raw + 0.1);
    flat = t_raw >= 50 & t_raw <= 80;
    data(flat, config.channels.lungs_idx) = 0;
    data(flat, config.channels.diaph_idx) = 0;
    phys = raw_only_phys_fixture(N, config);
    resp_ref = explicit_raw_resp_ref(2, 0.1, 2, 0.1);

    [~, both] = detect_apnea(data, phys, resp_ref, config);
    verifyEqual(testCase, both.raw_flat_support_belts, 'both');
    verifyTrue(testCase, any(both.raw_flat.lungs.mask));
    verifyEqual(testCase, both.raw_flat.combined_candidate, ...
        both.raw_flat.lungs.mask & both.raw_flat.diaph.mask);

    resp_ref.diaph.raw.available = false;
    [~, one] = detect_apnea(data, phys, resp_ref, config);
    verifyEqual(testCase, one.raw_flat_support_belts, 'lungs');
    verifyEqual(testCase, one.raw_flat.combined_candidate, ...
        one.raw_flat.lungs.mask);
end

function testRawApneaReferenceNeverFallsBackWhenIntervalIsUnavailable(testCase)
    config = session_test_config(1, 10);
    config.grid_step_sec = 1;
    config.apnea.do_plot = false;
    N = 120 * config.fs;
    t = (0:N-1)' / config.fs;
    data = zeros(N, 6);
    data(:, config.channels.lungs_idx) = sin(2*pi*0.2*t);
    data(:, config.channels.diaph_idx) = ...
        0.7 * sin(2*pi*0.2*t + 0.1);
    reference = get_session_reference_interval(N, config);
    phys = raw_only_phys_fixture(N, config);
    resp_ref = compute_respiratory_reference( ...
        data, make_resp_feat([], [], [], []), reference, config);

    [~, diagnostics] = detect_apnea(data, phys, resp_ref, config);

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
    data = zeros(N, numel(config.data_columns));
    resp_ref = compute_respiratory_reference( ...
        data, resp_feat, reference, config);
    phys = compute_respiratory_features( ...
        zeros(N, 6), resp_feat, resp_ref, config);

    verifyEqual(testCase, phys.lungs.session_reference_value, 1, ...
        'AbsTol', eps);
    verifyEqual(testCase, phys.lungs.global_reference_value, 2, ...
        'AbsTol', eps);
    verifyEqual(testCase, phys.lungs.amp_ratio_global, ...
        amp / 2, 'AbsTol', eps);
end

function testNoObsoleteReferenceConfigurationOrHelperRemains(testCase)
    config = get_config();
    verifyFalse(testCase, isfield(config, 'baseline_sec'));
    verifyFalse(testCase, isfield(config, 'baseline_location'));
    verifyFalse(testCase, isfield(config, 'resp_ref'));
    verifyFalse(testCase, isfield(config.apnea, 'raw_flat_enabled'));

    repo_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    verifyFalse(testCase, isfile(fullfile(repo_root, 'src', 'utils', ...
        'get_static_baseline_interval.m')));
    verifyFalse(testCase, isfile(fullfile(repo_root, 'src', ...
        'feature_extraction', 'compute_baseline.m')));

    interval_helpers = dir(fullfile(repo_root, 'src', '**', ...
        '*reference_interval*.m'));
    verifyEqual(testCase, {interval_helpers.name}, ...
        {'get_session_reference_interval.m'});

    apnea_source = fileread(fullfile(repo_root, 'src', ...
        'label_detection', 'detect_apnea.m'));
    verifyFalse(testCase, contains(apnea_source, ...
        'data, resp_features, session_reference, config'));
    verifyFalse(testCase, contains(apnea_source, 'reference_segment'));

    forbidden = {'baseline_sec', 'baseline_location', 'raw_flat_enabled', ...
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
    phys = struct('time_sec', t_grid, 'lungs', belt, 'diaph', belt);
end

function resp_ref = explicit_raw_resp_ref( ...
    lungs_excursion, lungs_slope, diaph_excursion, diaph_slope)
% EXPLICIT_RAW_RESP_REF Build fixed raw references for detector-only tests.

    lungs = raw_reference_fixture(lungs_excursion, lungs_slope);
    diaph = raw_reference_fixture(diaph_excursion, diaph_slope);
    session = struct('value', 100, 'available', true);
    resp_ref = struct( ...
        'lungs', struct('session', session, 'raw', lungs), ...
        'diaph', struct('session', session, 'raw', diaph));
end

function raw = raw_reference_fixture(excursion, slope)
% RAW_REFERENCE_FIXTURE Build one complete fixed raw-reference schema.

    available = isfinite(excursion) && excursion > 0 && ...
        isfinite(slope) && slope > 0;
    raw = struct('available', available, 'quality', 'test_reference', ...
        'n_samples', 100, 'finite_fraction', 1, ...
        'excursion', excursion, 'slope', slope);
end

function [i1, i2] = reference_window_indices(t1, t2, fs, N)
% REFERENCE_WINDOW_INDICES Mirror the detector's clamped time indexing.

    i1 = max(1, floor(t1 * fs) + 1);
    i2 = min(N, floor(t2 * fs) + 1);
end
