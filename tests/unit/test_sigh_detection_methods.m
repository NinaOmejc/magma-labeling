function tests = test_sigh_detection_methods
% Focused tests for fixed-reference and alternative sigh detection methods.

    tests = functiontests(localfunctions);
end

function testSessionReferenceIsTheConfiguredDefault(testCase)
    config = get_config_defaults();

    verifyEqual(testCase, config.sigh.method, 'session_reference_2x');
    verifyEqual(testCase, config.sigh.session_ratio_threshold, 2.0);
    verifyEqual(testCase, config.sigh.rolling_window_breaths, 15);
    verifyEqual(testCase, config.sigh.rolling_min_valid_breaths, 3);
    verifyEqual(testCase, config.sigh.rolling_ratio_threshold, 2.0);
    verifyFalse(testCase, config.sigh.compare_methods);
end

function testSessionReferenceUsesSavedRatiosAndInclusiveConfigurableThreshold(testCase)
    [data, features, cycles, config] = sigh_fixture([1; 2; 4; NaN]);
    config.sigh.method = 'session_reference_2x';
    features.lungs.session_reference_value = 2;
    features.lungs.amp_ratio_session = [0.5; 1; 2; NaN];
    before = cycles;
    [events, diagnostics] = detect_sigh(data, features, cycles, config);
    verifyNotEmpty(testCase, events);
    verifyEqual(testCase, diagnostics.lungs.sigh_flags, [false; false; true; false]);
    verifyEqual(testCase, diagnostics.lungs.evaluable_mask, [true; true; true; false]);
    verifyEqual(testCase, diagnostics.lungs.sigh_ratio, features.lungs.amp_ratio_session);
    verifyEqual(testCase, diagnostics.lungs.session_reference_value, 2);
    verifyEqual(testCase, diagnostics.lungs.sigh_baseline, 2 * ones(4, 1));
    verifyEqual(testCase, diagnostics.lungs.decision_threshold, 2);
    verifyFalse(testCase, any(diagnostics.lungs.boundary_extrapolation_mask));
    verifyEqual(testCase, cycles, before);

    config.sigh.session_ratio_threshold = 1;
    [~, diagnostics] = detect_sigh(data, features, cycles, config);
    verifyEqual(testCase, diagnostics.lungs.sigh_flags, [false; true; true; false]);
    verifyEqual(testCase, diagnostics.lungs.decision_threshold, 1);
end

function testSessionReferenceTreatsBeltsIndependentlyAndRetainsQCWarnings(testCase)
    [data, features, cycles, config] = sigh_fixture([1; 2; 4]);
    config.sigh.method = 'session_reference_2x';
    features.diaph = features.lungs;
    features.diaph.session_reference_value = 2;
    features.diaph.amp_ratio_session = features.diaph.amp / 2;
    features.lungs.reference_quality = 'step_candidate';
    features.diaph.reference_quality = 'gradual_or_complex';
    [events, diagnostics] = detect_sigh(data, features, cycles, config);
    verifyEqual(testCase, diagnostics.lungs.sigh_flags, [false; true; true]);
    verifyEqual(testCase, diagnostics.diaph.sigh_flags, [false; false; true]);
    verifyEqual(testCase, diagnostics.lungs.reference_quality, 'step_candidate');
    verifyEqual(testCase, diagnostics.diaph.reference_quality, 'gradual_or_complex');
    verifyTrue(testCase, diagnostics.lungs.available && diagnostics.diaph.available);
    % Keep the existing within-belt merge and separate belt event types.
    verifyNumElements(testCase, events, 2);
    verifyEqual(testCase, sort({events.type}), {'sigh_diaph', 'sigh_lungs'});
    features.diaph.available = false;
    expected = detect_sigh(data, features, cycles, config);
    thoracic = events(strcmp({events.type}, 'sigh_lungs'));
    verifyEqual(testCase, thoracic, expected);
end

function testSessionReferenceNeverFallsBackAndMarksSighUnassessable(testCase)
    [data, features, cycles, config] = sigh_fixture([1; 4; 1]);
    config.sigh.method = 'session_reference_2x';
    config.channels = struct('lungs_idx', 4, 'diaph_idx', 6, 'spo2_idx', 3);
    for reference = [NaN 0 -1 Inf]
        features.lungs.session_reference_value = reference;
        [events, diagnostics] = detect_sigh(data, features, cycles, config);
        verifyEmpty(testCase, events);
        verifyFalse(testCase, diagnostics.available);
        verifyFalse(testCase, any(diagnostics.lungs.evaluable_mask));
        verifyTrue(testCase, all(isnan(diagnostics.lungs.sigh_ratio)));
        verifyEqual(testCase, diagnostics.lungs.status, 'invalid_session_reference');
        mask = compute_label_assessable_mask(data, {'sigh', 'desat'}, ...
            [true true], struct(), [], config, features, struct('sigh', diagnostics));
        verifyFalse(testCase, any(mask(:, 1)));
        verifyTrue(testCase, all(mask(:, 2)));
    end
    features.lungs.session_reference_value = 1;
    features.lungs.session_amplitude_available = false;
    [events, diagnostics] = detect_sigh(data, features, cycles, config);
    verifyEmpty(testCase, events);
    verifyEqual(testCase, diagnostics.lungs.status, 'no_session_reference');
    verifyFalse(testCase, diagnostics.available);
    features.lungs.session_amplitude_available = true;
    features.lungs = rmfield(features.lungs, 'amp_ratio_session');
    [~, diagnostics] = detect_sigh(data, features, cycles, config);
    verifyFalse(testCase, diagnostics.available);
    verifyEqual(testCase, diagnostics.lungs.status, 'missing_session_amplitude_ratio');
end

function testSessionSighUnavailableReasonAndPartialAssessability(testCase)
    config = make_test_config();
    [~, features, cycles, ~] = sigh_fixture([1; NaN; 4]);
    config.sigh.method = 'session_reference_2x';
    N = ceil((features.lungs.peak_t(end) + 2) * config.fs);
    data = ones(N, 6);
    % The unavailable middle breath is not a reviewed or automatic negative.
    [~, diagnostics] = detect_sigh(data, features, cycles, config);
    mask = compute_label_assessable_mask(data, {'sigh', 'desat'}, ...
        [true true], struct(), [], config, features, struct('sigh', diagnostics));
    indices = round(features.lungs.peak_t * config.fs) + 1;
    verifyEqual(testCase, mask(indices, 1), [true; false; true]);
    verifyTrue(testCase, all(mask(:, 2)));

    features.lungs.session_amplitude_available = false;
    [~, diagnostics] = detect_sigh(data, features, cycles, config);
    features.lungs.rate_slow_window_bpm = [];
    features.diaph.rate_slow_window_bpm = [];
    features.lungs.rate_rapid_window_bpm = [];
    features.diaph.rate_rapid_window_bpm = [];
    features.lungs.irregularity.cov = [];
    features.diaph.irregularity.cov = [];
    [available, reason] = compute_label_availability({'sigh'}, features, ...
        struct(), struct(), struct(), diagnostics, struct());
    verifyFalse(testCase, available);
    verifyEqual(testCase, reason, {'no_session_reference'});
end

function testSessionArtifactsDoNotExpandIntoRollingBaselineWindow(testCase)
    amplitude = ones(35, 1);
    amplitude([10 18 26]) = 4;
    [data, features, cycles, config] = sigh_fixture(amplitude);
    config.sigh.method = 'session_reference_2x';
    config.sigh.compare_methods = true;
    features.diaph = features.lungs;
    bad_sample = round(features.lungs.peak_t(18) * config.fs) + 1;
    features.lungs.artifact_intervals_idx = [bad_sample bad_sample];
    features.diaph.artifact_intervals_idx = [bad_sample bad_sample];
    [~, fixed] = detect_sigh(data, features, cycles, config);
    config.channels = struct('lungs_idx', 4, 'diaph_idx', 6, 'spo2_idx', 3);
    features.respiratory_artifact_state = struct( ...
        'artifact_intervals_idx', [bad_sample bad_sample]);
    mask = compute_label_assessable_mask(data, {'sigh', 'desat'}, [true true], ...
        struct(), [], config, features, struct('sigh', fixed));
    verifyFalse(testCase, mask(bad_sample, 1));
    nearby = round(features.lungs.peak_t([17 19]) * config.fs) + 1;
    verifyTrue(testCase, all(mask(nearby, 1)));
    verifyTrue(testCase, all(mask(:, 2)));
    config.sigh.method = 'rolling_median_2x';
    [~, rolling] = detect_sigh(data, features, cycles, config);
    for name = {'lungs', 'diaph'}
        key = name{1};
        verifyFalse(testCase, fixed.(key).evaluable_mask(18));
        verifyFalse(testCase, fixed.(key).sigh_flags(18));
        verifyTrue(testCase, all(fixed.(key).evaluable_mask([17 19])));
        verifyFalse(testCase, any(rolling.(key).evaluable_mask(11:25)));
        verifyEqual(testCase, fixed.comparison.(key).both_count, 2);
        verifyEqual(testCase, fixed.comparison.(key).session_reference_2x_count, 2);
        verifyEqual(testCase, fixed.comparison.(key).rolling_median_2x_count, 2);
        verifyEqual(testCase, fixed.comparison.(key).valid_breath_count, 20);
    end
end

function testSessionComparisonReportsCountDifferencesAndOverlap(testCase)
    [data, features, cycles, config] = sigh_fixture([ones(12, 1); 3; ones(12, 1)]);
    config.sigh.method = 'session_reference_2x';
    config.sigh.compare_methods = true;
    features.lungs.session_reference_value = 2;
    features.lungs.amp_ratio_session = features.lungs.amp / 2;
    [~, diagnostics] = detect_sigh(data, features, cycles, config);
    verifyEqual(testCase, diagnostics.comparison.lungs.session_reference_2x_count, 0);
    verifyEqual(testCase, diagnostics.comparison.lungs.rolling_median_2x_count, 1);
    verifyEqual(testCase, diagnostics.comparison.lungs.both_count, 0);
    verifyEqual(testCase, diagnostics.comparison.lungs.rolling_median_2x_only_count, 1);
    verifyEqual(testCase, diagnostics.comparison.total.valid_breath_count, 25);
end

function testSessionThresholdAndRatioAlignmentValidation(testCase)
    [data, features, cycles, config] = sigh_fixture(ones(3, 1));
    config.sigh.method = 'session_reference_2x';
    config.sigh.session_ratio_threshold = 0;
    verifyError(testCase, @() detect_sigh(data, features, cycles, config), ...
        'MAGMA:Sigh:InvalidSessionThreshold');
    config.sigh.session_ratio_threshold = 2;
    features.lungs.amp_ratio_session(end) = [];
    verifyError(testCase, @() detect_sigh(data, features, cycles, config), ...
        'MAGMA:Sigh:BreathAlignmentMismatch');
end

function testSessionDiagnosticPlotShowsSelectedMethodRatiosAndThreshold(testCase)
    output_dir = tempname;
    mkdir(output_dir);
    cleanup_dir = onCleanup(@() rmdir(output_dir, 's')); %#ok<NASGU>
    [data, features, cycles, config] = sigh_fixture([1; 2; 4]);
    config.sigh.method = 'session_reference_2x';
    config.sigh.do_plot = true;
    config.sigh.compare_methods = true;
    config.sub_results_path = output_dir;
    config.plot_format = 'fig';
    config.channels = struct('lungs_idx', 4, 'diaph_idx', 6, 'spo2_idx', 3);
    existing_figures = findall(groot, 'Type', 'figure');
    cleanup = onCleanup(@() close_new_figures(existing_figures)); %#ok<NASGU>
    detect_sigh(data, features, cycles, config);
    saved_figure = openfig(fullfile(output_dir, 'Sub999_M1_sigh.fig'), 'invisible');
    saved_figure.Visible = 'off';
    axes_handles = findall(saved_figure, 'Type', 'axes');
    ratio_axes = axes_handles(arrayfun(@(ax) ...
        strcmp(ax.YLabel.String, 'Amplitude / session reference'), axes_handles));
    verifyNumElements(testCase, ratio_axes, 2);
    for ax = ratio_axes(:)'
        verifyTrue(testCase, contains(ax.Title.String, 'session_reference_2x'));
    end
    lines = findall(ratio_axes, 'Type', 'constantline');
    verifyTrue(testCase, any(arrayfun(@(line) line.Value == 2, lines)));
end

function testCanonicalAmplitudeIgnoresContradictoryAuxiliaryFields(testCase)
    amplitude = ones(25, 1);
    amplitude(13) = 2.2;
    [data, features, cycles, config] = sigh_fixture(amplitude);
    config.sigh.compare_methods = true;
    contradictory_cycles = cycles;
    contradictory_cycles.lungs.amp_exp = 1000 * (1:25)';
    contradictory_cycles.lungs.amp_insp = ...
        flipud(contradictory_cycles.lungs.amp_exp);
    contradictory_cycles.lungs.amp_sym = ...
        -contradictory_cycles.lungs.amp_exp;
    no_aux_cycles = contradictory_cycles;
    no_aux_cycles.lungs = rmfield(no_aux_cycles.lungs, ...
        {'amp_exp', 'amp_insp', 'amp_sym'});
    methods = {'session_reference_2x', 'rolling_median_2x', 'global_ratio_outlier', 'legacy_60s'};

    for i = 1:numel(methods)
        config.sigh.method = methods{i};
        [expected_events, expected_diagnostics] = ...
            detect_sigh(data, features, cycles, config);
        [actual_events, actual_diagnostics] = ...
            detect_sigh(data, features, contradictory_cycles, config);
        [no_aux_events, no_aux_diagnostics] = ...
            detect_sigh(data, features, no_aux_cycles, config);

        verifyEqual(testCase, actual_events, expected_events);
        verifyEqual(testCase, actual_diagnostics.lungs.sigh_flags, ...
            expected_diagnostics.lungs.sigh_flags);
        verifyEqual(testCase, actual_diagnostics.lungs.sigh_amplitude, ...
            expected_diagnostics.lungs.sigh_amplitude);
        verifyEqual(testCase, actual_diagnostics.lungs.sigh_baseline, ...
            expected_diagnostics.lungs.sigh_baseline);
        verifyEqual(testCase, actual_diagnostics.lungs.sigh_ratio, ...
            expected_diagnostics.lungs.sigh_ratio);
        verifyEqual(testCase, actual_diagnostics.comparison, ...
            expected_diagnostics.comparison);
        verifyEqual(testCase, no_aux_events, expected_events);
        verifyEqual(testCase, no_aux_diagnostics.lungs.sigh_flags, ...
            expected_diagnostics.lungs.sigh_flags);
        verifyEqual(testCase, no_aux_diagnostics.lungs.sigh_ratio, ...
            expected_diagnostics.lungs.sigh_ratio);
    end
end

function testEveryMethodUsesEachConfiguredCanonicalAmplitude(testCase)
    methods = {'expiratory', 'inspiratory', 'symmetric'};
    sigh_methods = {'session_reference_2x', 'rolling_median_2x', 'global_ratio_outlier', 'legacy_60s'};
    [signal, peak_idx] = synthetic_reviewed_breaths(25);
    expected_peak_idx = peak_idx;
    expected_trough_idx = [];

    for i = 1:numel(methods)
        breath_config = struct('fs', 1, 'resp', struct( ...
            'trough_method', 'min', 'trough_prct', 5, ...
            'amp_method', methods{i}));
        breath = recompute_respiration_breath_fields( ...
            struct(), signal, peak_idx, breath_config);
        if isempty(expected_trough_idx)
            expected_trough_idx = breath.trough_idx;
        end
        verifyEqual(testCase, breath.peak_idx, expected_peak_idx);
        verifyEqual(testCase, breath.trough_idx, expected_trough_idx);
        verifyEqual(testCase, breath.amp, breath.(amplitude_field(methods{i})));

        [data, features, cycles, config] = sigh_fixture(breath.amp);
        config.resp.amp_method = methods{i};
        cycles.lungs = breath;
        for j = 1:numel(sigh_methods)
            config.sigh.method = sigh_methods{j};
            [~, diagnostics] = detect_sigh(data, features, cycles, config);
            verifyEqual(testCase, diagnostics.lungs.sigh_amplitude, ...
                breath.amp);
            verifyEqual(testCase, diagnostics.lungs.amplitude_method, ...
                methods{i});
        end
    end
end

function testCompleteCenteredBoundaryMedians(testCase)
    amplitude = (1:29)';
    [~, diagnostics] = run_rolling(amplitude, 15);
    expected = [(8 * ones(7, 1)); (8:22)'; (22 * ones(7, 1))];

    verifyEqual(testCase, diagnostics.lungs.sigh_baseline, expected);
    verifyEqual(testCase, diagnostics.lungs.boundary_extrapolation_mask, ...
        [true(7, 1); false(15, 1); true(7, 1)]);
    verifyEqual(testCase, diagnostics.lungs.boundary_convention, ...
        'complete_centered_windows_constant_edge_extension');
end

function testExactlyOneCompleteWindowExtendsOneMedianEverywhere(testCase)
    amplitude = [1; 4; 2; 7; 5; 3; 6; 8; 10; 9; 11; 12; 13; 14; 15];
    [~, diagnostics] = run_rolling(amplitude, 15);

    verifyEqual(testCase, diagnostics.lungs.sigh_baseline, ...
        repmat(median(amplitude), 15, 1));
    verifyTrue(testCase, diagnostics.lungs.available);
    verifyEqual(testCase, diagnostics.lungs.status, 'available');
end

function testShortEmptyAndUnusableSequencesAreUnavailable(testCase)
    [events, diagnostics] = run_rolling(ones(14, 1), 3);
    verifyEmpty(testCase, events);
    verifyFalse(testCase, diagnostics.lungs.available);
    verifyEqual(testCase, diagnostics.lungs.status, ...
        'insufficient_breath_positions');
    verifyTrue(testCase, all(isnan(diagnostics.lungs.sigh_baseline)));
    verifyTrue(testCase, all(isnan(diagnostics.lungs.sigh_ratio)));
    verifyFalse(testCase, any(diagnostics.lungs.sigh_flags));

    [events, diagnostics] = run_rolling(zeros(0, 1), 3);
    verifyEmpty(testCase, events);
    verifyEqual(testCase, diagnostics.lungs.status, 'no_breaths');
    verifyFalse(testCase, diagnostics.lungs.available);

    [~, diagnostics] = run_rolling(nan(20, 1), 3);
    verifyEqual(testCase, diagnostics.lungs.status, ...
        'insufficient_valid_amplitudes');
    verifyTrue(testCase, all(isnan(diagnostics.lungs.sigh_baseline)));
    verifyTrue(testCase, all(isnan(diagnostics.lungs.sigh_ratio)));
    verifyFalse(testCase, any(diagnostics.lungs.evaluable_mask));

    sparse = nan(20, 1);
    sparse([1 10]) = 1;
    [~, diagnostics] = run_rolling(sparse, 3);
    verifyFalse(testCase, diagnostics.lungs.available);
    verifyTrue(testCase, all(isnan(diagnostics.lungs.sigh_baseline)));
end

function testMissingOrZeroBeltUsesAlignedCanonicalEmptyVectors(testCase)
    config = minimal_sigh_config();
    zero_signal = zeros(100, 1);
    missing_signal = nan(100, 1);

    zero_belt = extract_respiration_feature( ...
        zero_signal, config, 'Resp-Lungs');
    missing_belt = extract_respiration_feature( ...
        missing_signal, config, 'Resp-Lungs');

    verifyEqual(testCase, zero_belt.x0, zero_signal);
    verifyEqual(testCase, missing_belt.x0, missing_signal);
    verifyEmpty(testCase, zero_belt.peak_t);
    verifyEmpty(testCase, zero_belt.amp);
    verifyEmpty(testCase, missing_belt.peak_t);
    verifyEmpty(testCase, missing_belt.amp);
end

function testMissingLungsUsesValidDiaphragmWithoutAlignmentError(testCase)
    amplitude = ones(25, 1);
    amplitude(13) = 4;
    [data, features, cycles, config] = sigh_fixture(amplitude);
    features.diaph = features.lungs;
    features.lungs = struct( ...
        'available', false, ...
        'ignored', true, ...
        'peak_t', zeros(0, 1), ...
        'amp', NaN, ...
        'global_amplitude_available', false, ...
        'reference_quality', 'belt_unavailable');

    [events, diagnostics] = detect_sigh( ...
        data, features, cycles, config);

    verifyEqual(testCase, diagnostics.lungs.status, 'belt_ignored');
    verifyFalse(testCase, diagnostics.lungs.available);
    verifyEmpty(testCase, diagnostics.lungs.sigh_flags);
    verifyTrue(testCase, diagnostics.diaph.available);
    verifyTrue(testCase, diagnostics.diaph.sigh_flags(13));
    verifyNotEmpty(testCase, events);
end

function testPlotLegendAcceptsConstantLineThreshold(testCase)
    output_dir = tempname;
    mkdir(output_dir);
    cleanup_dir = onCleanup(@() rmdir(output_dir, 's'));
    amplitude = ones(25, 1);
    amplitude(13) = 4;
    [data, features, cycles, config] = sigh_fixture(amplitude);
    config.sigh.do_plot = true;
    config.channels = struct( ...
        'lungs_idx', 4, 'diaph_idx', 6, 'spo2_idx', 3);
    config.sub_results_path = output_dir;

    detect_sigh(data, features, cycles, config);

    verifyTrue(testCase, isfile(fullfile(output_dir, ...
        'Sub999_M1_sigh.png')));
end

function testInternalUndefinedBaselinesAreNotFilled(testCase)
    amplitude = ones(45, 1);
    amplitude(23) = NaN;
    [~, diagnostics] = run_rolling(amplitude, 15);
    baseline = diagnostics.lungs.sigh_baseline;

    verifyEqual(testCase, baseline(1:15), ones(15, 1));
    verifyTrue(testCase, all(isnan(baseline(16:30))));
    verifyEqual(testCase, baseline(31:45), ones(15, 1));
    verifyTrue(testCase, all(isnan(diagnostics.lungs.sigh_ratio(16:30))));
    verifyEqual(testCase, ...
        find(diagnostics.lungs.boundary_extrapolation_mask), ...
        [1:7 39:45]');
end

function testUndefinedFirstAndLastCompleteBaselinesStayAtEdges(testCase)
    amplitude = ones(30, 1);
    amplitude([1 end]) = NaN;
    [~, diagnostics] = run_rolling(amplitude, 15);
    baseline = diagnostics.lungs.sigh_baseline;

    verifyTrue(testCase, all(isnan(baseline(1:8))));
    verifyEqual(testCase, baseline(9), 1);
    verifyEqual(testCase, baseline(22), 1);
    verifyTrue(testCase, all(isnan(baseline(23:30))));
end

function testInvalidTargetAndInclusiveThreshold(testCase)
    amplitude = ones(21, 1);
    amplitude(11) = 2;
    amplitude(5) = NaN;
    [~, diagnostics] = run_rolling(amplitude, 3);

    verifyTrue(testCase, diagnostics.lungs.sigh_flags(11));
    verifyEqual(testCase, diagnostics.lungs.sigh_ratio(11), 2);
    verifyFalse(testCase, diagnostics.lungs.evaluable_mask(5));
    verifyTrue(testCase, isnan(diagnostics.lungs.sigh_ratio(5)));
end

function testComparisonExcludesUnevaluableRollingBreaths(testCase)
    amplitude = ones(14, 1);
    [data, features, cycles, config] = sigh_fixture(amplitude);
    config.sigh.compare_methods = true;
    [~, diagnostics] = detect_sigh(data, features, cycles, config);

    verifyFalse(testCase, diagnostics.comparison.lungs.available);
    verifyEqual(testCase, ...
        diagnostics.comparison.lungs.valid_breath_count, 0);
    verifyEqual(testCase, ...
        diagnostics.comparison.lungs.agreement_count, 0);
end

function testAlignmentMismatchRaisesClearError(testCase)
    [data, features, cycles, config] = sigh_fixture(ones(20, 1));
    features.lungs.amp(end) = [];
    verifyError(testCase, ...
        @() detect_sigh(data, features, cycles, config), ...
        'MAGMA:Sigh:BreathAlignmentMismatch');
end

function testStaleGlobalRatioRaisesClearError(testCase)
    [data, features, cycles, config] = sigh_fixture(ones(20, 1));
    features.lungs.amp(10) = 2;
    config.sigh.method = 'global_ratio_outlier';
    verifyError(testCase, ...
        @() detect_sigh(data, features, cycles, config), ...
        'MAGMA:Sigh:StaleGlobalRatio');
end

function testRatioPlotHandlesValidEvidenceWithZeroDetectedSighs(testCase)
    output_dir = tempname;
    mkdir(output_dir);
    cleanup_dir = onCleanup(@() rmdir(output_dir, 's')); %#ok<NASGU>
    [data, features, cycles, config] = sigh_fixture(ones(25, 1));
    config.sub_results_path = output_dir;
    config.sigh.do_plot = true;
    config.sigh.compare_methods = true;
    config.channels = struct( ...
        'lungs_idx', 1, 'diaph_idx', [], 'spo2_idx', []);
    existing_figures = findall(groot, 'Type', 'figure');
    cleanup = onCleanup(@() close_new_figures(existing_figures)); %#ok<NASGU>

    [events, diagnostics] = detect_sigh( ...
        data, features, cycles, config);

    verifyTrue(testCase, diagnostics.lungs.available);
    verifyTrue(testCase, any(isfinite(diagnostics.lungs.sigh_ratio)));
    verifyFalse(testCase, any(diagnostics.lungs.sigh_flags));
    verifyEqual(testCase, ...
        diagnostics.comparison.lungs.rolling_median_2x_count, 0);
    verifyEqual(testCase, ...
        diagnostics.comparison.lungs.session_reference_2x_count, 0);
    verifyEmpty(testCase, events);
end

function testGlobalRatioOutlierMatchesFrozenPreviousImplementation(testCase)
    amplitude = ones(25, 1);
    amplitude(13) = 4;
    [data, features, cycles, config] = sigh_fixture(amplitude);
    config.sigh.method = 'global_ratio_outlier';
    expected = frozen_global_ratio_outlier( ...
        features.lungs, config.sigh.ratio_prctile, ...
        config.sigh.min_abs_ratio, config.sigh.iqr_k, ...
        config.sigh.min_gap_sec);

    [~, diagnostics] = detect_sigh(data, features, cycles, config);

    verifyEqual(testCase, diagnostics.lungs.sigh_flags, expected);
    verifyEqual(testCase, diagnostics.sigh_method, 'global_ratio_outlier');
end

function testLegacy60sMatchesFrozenAndReportsLocalBaseline(testCase)
    amplitude = ones(25, 1);
    amplitude(18) = 2;
    [data, features, cycles, config] = sigh_fixture(amplitude);
    config.sigh.method = 'legacy_60s';
    expected = frozen_legacy_60s(features.lungs, ...
        config.sigh.legacy_prev_win_sec, ...
        config.sigh.legacy_amp_ratio_thr, ...
        config.sigh.legacy_min_prev_breaths);

    [~, diagnostics] = detect_sigh(data, features, cycles, config);

    verifyEqual(testCase, diagnostics.lungs.sigh_flags, expected);
    verifyEqual(testCase, diagnostics.lungs.sigh_baseline(18), 1);
    verifyEqual(testCase, diagnostics.lungs.sigh_ratio(18), 2);
    verifyTrue(testCase, diagnostics.lungs.evaluable_mask(18));
end

function [events, diagnostics] = run_rolling(amplitude, min_valid)
    [data, features, cycles, config] = sigh_fixture(amplitude);
    config.sigh.rolling_min_valid_breaths = min_valid;
    [events, diagnostics] = detect_sigh(data, features, cycles, config);
end

function [data, features, cycles, config] = sigh_fixture(amplitude)
    amplitude = amplitude(:);
    n_breaths = numel(amplitude);
    peak_t = 2 + 4 * (0:n_breaths - 1)';
    config = minimal_sigh_config();
    n_samples = max(100, round((max([0; peak_t]) + 2) * config.fs));
    data = zeros(n_samples, 6);

    lungs = struct( ...
        'available', true, ...
        'ignored', false, ...
        'peak_t', peak_t, ...
        'amp', amplitude, ...
        'amp_ratio_session', amplitude, ...
        'session_reference_value', 1, ...
        'session_amplitude_available', true, ...
        'amp_ratio_global', amplitude, ...
        'global_reference_value', 1, ...
        'global_amplitude_available', true, ...
        'reference_quality', 'good');
    diaph = struct( ...
        'available', false, ...
        'ignored', false, ...
        'peak_t', zeros(0, 1), ...
        'amp', zeros(0, 1), ...
        'amp_ratio_session', zeros(0, 1), ...
        'session_reference_value', NaN, ...
        'session_amplitude_available', false, ...
        'amp_ratio_global', zeros(0, 1), ...
        'global_reference_value', NaN, ...
        'global_amplitude_available', false, ...
        'reference_quality', 'belt_unavailable');
    features = struct('lungs', lungs, 'diaph', diaph);

    cycle_lungs = struct( ...
        'ok', true, ...
        'peak_t', peak_t, ...
        'amp', amplitude, ...
        'amp_exp', 10 * ones(n_breaths, 1), ...
        'amp_insp', 20 * ones(n_breaths, 1), ...
        'amp_sym', 30 * ones(n_breaths, 1));
    cycles = struct( ...
        'lungs', cycle_lungs, ...
        'diaph', empty_respiration_feature('Resp-Diaphragm'));
end

function config = minimal_sigh_config()
    config = struct();
    config.fs = 10;
    config.subject = 999;
    config.measure = 1;
    config.make_figs_visible = 'off';
    config.execution = struct('mode', 'analyze');
    config.resp = struct('amp_method', 'expiratory');
    config.sigh = struct( ...
        'method', 'rolling_median_2x', ...
        'session_ratio_threshold', 2, ...
        'rolling_window_breaths', 15, ...
        'rolling_min_valid_breaths', 3, ...
        'rolling_ratio_threshold', 2, ...
        'compare_methods', false, ...
        'ratio_prctile', 98, ...
        'min_abs_ratio', 2, ...
        'iqr_k', 3.5, ...
        'min_gap_sec', 2, ...
        'do_plot', false, ...
        'legacy_prev_win_sec', 60, ...
        'legacy_amp_ratio_thr', 1.5, ...
        'legacy_min_prev_breaths', 3);
end

function close_new_figures(existing_figures)
% CLOSE_NEW_FIGURES Clean up figures created by plotting regression tests.

    current_figures = findall(groot, 'Type', 'figure');
    for i = 1:numel(current_figures)
        if ~any(current_figures(i) == existing_figures)
            close(current_figures(i));
        end
    end
end

function [signal, peak_idx] = synthetic_reviewed_breaths(n_breaths)
    peak_idx = (2:4:(2 + 4 * (n_breaths - 1)))';
    signal = zeros(peak_idx(end) + 2, 1);
    signal(peak_idx) = 3 + 0.25 * sin((1:n_breaths)');
    for i = 1:(n_breaths - 1)
        signal(peak_idx(i) + 2) = -0.2 * mod(i, 3);
    end
end

function field = amplitude_field(method)
    switch method
        case 'expiratory'
            field = 'amp_exp';
        case 'inspiratory'
            field = 'amp_insp';
        case 'symmetric'
            field = 'amp_sym';
    end
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
