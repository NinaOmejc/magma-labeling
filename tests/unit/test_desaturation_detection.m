function tests = test_desaturation_detection
% Focused tests for independent desaturation branches and event descriptors.

    tests = functiontests(localfunctions);
end

function testAbsoluteDetectionWithoutSessionReference(testCase)
    config = desaturation_config(1);
    data = 88 * ones(20, 1);
    [events, diagnostics, reference] = detect_desaturation( ...
        data, unavailable_reference(), config);

    verifyFalse(testCase, reference.available);
    verifyTrue(testCase, diagnostics.signal_available);
    verifyTrue(testCase, diagnostics.absolute_available);
    verifyFalse(testCase, diagnostics.relative_available);
    verifyTrue(testCase, diagnostics.detection_available);
    verifyEqual(testCase, diagnostics.detection_mode, 'absolute_only');
    verifyEqual(testCase, [events.start_idx], 1);
    verifyEqual(testCase, [events.end_idx], 20);
    metric = diagnostics.event_metrics_automatic(1);
    verifyEqual(testCase, metric.absolute_support_fraction, 1);
    verifyTrue(testCase, isnan(metric.relative_support_fraction));
    verifyTrue(testCase, isnan(metric.session_drop_pp));
end

function testUnavailableReferenceLeavesRelativeBranchUnevaluable(testCase)
    config = desaturation_config(1);
    [events, diagnostics] = detect_desaturation( ...
        92 * ones(20, 1), unavailable_reference(), config);

    verifyEmpty(testCase, events);
    verifyTrue(testCase, diagnostics.detection_available);
    verifyTrue(testCase, diagnostics.absolute_available);
    verifyFalse(testCase, diagnostics.relative_available);
    verifyEqual(testCase, diagnostics.detection_mode, 'absolute_only');
end

function testRelativeDetectionWithValidReference(testCase)
    config = desaturation_config(1);
    data = 98 * ones(60, 1);
    data(31:45) = 94;
    [events, diagnostics, reference] = detect_desaturation( ...
        data, valid_reference(1, 20), config);

    verifyEqual(testCase, reference.median_percent, 98);
    verifyTrue(testCase, diagnostics.relative_available);
    verifyEqual(testCase, diagnostics.detection_mode, ...
        'absolute_and_relative');
    verifyEqual(testCase, [events.start_idx], 31);
    verifyEqual(testCase, [events.end_idx], 45);
    verifyEqual(testCase, ...
        diagnostics.event_metrics_automatic.relative_support_fraction, 1);
    verifyEqual(testCase, ...
        diagnostics.event_metrics_automatic.absolute_support_fraction, 0);
end

function testValidReferencePreservesCombinedLegacyEventDefinition(testCase)
    config = desaturation_config(1);
    data = 98 * ones(80, 1);
    data(21:31) = 94;
    data(45:59) = 88;
    expected_mask = data < config.desat.spo2_floor | ...
        (98 - data) >= config.desat.drop_thr;
    expected_events = runs_to_events(expected_mask, config.fs, ...
        config.desat.min_dur_sec, 'desaturation');

    [actual_events, diagnostics] = detect_desaturation( ...
        data, valid_reference(1, 20), config);

    verifyEqual(testCase, actual_events, expected_events);
    verifyEqual(testCase, reshape( ...
        [diagnostics.event_metrics_automatic.start_idx; ...
         diagnostics.event_metrics_automatic.end_idx], 2, [])', ...
        reshape([actual_events.start_idx; actual_events.end_idx], 2, [])');
end

function testExactBranchInequalities(testCase)
    config = desaturation_config(1);
    config.desat.min_dur_sec = 1;
    [absolute_events, diagnostics] = detect_desaturation( ...
        [90; 89.9], unavailable_reference(), config);
    verifyEqual(testCase, [absolute_events.start_idx], 2);
    verifyEqual(testCase, diagnostics.thresholds.absolute_inequality, '<');

    data = [98; 98; 95; 95.1];
    [relative_events, diagnostics] = detect_desaturation( ...
        data, valid_reference(1, 2), config);
    verifyEqual(testCase, [relative_events.start_idx], 3);
    verifyEqual(testCase, [relative_events.end_idx], 3);
    verifyEqual(testCase, diagnostics.thresholds.relative_inequality, '>=');
end

function testNanGapBreaksCombinedSupport(testCase)
    config = desaturation_config(1);
    data = [88 * ones(6, 1); NaN; 88 * ones(6, 1)];
    events = detect_desaturation(data, unavailable_reference(), config);

    verifyEmpty(testCase, events);
end

function testAbsoluteOnlyAvailabilityPropagatesToReviewAssessability(testCase)
    config = desaturation_config(1);
    data = 92 * ones(20, 1);
    data(5) = NaN;
    [~, diagnostics] = detect_desaturation( ...
        data, unavailable_reference(), config);
    labels = {'desat'};
    [available, reason] = compute_label_availability( ...
        labels, minimal_resp_features(), diagnostics, struct(), ...
        struct(), struct(), struct());
    [assessable, ~] = compute_label_assessable_mask( ...
        data, labels, available, struct(), (0:19)', config);
    review = false(20, 1);
    review(1:4) = true;
    [reviewed_assessable, reviewed_available] = ...
        compute_reviewed_label_availability( ...
            available, reason, assessable, review);

    verifyTrue(testCase, available);
    verifyEqual(testCase, reason, {'available'});
    verifyFalse(testCase, assessable(5));
    verifyTrue(testCase, all(assessable([1:4 6:end])));
    verifyTrue(testCase, reviewed_available);
    verifyTrue(testCase, all(reviewed_assessable(1:4)));
end

function testEventNadirDepthLocalBaselineAndRecovery(testCase)
    config = desaturation_config(1);
    data = 97 * ones(100, 1);
    data(41:55) = 89;
    data(46:47) = 85;
    [events, diagnostics] = detect_desaturation( ...
        data, valid_reference(1, 20), config);
    metric = diagnostics.event_metrics_automatic(1);

    verifyEqual(testCase, [events.start_idx events.end_idx], [41 55]);
    verifyEqual(testCase, metric.start_idx, events.start_idx);
    verifyEqual(testCase, metric.end_idx, events.end_idx);
    verifyEqual(testCase, metric.nadir_spo2_percent, 85);
    verifyEqual(testCase, metric.nadir_idx, 46);
    verifyEqual(testCase, metric.nadir_t, 45);
    verifyEqual(testCase, metric.session_drop_pp, 12);
    verifyEqual(testCase, metric.pre_event_baseline_spo2, 97);
    verifyTrue(testCase, metric.pre_event_baseline_available);
    verifyEqual(testCase, metric.pre_event_support_sec, 30);
    verifyEqual(testCase, metric.local_drop_pp, 12);
    verifyTrue(testCase, metric.recovery_observed);
    verifyEqual(testCase, metric.recovery_idx, 56);
    verifyEqual(testCase, metric.recovery_t, 55);
    verifyEqual(testCase, metric.nadir_to_recovery_sec, 10);
    verifyEqual(testCase, metric.recovery_status, 'observed');
    verifyEqual(testCase, metric.detection_support_mode, ...
        'absolute_and_relative');
end

function testMissingPreEventBaselineIsExplicit(testCase)
    config = desaturation_config(1);
    data = [88 * ones(10, 1); 97 * ones(20, 1)];
    [events, diagnostics] = detect_desaturation( ...
        data, unavailable_reference(), config);
    metric = diagnostics.event_metrics_automatic(1);

    verifyEqual(testCase, [events.start_idx events.end_idx], [1 10]);
    verifyFalse(testCase, metric.pre_event_baseline_available);
    verifyTrue(testCase, isnan(metric.pre_event_baseline_spo2));
    verifyEqual(testCase, metric.pre_event_baseline_status, 'recording_start');
    verifyEqual(testCase, metric.recovery_status, 'no_pre_event_baseline');
    verifyTrue(testCase, isnan(metric.nadir_to_recovery_sec));
end

function testNextEventInterruptsRecovery(testCase)
    config = desaturation_config(1);
    data = 97 * ones(90, 1);
    data(31:40) = 88;
    data(41:50) = 94;
    data(51:60) = 88;
    [events, diagnostics] = detect_desaturation( ...
        data, unavailable_reference(), config);

    verifyEqual(testCase, reshape([events.start_idx; events.end_idx], 2, [])', ...
        [31 40; 51 60]);
    verifyEqual(testCase, ...
        diagnostics.event_metrics_automatic(1).recovery_status, ...
        'next_event_before_recovery');
    verifyFalse(testCase, ...
        diagnostics.event_metrics_automatic(1).recovery_observed);
end

function testInvalidDataInterruptsRecovery(testCase)
    config = desaturation_config(1);
    data = 97 * ones(80, 1);
    data(31:40) = 88;
    data(41:44) = 94;
    data(45) = NaN;
    [~, diagnostics] = detect_desaturation( ...
        data, unavailable_reference(), config);

    verifyEqual(testCase, ...
        diagnostics.event_metrics_automatic(1).recovery_status, ...
        'invalid_data_before_recovery');
end

function testRecordingEndCensorsRecoveryWithoutChangingEvent(testCase)
    config = desaturation_config(1);
    data = 97 * ones(50, 1);
    data(31:40) = 88;
    data(41:50) = 94;
    [events, diagnostics] = detect_desaturation( ...
        data, unavailable_reference(), config);

    verifyEqual(testCase, [events.start_idx events.end_idx], [31 40]);
    metric = diagnostics.event_metrics_automatic(1);
    verifyFalse(testCase, metric.recovery_observed);
    verifyEqual(testCase, metric.recovery_status, 'recording_end_censored');
    verifyTrue(testCase, isnan(metric.recovery_idx));
    verifyTrue(testCase, isnan(metric.nadir_to_recovery_sec));
end

function config = desaturation_config(fs)
    config = struct();
    config.fs = fs;
    config.subject = 999;
    config.measure = 1;
    config.make_figs_visible = 'off';
    config.data_columns = {'SpO2'};
    config.channels = struct( ...
        'lungs_idx', [], 'diaph_idx', [], 'spo2_idx', 1);
    config.reference = struct('spo2_min_valid_samples', 2);
    config.desat = struct( ...
        'spo2_floor', 90, ...
        'drop_thr', 3, ...
        'min_dur_sec', 10, ...
        'do_plot', false, ...
        'metrics', struct( ...
            'pre_event_lookback_sec', 30, ...
            'min_pre_event_valid_sec', 10, ...
            'recovery_tolerance_pp', 1, ...
            'recovery_hold_sec', 5, ...
            'max_recovery_search_sec', 120));
end

function reference = unavailable_reference()
    reference = struct( ...
        'available', false, ...
        'complete', false, ...
        'reference_start_idx', NaN, ...
        'reference_end_idx', NaN);
end

function reference = valid_reference(start_idx, end_idx)
    reference = struct( ...
        'available', true, ...
        'complete', true, ...
        'reference_start_idx', start_idx, ...
        'reference_end_idx', end_idx);
end

function features = minimal_resp_features()
    belt = struct( ...
        'available', false, ...
        'session_amplitude_available', false, ...
        'rate_slow_window_bpm', [], ...
        'rate_rapid_window_bpm', [], ...
        'irregularity', struct('cov', []));
    features = struct( ...
        'lungs', belt, ...
        'diaph', belt, ...
        'thoracoabdominal_balance', struct('available', false));
end
