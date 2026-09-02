function tests = test_session_respiratory_reference
% Regression tests for the fixed, reviewed-breath session reference.
    tests = functiontests(localfunctions);
end

function testProtocolIntervalsFollowMeasurement(testCase)
    cases = [1 120 420; 2 1080 1380; 3 120 420; 4 1080 1380];
    t = (0:3:1500)';
    amp = ones(size(t));

    for i = 1:size(cases, 1)
        config = session_test_config(cases(i, 1));
        resp_ref = compute_respiratory_reference(make_resp_feat(t, amp, t, amp), config);
        verifyEqual(testCase, resp_ref.session_interval.start_t, cases(i, 2));
        verifyEqual(testCase, resp_ref.session_interval.end_t, cases(i, 3));
        verifyEqual(testCase, resp_ref.lungs.session.start_t, cases(i, 2));
        verifyEqual(testCase, resp_ref.lungs.session.end_t, cases(i, 3));
    end
end

function testSessionAndGlobalUseFinitePositiveReviewedBreaths(testCase)
    config = session_test_config(1);
    config.resp_ref.session_min_breaths = 5;
    t = (0:3:600)';
    amp = ones(size(t));
    amp(t >= 120 & t <= 420) = 2;
    amp(t == 150) = NaN;
    amp(t == 180) = 0;

    resp_ref = compute_respiratory_reference(make_resp_feat(t, amp, [], []), config);

    verifyTrue(testCase, resp_ref.lungs.session.available);
    verifyEqual(testCase, resp_ref.lungs.session.value, 2, 'AbsTol', eps);
    verifyEqual(testCase, resp_ref.lungs.session.n_breaths, 99);
    verifyTrue(testCase, resp_ref.lungs.global.available);
    verifyGreaterThan(testCase, resp_ref.lungs.global.value, 0);
    verifyEqual(testCase, resp_ref.lungs.global_to_session_ratio, ...
        resp_ref.lungs.global.value / 2, 'AbsTol', eps);
end

function testBeltsHaveIndependentReferences(testCase)
    config = session_test_config(1);
    t = (0:3:600)';
    lungs_amp = 3 * ones(size(t));
    diaph_amp = 1.2 * ones(size(t));

    resp_ref = compute_respiratory_reference( ...
        make_resp_feat(t, lungs_amp, t, diaph_amp), config);

    verifyEqual(testCase, resp_ref.lungs.session.value, 3, 'AbsTol', eps);
    verifyEqual(testCase, resp_ref.diaph.session.value, 1.2, 'AbsTol', eps);
end

function testDriftDoesNotAlterFixedSessionReference(testCase)
    config = session_test_config(1);
    t = (0:3:1500)';
    amp = 2 * ones(size(t));
    after = t > 420;
    amp(after) = linspace(2, 1, nnz(after));

    resp_ref = compute_respiratory_reference(make_resp_feat(t, amp, [], []), config);
    [value, available, quality] = get_resp_session_reference(resp_ref, 'lungs');

    verifyTrue(testCase, available);
    verifyEqual(testCase, value, 2, 'AbsTol', eps);
    verifyLessThan(testCase, resp_ref.lungs.global_to_session_ratio, 1);
    verifyEqual(testCase, quality, resp_ref.lungs.reference_quality);
    verifyEqual(testCase, resp_ref.lungs.reference_action, 'retain_data_no_correction');
    verifyEqual(testCase, resp_ref.default_warning_action, 'retain_data_no_correction');
end

function testStepWarningRetainsUsableReference(testCase)
    config = session_test_config(1);
    config.resp_ref.edge_window_sec = 300;
    config.resp_ref.min_segment_breaths = 12;
    t = (0:3:597)';
    amp = [ones(100, 1); 0.5 * ones(100, 1)];

    resp_ref = compute_respiratory_reference(make_resp_feat(t, amp, [], []), config);
    [value, available, quality] = get_resp_session_reference(resp_ref, 'lungs');

    verifyTrue(testCase, resp_ref.lungs.change_detected);
    verifyEqual(testCase, quality, 'step_candidate');
    verifyTrue(testCase, available);
    verifyTrue(testCase, isfinite(value) && value > 0);
    verifyEqual(testCase, resp_ref.lungs.reference_action, 'retain_data_no_correction');
end

function testInsufficientSessionDoesNotFallBackToGlobal(testCase)
    config = session_test_config(1);
    config.resp_ref.session_min_breaths = 10;
    t = (0:3:90)';
    amp = ones(size(t));

    resp_ref = compute_respiratory_reference(make_resp_feat(t, amp, [], []), config);
    [value, available, quality] = get_resp_session_reference(resp_ref, 'lungs');

    verifyTrue(testCase, resp_ref.lungs.global.available);
    verifyFalse(testCase, resp_ref.lungs.session.available);
    verifyTrue(testCase, isnan(resp_ref.lungs.session.value));
    verifyFalse(testCase, available);
    verifyTrue(testCase, isnan(value));
    verifyEqual(testCase, quality, 'insufficient_breaths');
end

function testShallowDetectorUsesSessionReference(testCase)
    config = session_test_config(1);
    config.fs = 1;
    config.grid_step_sec = 1;
    config.ShB.do_plot = false;
    config.ShB.exclude_desat = false;
    config.problems.missing_lung_belt = zeros(0, 2);

    t = (0:3:600)';
    amp = 2 * ones(size(t));
    amp(t >= 450 & t <= 520) = 1.4;
    resp_feat = make_resp_feat(t, amp, [], []);
    resp_feat.lungs.ok = true;
    resp_feat.diaph.ok = false;
    resp_ref = compute_respiratory_reference(resp_feat, config);

    data = zeros(650, 6);
    baseline = struct();
    spo2_feat = struct('desat_events', empty_events());
    events = detect_shallow_breathing( ...
        data, resp_ref, baseline, resp_feat, spo2_feat, config);

    verifyNotEmpty(testCase, events);
    verifyTrue(testCase, any(contains(string({events.type}), 'shallow_breathing_lungs')));
end

function testComputeBaselineIsSpO2Only(testCase)
    config = session_test_config(1);
    config.fs = 10;
    config.baseline_sec = 10;
    config.baseline_location = 'first';
    config = resolve_signal_channels(config);
    data = zeros(200, 6);
    data(:, config.channels.spo2_idx) = 95;

    baseline = compute_baseline(data, config);

    verifyEqual(testCase, baseline.SpO2_median, 95, 'AbsTol', eps);
    verifyEqual(testCase, baseline.SpO2_mean, 95, 'AbsTol', eps);
    verifyEqual(testCase, fieldnames(baseline), { ...
        'static_baseline_start_idx'; ...
        'static_baseline_end_idx'; ...
        'static_baseline_start_t'; ...
        'static_baseline_end_t'; ...
        'static_baseline_location'; ...
        'SpO2_baseline_start_idx'; ...
        'SpO2_baseline_end_idx'; ...
        'SpO2_baseline_start_t'; ...
        'SpO2_baseline_end_t'; ...
        'SpO2_median'; ...
        'SpO2_mean'});
    verifyFalse(testCase, isfield(config, 'rolling_baseline'));
end

function config = session_test_config(measure)
    config = make_test_config();
    config.measure = measure;
    config.resp_ref.session_pre_start_min = 2;
    config.resp_ref.session_pre_end_min = 7;
    config.resp_ref.session_post_start_min = 18;
    config.resp_ref.session_post_end_min = 23;
    config.resp_ref.session_min_breaths = 10;
    config.resp_ref.do_plot = false;
end

function resp_feat = make_resp_feat(t_lungs, amp_lungs, t_diaph, amp_diaph)
    resp_feat = struct();
    resp_feat.lungs = struct('ok', ~isempty(t_lungs), ...
        'peak_t', t_lungs(:), 'amp', amp_lungs(:));
    resp_feat.diaph = struct('ok', ~isempty(t_diaph), ...
        'peak_t', t_diaph(:), 'amp', amp_diaph(:));
end
