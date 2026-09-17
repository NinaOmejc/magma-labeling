function tests = test_sigh_detection_methods
% Focused tests for selectable breath-level sigh detection methods.

    tests = functiontests(localfunctions);
end

function testRollingMedianIsTheConfiguredDefault(testCase)
    config = get_config();

    verifyEqual(testCase, config.sigh.method, 'rolling_median_2x');
    verifyEqual(testCase, config.sigh.rolling_window_breaths, 15);
    verifyEqual(testCase, config.sigh.rolling_min_valid_breaths, 3);
    verifyEqual(testCase, config.sigh.rolling_ratio_threshold, 2.0);
    verifyFalse(testCase, config.sigh.compare_methods);
end

function testModestVariabilityDoesNotForceSighs(testCase)
    amplitude = 1 + 0.08 * sin((1:25)' / 3);
    amplitude(1) = NaN;
    [events, diagnostics, review] = run_rolling(amplitude);

    verifyEmpty(testCase, events);
    verifyFalse(testCase, any(review.automatic_flags_lungs));
    verifyEqual(testCase, diagnostics.lungs.sigh_flags, ...
        review.automatic_flags_lungs);
end

function testIsolatedLargeInspirationIsDetected(testCase)
    amplitude = ones(25, 1);
    amplitude(1) = NaN;
    amplitude(13) = 2.2;
    [events, diagnostics, review] = run_rolling(amplitude);

    verifyNotEmpty(testCase, events);
    verifyEqual(testCase, find(review.automatic_flags_lungs), 13);
    verifyEqual(testCase, diagnostics.lungs.sigh_amplitude, amplitude);
    verifyEqual(testCase, diagnostics.lungs.sigh_baseline(13), 1);
    verifyEqual(testCase, diagnostics.lungs.sigh_ratio(13), 2.2, ...
        'AbsTol', eps);
end

function testThresholdIsInclusiveAtTwo(testCase)
    at_threshold = ones(21, 1);
    at_threshold(1) = NaN;
    at_threshold(11) = 2.0;
    [~, diagnostics, review] = run_rolling(at_threshold);
    verifyTrue(testCase, review.automatic_flags_lungs(11));
    verifyEqual(testCase, diagnostics.lungs.sigh_ratio(11), 2.0);

    below_threshold = at_threshold;
    below_threshold(11) = 1.99;
    [~, diagnostics, review] = run_rolling(below_threshold);
    verifyFalse(testCase, review.automatic_flags_lungs(11));
    verifyEqual(testCase, diagnostics.lungs.sigh_ratio(11), 1.99, ...
        'AbsTol', eps);
end

function testGradualAmplitudeTrendAdaptsWithoutFalseSeries(testCase)
    amplitude = linspace(1, 2, 31)';
    amplitude(1) = NaN;
    [events, ~, review] = run_rolling(amplitude);

    verifyEmpty(testCase, events);
    verifyFalse(testCase, any(review.automatic_flags_lungs));
end

function testShortenedWindowsDetectNearBothEdges(testCase)
    amplitude = ones(20, 1);
    amplitude(1) = NaN;
    amplitude(2) = 3;
    amplitude(end) = 3;
    [~, diagnostics, review] = run_rolling(amplitude);

    verifyTrue(testCase, review.automatic_flags_lungs(2));
    verifyTrue(testCase, review.automatic_flags_lungs(end));
    verifyEqual(testCase, diagnostics.lungs.sigh_baseline([2 end]), [1; 1]);
end

function testInvalidAmplitudesAreIgnoredAndNeverClassified(testCase)
    amplitude = ones(21, 1);
    amplitude([1 5 6]) = NaN;
    amplitude(11) = 2.1;
    [~, diagnostics, review] = run_rolling(amplitude);

    verifyFalse(testCase, any(review.automatic_flags_lungs([1 5 6])));
    verifyTrue(testCase, review.automatic_flags_lungs(11));
    verifyTrue(testCase, all(isnan(diagnostics.lungs.sigh_ratio([1 5 6]))));
    verifyEqual(testCase, diagnostics.lungs.sigh_baseline(11), 1);
end

function testFewerThanFifteenBreathsAreHandledSafely(testCase)
    amplitude = [NaN; 1; 2; 1; NaN];
    [~, diagnostics, review] = run_rolling(amplitude);
    verifyTrue(testCase, review.automatic_flags_lungs(3));
    verifyEqual(testCase, diagnostics.lungs.sigh_baseline(3), 1);

    [events, diagnostics, review] = run_rolling([NaN; 2]);
    verifyEmpty(testCase, events);
    verifyFalse(testCase, diagnostics.available);
    verifyFalse(testCase, any(review.automatic_flags_lungs));
    verifyTrue(testCase, all(isnan(diagnostics.lungs.sigh_baseline)));
end

function testRollingMethodUsesInspiratoryAmplitudeNotSelectedAmplitude(testCase)
    inspiratory = ones(21, 1);
    inspiratory(1) = NaN;
    inspiratory(11) = 2.2;
    selected = 10 * ones(size(inspiratory));
    [data, features, cycles, config] = sigh_fixture(inspiratory, selected);

    [~, diagnostics, review] = detect_sigh(data, features, cycles, config);

    verifyEqual(testCase, diagnostics.lungs.sigh_amplitude, inspiratory);
    verifyTrue(testCase, review.automatic_flags_lungs(11));
end

function testOptionalComparisonReportsCountsThresholdAndAgreement(testCase)
    inspiratory = ones(25, 1);
    inspiratory(1) = NaN;
    inspiratory(13) = 2.2;
    global_amplitude = ones(25, 1);
    global_amplitude(13) = 2.2;
    [data, features, cycles, config] = ...
        sigh_fixture(inspiratory, global_amplitude); %#ok<ASGLU>
    config.sigh.compare_methods = true;

    output = evalc( ...
        '[~, diagnostics, ~] = detect_sigh(data, features, cycles, config);');
    comparison = diagnostics.comparison.lungs;

    verifyTrue(testCase, diagnostics.comparison.enabled);
    verifyTrue(testCase, comparison.available);
    verifyEqual(testCase, comparison.valid_breath_count, 24);
    verifyEqual(testCase, comparison.rolling_median_2x_count, 1);
    verifyEqual(testCase, comparison.global_ratio_outlier_count, 1);
    verifyEqual(testCase, comparison.both_count, 1);
    verifyEqual(testCase, comparison.rolling_median_2x_only_count, 0);
    verifyEqual(testCase, comparison.global_ratio_outlier_only_count, 0);
    verifyEqual(testCase, comparison.agreement_percent, 100);
    verifyGreaterThanOrEqual(testCase, ...
        comparison.global_ratio_outlier_threshold, 2.0);
    verifyTrue(testCase, contains(output, ...
        'Sigh detection comparison (lungs)'));
    verifyTrue(testCase, contains(output, 'overlap: 1'));
end

function testGlobalRatioOutlierMatchesFrozenPreviousImplementation(testCase)
    inspiratory = ones(25, 1);
    inspiratory(1) = NaN;
    global_amplitude = ones(25, 1);
    global_amplitude(13) = 4;
    [data, features, cycles, config] = ...
        sigh_fixture(inspiratory, global_amplitude);
    config.sigh.method = 'global_ratio_outlier';

    expected = frozen_global_ratio_outlier( ...
        features.lungs, config.sigh.ratio_prctile, ...
        config.sigh.min_abs_ratio, config.sigh.iqr_k, ...
        config.sigh.min_gap_sec);
    [~, diagnostics, review] = detect_sigh(data, features, cycles, config);

    verifyEqual(testCase, review.automatic_flags_lungs, expected);
    verifyEqual(testCase, diagnostics.sigh_method, 'global_ratio_outlier');
end

function testLegacy60sMatchesFrozenPreviousImplementation(testCase)
    inspiratory = ones(25, 1);
    inspiratory(1) = NaN;
    selected = ones(25, 1);
    selected(18) = 2;
    [data, features, cycles, config] = sigh_fixture(inspiratory, selected);
    config.sigh.method = 'legacy_60s';

    expected = frozen_legacy_60s(features.lungs, ...
        config.sigh.legacy_prev_win_sec, ...
        config.sigh.legacy_amp_ratio_thr, ...
        config.sigh.legacy_min_prev_breaths);
    [~, diagnostics, review] = detect_sigh(data, features, cycles, config);

    verifyEqual(testCase, review.automatic_flags_lungs, expected);
    verifyEqual(testCase, diagnostics.sigh_method, 'legacy_60s');
end

function [events, diagnostics, review] = run_rolling(amplitude)
    [data, features, cycles, config] = sigh_fixture(amplitude, ones(size(amplitude)));
    [events, diagnostics, review] = detect_sigh(data, features, cycles, config);
end

function [data, features, cycles, config] = ...
    sigh_fixture(inspiratory_amplitude, selected_amplitude)

    config = get_config();
    config.fs = 10;
    config.subject = 999;
    config.measure = 1;
    config.make_figs_visible = 'off';
    config.sigh.method = 'rolling_median_2x';
    config.sigh.do_plot = false;
    config.sigh.manual_control = false;
    config.sigh.compare_methods = false;

    inspiratory_amplitude = inspiratory_amplitude(:);
    selected_amplitude = selected_amplitude(:);
    n_breaths = numel(inspiratory_amplitude);
    peak_t = 2 + 4 * (0:n_breaths - 1)';
    n_samples = max(100, round((max([0; peak_t]) + 2) * config.fs));
    data = zeros(n_samples, 6);

    lungs = struct( ...
        'available', true, ...
        'ignored', false, ...
        'peak_t', peak_t, ...
        'amp', selected_amplitude, ...
        'amp_ratio_global', selected_amplitude, ...
        'global_reference_value', 1, ...
        'global_amplitude_available', true, ...
        'reference_quality', 'good');
    diaph = struct( ...
        'available', false, ...
        'ignored', false, ...
        'peak_t', zeros(0, 1), ...
        'amp', zeros(0, 1), ...
        'amp_ratio_global', zeros(0, 1), ...
        'global_reference_value', NaN, ...
        'global_amplitude_available', false, ...
        'reference_quality', 'belt_unavailable');
    features = struct('lungs', lungs, 'diaph', diaph);

    cycle_lungs = struct( ...
        'ok', true, ...
        'peak_t', peak_t, ...
        'amp', selected_amplitude, ...
        'amp_insp', inspiratory_amplitude);
    cycles = struct( ...
        'lungs', cycle_lungs, ...
        'diaph', empty_respiration_feature('Resp-Diaphragm'));
end

function flags = frozen_global_ratio_outlier( ...
    belt, ratio_prctile, min_abs_ratio, iqr_k, min_gap_sec)
% Frozen copy of the pre-change global_ratio_outlier decision behavior.

    peak_t = belt.peak_t(:);
    amplitude = belt.amp(:);
    L = min(numel(peak_t), numel(amplitude));
    peak_t = peak_t(1:L);
    amplitude = amplitude(1:L);
    flags = false(L, 1);
    if L < 10
        return;
    end
    ratio = belt.amp_ratio_global(:);
    ratio = ratio(1:L);
    baseline = belt.global_reference_value * ones(L, 1);
    valid = isfinite(ratio) & ratio > 0 & isfinite(amplitude) & ...
        amplitude > 0 & isfinite(baseline) & baseline > 0;
    if sum(valid) < 10
        return;
    end
    values = ratio(valid);
    threshold = max([prctile(values, ratio_prctile), ...
        median(values, 'omitnan') + iqr_k * iqr(values), min_abs_ratio]);
    candidates = false(L, 1);
    candidates(valid) = ratio(valid) >= threshold;
    flags = frozen_min_gap(candidates, peak_t, ratio, min_gap_sec);
end

function flags = frozen_legacy_60s( ...
    belt, previous_window_sec, ratio_threshold, min_previous_breaths)
% Frozen copy of the pre-change legacy_60s decision behavior.

    peak_t = belt.peak_t(:);
    amplitude = belt.amp(:);
    L = min(numel(peak_t), numel(amplitude));
    peak_t = peak_t(1:L);
    amplitude = amplitude(1:L);
    flags = false(L, 1);
    for i = 1:L
        lower_bound = peak_t(i) - previous_window_sec;
        if lower_bound < 0
            continue;
        end
        previous = find(peak_t < peak_t(i) & peak_t >= lower_bound);
        if numel(previous) < min_previous_breaths
            continue;
        end
        previous_median = median(amplitude(previous), 'omitnan');
        if ~isfinite(previous_median) || previous_median <= 0 || ...
                ~isfinite(amplitude(i))
            continue;
        end
        flags(i) = amplitude(i) >= ratio_threshold * previous_median;
    end
end

function flags_out = frozen_min_gap(flags_in, peak_t, strength, min_gap_sec)
% Frozen copy of the pre-change strongest-candidate spacing behavior.

    flags_out = false(size(flags_in));
    candidates = find(flags_in);
    [~, order] = sort(strength(candidates), 'descend', ...
        'MissingPlacement', 'last');
    candidates = candidates(order);
    for k = 1:numel(candidates)
        i = candidates(k);
        if ~isfinite(peak_t(i)) || ~isfinite(strength(i))
            continue;
        end
        retained = find(flags_out);
        if isempty(retained) || ...
                ~any(abs(peak_t(retained) - peak_t(i)) < min_gap_sec)
            flags_out(i) = true;
        end
    end
end
