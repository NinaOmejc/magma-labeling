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

    [~, diagnostics_desat, spo2_ref] = detect_desaturation( ...
        data, reference, config);

    verifyTrue(testCase, spo2_ref.available);
    verifyEqual(testCase, spo2_ref.median_percent, 96, 'AbsTol', eps);
    verifyEqual(testCase, spo2_ref.n_interval_samples, 180);
    verifyEqual(testCase, spo2_ref.n_valid_samples, 179);
    verifyTrue(testCase, diagnostics_desat.reference_available);
    forbidden = {'spo2','time_sec','desaturation_sample_mask','events', ...
        'valid_sample_mask','spo2_ref'};
    verifyFalse(testCase, any(isfield(diagnostics_desat, forbidden)));
end

function testUnavailableSpO2DoesNotInvalidateRespiratoryReference(testCase)
    config = session_test_config(1, 1);
    data = zeros(400, 6);
    data(:, config.channels.spo2_idx) = NaN;
    t = (180:3:357)';
    reference = get_session_reference_interval(size(data, 1), config);
    resp_ref = compute_respiratory_reference( ...
        data, make_resp_feat(t, 2 * ones(size(t)), [], []), reference, config);
    [~, ~, spo2_ref] = detect_desaturation(data, reference, config);

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

    [~, diagnostics_desat, spo2_ref] = detect_desaturation( ...
        data, reference, config);

    verifyFalse(testCase, spo2_ref.available);
    verifyEqual(testCase, spo2_ref.quality, 'insufficient_valid_samples');
    verifyFalse(testCase, diagnostics_desat.reference_available);
    verifyTrue(testCase, diagnostics_desat.absolute_available);
    verifyFalse(testCase, diagnostics_desat.relative_available);
    verifyTrue(testCase, diagnostics_desat.detection_available);
    verifyEqual(testCase, diagnostics_desat.detection_mode, 'absolute_only');
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
    verifyTrue(testCase, diagnostics.raw_excursion.lungs.valid);
    verifyEqual(testCase, fieldnames(resp_ref.lungs.raw), ...
        {'available'; 'quality'; 'n_samples'; 'finite_fraction'; ...
         'excursion'});
    verifyTrue(testCase, isfield(resp_ref.diaph, 'raw'));
    verifyFalse(testCase, resp_ref.lungs.session.available);
    verifyTrue(testCase, resp_ref.lungs.raw.available);
    verifyEqual(testCase, ...
        resp_ref.lungs.raw.excursion, expected_excursion, 'AbsTol', 1e-12);
    verifyEqual(testCase, resp_ref.lungs.raw.n_samples, numel(x_lungs));
    verifyEqual(testCase, resp_ref.lungs.raw.finite_fraction, 1);
    verifyEqual(testCase, resp_ref.lungs.raw.quality, 'good');
    verifyFalse(testCase, isfield(diagnostics.raw_excursion.lungs, ...
        'session_excursion_reference'));
    verifyFalse(testCase, isfield(diagnostics.raw_excursion.lungs, ...
        'reference_source'));
end

function testRawReferenceFiniteCoverageUsesConfiguredThreshold(testCase)
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

    verifyLessThan(testCase, resp_ref.lungs.raw.finite_fraction, ...
        config.reference.resp.raw_min_finite_fraction);
    verifyFalse(testCase, resp_ref.lungs.raw.available);
    verifyEqual(testCase, resp_ref.lungs.raw.quality, ...
        'insufficient_finite_coverage');

    config.reference.resp.raw_min_finite_fraction = 0.75;
    accepted = compute_respiratory_reference( ...
        data, make_resp_feat([], [], [], []), reference, config);
    verifyTrue(testCase, accepted.lungs.raw.available);
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

function testApneaNormalizesCurrentRawMetricsByFixedReferences(testCase)
    config = session_test_config(1, 10);
    config.grid_step_sec = 1;
    config.apnea.do_plot = false;
    N = 121 * config.fs;
    t_raw = (0:N-1)' / config.fs;
    data = zeros(N, numel(config.data_columns));
    data(:, config.channels.lungs_idx) = t_raw;
    phys = raw_only_phys_fixture(N, config);
    resp_ref = explicit_raw_resp_ref(10, NaN);

    [~, diagnostics] = detect_apnea(data, phys, resp_ref, config);
    grid_idx = find(phys.time_sec == 10, 1);
    segment = data(1:10*config.fs+1, config.channels.lungs_idx);

    verifyEqual(testCase, diagnostics.raw_excursion.lungs.excursion_ratio(grid_idx), ...
        robust_resp_excursion(segment) / 10, 'AbsTol', 1e-12);
    verifyEqual(testCase, fieldnames(diagnostics.raw_excursion.lungs), ...
        {'valid'; 'evaluable_endpoint_mask'; 'excursion_ratio'});
end

function testApneaUsesFixedSessionRawExcursionReference(testCase)
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
    resp_ref = explicit_raw_resp_ref(8, NaN);

    [~, diagnostics] = detect_apnea(data, phys, resp_ref, config);
    grid_idx = find(phys.time_sec == 100, 1);
    current = x(90*config.fs+1:100*config.fs+1);

    verifyEqual(testCase, diagnostics.raw_excursion.lungs.excursion_ratio(grid_idx), ...
        robust_resp_excursion(current) / resp_ref.lungs.raw.excursion, ...
        'AbsTol', 1e-12);
end

function testRawApneaWindowUsesConfiguredFiniteCoverage(testCase)
    config = session_test_config(1, 10);
    config.grid_step_sec = 1;
    config.apnea.do_plot = false;
    N = 41 * config.fs;
    t_raw = (0:N-1)' / config.fs;
    data = zeros(N, numel(config.data_columns));
    data(:, config.channels.lungs_idx) = t_raw;
    data(1:15, config.channels.lungs_idx) = NaN;
    phys = raw_only_phys_fixture(N, config);
    resp_ref = explicit_raw_resp_ref(10, NaN);

    config.reference.resp.raw_min_finite_fraction = 0.90;
    [~, strict] = detect_apnea(data, phys, resp_ref, config);
    grid_idx = find(phys.time_sec == 10, 1);
    verifyTrue(testCase, ...
        isnan(strict.raw_excursion.lungs.excursion_ratio(grid_idx)));

    config.reference.resp.raw_min_finite_fraction = 0.80;
    [~, permissive] = detect_apnea(data, phys, resp_ref, config);
    verifyTrue(testCase, ...
        isfinite(permissive.raw_excursion.lungs.excursion_ratio(grid_idx)));
end

function testRawExcursionCannotRescueFailedAmplitude(testCase)
    config = session_test_config(1, 10);
    config.grid_step_sec = 1;
    config.apnea.do_plot = false;
    N = 41 * config.fs;
    t_raw = (0:N-1)' / config.fs;
    base = double(mod((0:N-1)', 10) < 7);
    data = zeros(N, numel(config.data_columns));
    data(:, config.channels.lungs_idx) = base;
    data(t_raw >= 10 & t_raw <= 20, config.channels.lungs_idx) = 0;
    phys = raw_only_phys_fixture(N, config);
    grid_idx = find(phys.time_sec == 20, 1);
    phys.lungs.session_amplitude_available = true;
    phys.lungs.apnea_amplitude_evaluable_endpoint_mask(grid_idx) = true;
    phys.lungs.apnea_amplitude_endpoint_mask(grid_idx) = false;
    phys.lungs.peak_t = 20;
    phys.lungs.amp_ratio_session = 0.50;
    resp_ref = explicit_raw_resp_ref(1, NaN);

    [events, diagnostics] = detect_apnea(data, phys, resp_ref, config);

    lungs = diagnostics.belt_evidence.lungs;
    raw_pass = diagnostics.raw_excursion.lungs.evaluable_endpoint_mask & ...
        diagnostics.raw_excursion.lungs.excursion_ratio <= ...
            config.apnea.raw_excursion_ratio_thr;
    verifyTrue(testCase, ...
        raw_pass(grid_idx));
    verifyTrue(testCase, ...
        phys.lungs.apnea_amplitude_evaluable_endpoint_mask(grid_idx));
    verifyFalse(testCase, ...
        phys.lungs.apnea_amplitude_endpoint_mask(grid_idx));
    verifyFalse(testCase, lungs.raw_fallback_used_endpoint_mask(grid_idx));
    verifyFalse(testCase, lungs.combined_belt_endpoint_mask(grid_idx));
    verifyFalse(testCase, diagnostics.combined_endpoint_mask(grid_idx));
    verifyEmpty(testCase, events);
end

function testRawExcursionSupportsWindowWithoutValidBreaths(testCase)
    config = session_test_config(1, 10);
    config.grid_step_sec = 1;
    config.apnea.do_plot = false;
    N = 41 * config.fs;
    t_raw = (0:N-1)' / config.fs;
    base = double(mod((0:N-1)', 10) < 7);
    data = zeros(N, numel(config.data_columns));
    data(:, config.channels.lungs_idx) = base;
    data(t_raw >= 10 & t_raw <= 20, config.channels.lungs_idx) = 0;
    phys = raw_only_phys_fixture(N, config);
    resp_ref = explicit_raw_resp_ref(1, NaN);
    grid_idx = find(phys.time_sec == 20, 1);

    [events, diagnostics] = detect_apnea(data, phys, resp_ref, config);

    lungs = diagnostics.belt_evidence.lungs;
    verifyFalse(testCase, ...
        phys.lungs.apnea_amplitude_evaluable_endpoint_mask(grid_idx));
    verifyTrue(testCase, ...
        diagnostics.raw_excursion.lungs.evaluable_endpoint_mask(grid_idx));
    verifyTrue(testCase, lungs.raw_fallback_used_endpoint_mask(grid_idx));
    verifyTrue(testCase, lungs.combined_belt_endpoint_mask(grid_idx));
    verifyTrue(testCase, diagnostics.combined_endpoint_mask(grid_idx));
    verifyNotEmpty(testCase, events);
end

function testRawExcursionBeltAvailabilityPreservesAgreementSemantics(testCase)
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
    resp_ref = explicit_raw_resp_ref(2, 2);

    [~, both] = detect_apnea(data, phys, resp_ref, config);
    verifyEqual(testCase, both.raw_excursion_support_belts, 'both');
    lungs_pass = raw_excursion_pass_mask(both, 'lungs', config);
    diaph_pass = raw_excursion_pass_mask(both, 'diaph', config);
    verifyTrue(testCase, any(lungs_pass));
    verifyEqual(testCase, both.combined_endpoint_mask, ...
        lungs_pass & diaph_pass);

    resp_ref.diaph.raw.available = false;
    [~, one] = detect_apnea(data, phys, resp_ref, config);
    verifyEqual(testCase, one.raw_excursion_support_belts, 'lungs');
    verifyEqual(testCase, one.combined_endpoint_mask, ...
        raw_excursion_pass_mask(one, 'lungs', config));
end

function testMixedAmplitudeAndRawFallbackRequireBothBeltsToPass(testCase)
    config = session_test_config(1, 10);
    config.grid_step_sec = 1;
    config.apnea.do_plot = false;
    N = 41 * config.fs;
    t_raw = (0:N-1)' / config.fs;
    base = double(mod((0:N-1)', 10) < 7);
    data = zeros(N, numel(config.data_columns));
    data(:, config.channels.lungs_idx) = base;
    data(:, config.channels.diaph_idx) = base;
    data(t_raw >= 10 & t_raw <= 20, config.channels.lungs_idx) = 0;
    data(t_raw >= 10 & t_raw <= 20, config.channels.diaph_idx) = 0;
    phys = raw_only_phys_fixture(N, config);
    grid_idx = find(phys.time_sec == 20, 1);
    phys.lungs.session_amplitude_available = true;
    phys.lungs.apnea_amplitude_evaluable_endpoint_mask(grid_idx) = true;
    phys.lungs.apnea_amplitude_endpoint_mask(grid_idx) = true;
    phys.lungs.peak_t = 20;
    phys.lungs.amp_ratio_session = 0.05;
    resp_ref = explicit_raw_resp_ref(1, 1);

    [events, mixed] = detect_apnea(data, phys, resp_ref, config);
    verifyTrue(testCase, ...
        phys.lungs.apnea_amplitude_evaluable_endpoint_mask(grid_idx));
    verifyTrue(testCase, ...
        mixed.belt_evidence.diaph.raw_fallback_used_endpoint_mask(grid_idx));
    verifyTrue(testCase, mixed.combined_endpoint_mask(grid_idx));
    verifyNotEmpty(testCase, events);

    phys.diaph.session_amplitude_available = true;
    phys.diaph.apnea_amplitude_evaluable_endpoint_mask(grid_idx) = true;
    phys.diaph.apnea_amplitude_endpoint_mask(grid_idx) = false;
    phys.diaph.peak_t = 20;
    phys.diaph.amp_ratio_session = 0.50;
    [events, disagreement] = detect_apnea(data, phys, resp_ref, config);
    verifyFalse(testCase, ...
        disagreement.belt_evidence.diaph.raw_fallback_used_endpoint_mask(grid_idx));
    verifyFalse(testCase, disagreement.combined_endpoint_mask(grid_idx));
    verifyEmpty(testCase, events);
end

function testNeitherEvaluableBeltCreatesNoApneaCandidate(testCase)
    config = session_test_config(1, 10);
    config.grid_step_sec = 1;
    config.apnea.do_plot = false;
    N = 41 * config.fs;
    data = nan(N, numel(config.data_columns));
    phys = raw_only_phys_fixture(N, config);
    resp_ref = explicit_raw_resp_ref(NaN, NaN);

    [events, diagnostics, candidates] = detect_apnea( ...
        data, phys, resp_ref, config);

    verifyFalse(testCase, any(diagnostics.combined_evaluable_endpoint_mask));
    verifyFalse(testCase, any(diagnostics.combined_endpoint_mask));
    verifyEmpty(testCase, events);
    verifyEmpty(testCase, candidates);
    verifyEqual(testCase, fieldnames(candidates), ...
        fieldnames(empty_candidate_events()));
end

function testApneaFinalDurationRejectsShortCombinedSupport(testCase)
    config = session_test_config(1, 10);
    t_grid = (0:30)';
    combined_support = t_grid >= 10 & t_grid < 19;

    [events, retained_mask] = sustained_condition_to_events( ...
        combined_support, t_grid, config.fs, 31 * config.fs, ...
        config.apnea.min_dur_sec, 'apnea');

    verifyEmpty(testCase, events);
    verifyFalse(testCase, any(retained_mask));

    repo_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    source = fileread(fullfile(repo_root, 'src', ...
        'label_detection', 'detect_apnea.m'));
    verifyNotEmpty(testCase, regexp(source, ...
        'sustained_condition_to_events\(\s*\.\.\.\s*candidate_state_mask,[\s\S]*?min_dur_sec', ...
        'once'));
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
    verifyFalse(testCase, diagnostics.raw_excursion.lungs.valid);
    verifyFalse(testCase, diagnostics.raw_excursion.diaph.valid);
    verifyEqual(testCase, resp_ref.lungs.raw.quality, ...
        'reference_interval_unavailable');
    verifyEqual(testCase, resp_ref.diaph.raw.quality, ...
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

function testCurrentReferenceConfigurationAndApneaSourceSemantics(testCase)
    config = get_config_defaults();
    verifyFalse(testCase, isfield(config, 'baseline_sec'));
    verifyFalse(testCase, isfield(config, 'baseline_location'));
    verifyFalse(testCase, isfield(config, 'resp_ref'));
    verifyEqual(testCase, fieldnames(config.apnea), ...
        {'min_dur_sec'; 'amp_ratio_thr'; 'raw_excursion_ratio_thr'; 'do_plot'});
    verifyEqual(testCase, config.apnea.min_dur_sec, 10);
    verifyEqual(testCase, config.apnea.amp_ratio_thr, 0.10);
    verifyEqual(testCase, config.apnea.raw_excursion_ratio_thr, 0.10);
    verifyEqual(testCase, config.reference.resp.raw_min_finite_fraction, 0.80);

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
    required_apnea_source = { ...
        'raw_cfg.win_sec = min_dur_sec', ...
        '''raw_excursion_ratio_thr'', 0.10', ...
        'select_belt_apnea_evidence', ...
        'raw_fallback_used_endpoint_mask', ...
        'combine_belt_evidence', ...
        'sustained_condition_to_events'};
    for i = 1:numel(required_apnea_source)
        verifyTrue(testCase, contains(apnea_source, required_apnea_source{i}));
    end
end

function mask = raw_excursion_pass_mask(diagnostics, belt, config)
% RAW_EXCURSION_PASS_MASK Reconstruct the configured decision from saved evidence.

    evidence = diagnostics.raw_excursion.(belt);
    mask = evidence.evaluable_endpoint_mask & ...
        evidence.excursion_ratio <= config.apnea.raw_excursion_ratio_thr;
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
    belt = struct( ...
        'ignored', false, ...
        'session_amplitude_available', false, ...
        'peak_t', zeros(0, 1), ...
        'amp_ratio_session', zeros(0, 1), ...
        'apnea_amplitude_evaluable_endpoint_mask', false(size(t_grid)), ...
        'apnea_amplitude_endpoint_mask', false(size(t_grid)), ...
        'apnea_amplitude_state_mask', false(size(t_grid)));
    phys = struct('time_sec', t_grid, 'lungs', belt, 'diaph', belt);
end

function resp_ref = explicit_raw_resp_ref(lungs_excursion, diaph_excursion)
% EXPLICIT_RAW_RESP_REF Build fixed raw references for detector-only tests.

    lungs = raw_reference_fixture(lungs_excursion);
    diaph = raw_reference_fixture(diaph_excursion);
    session = struct('value', 100, 'available', true);
    resp_ref = struct( ...
        'lungs', struct('session', session, 'raw', lungs), ...
        'diaph', struct('session', session, 'raw', diaph));
end

function raw = raw_reference_fixture(excursion)
% RAW_REFERENCE_FIXTURE Build one complete fixed raw-reference schema.

    available = isfinite(excursion) && excursion > 0;
    raw = struct('available', available, 'quality', 'test_reference', ...
        'n_samples', 100, 'finite_fraction', 1, 'excursion', excursion);
end
