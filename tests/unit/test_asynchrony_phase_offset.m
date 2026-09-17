function tests = test_asynchrony_phase_offset
% Focused tests for complementary respiratory wavelet phase offset.

    tests = functiontests(localfunctions);
end

function testKnownStablePhaseOffsets(testCase)
    angles = [0 30 90 180];
    tolerance_deg = 2;
    for angle_deg = angles
        [data, config] = phase_fixture(angle_deg, 1);
        metrics = compute_respiratory_phase_offset_metrics(data, [], config);
        observed = median(metrics.absolute_mean_phase_deg, 'omitnan');

        verifyTrue(testCase, metrics.available, metrics.availability_reason);
        verifyEqual(testCase, observed, angle_deg, ...
            'AbsTol', tolerance_deg);
        verifyGreaterThan(testCase, ...
            median(metrics.resultant_length, 'omitnan'), 0.98);
        verifyEqual(testCase, ...
            median(metrics.selected_resp_frequency_hz, 'omitnan'), ...
            0.25, 'AbsTol', 0.02);
    end
end

function testCircularMeanWrapsAtOneHundredEightyDegrees(testCase)
    [mean_phase, resultant] = circular_phase_summary( ...
        deg2rad([179 -179]));

    verifyEqual(testCase, abs(rad2deg(mean_phase)), 180, 'AbsTol', 0.01);
    verifyGreaterThan(testCase, resultant, 0.99);
end

function testStableOppositionIsDetectedWithoutAutomaticInversion(testCase)
    [data, config] = phase_fixture(180, 1);
    missing_reference = struct('available', false);
    [events, diagnostics] = detect_respiratory_asynchrony( ...
        data, missing_reference, [], config);
    phase = diagnostics.methods.wavelet_phase_offset;

    verifyNotEmpty(testCase, events);
    verifyEqual(testCase, diagnostics.primary_method, ...
        'wavelet_phase_offset');
    verifyTrue(testCase, diagnostics.primary_available);
    verifyEqual(testCase, median(phase.absolute_mean_phase_deg, 'omitnan'), ...
        180, 'AbsTol', 2);
    verifyGreaterThan(testCase, median(phase.resultant_length, 'omitnan'), 0.98);
    verifyEqual(testCase, phase.polarity_convention, ...
        ['configured_fixed_multipliers_thoracic_minus_abdominal_' ...
         'no_automatic_optimization']);
    verifyEqual(testCase, phase.reference_normalization, 'none');
    verifyEqual(testCase, phase.provenance.polarity_convention, ...
        phase.polarity_convention);
end

function testAmplitudeScalingDoesNotChangePhase(testCase)
    [data, config] = phase_fixture(90, 1);
    scaled = data;
    scaled(:, 1) = 7 * scaled(:, 1);
    scaled(:, 2) = 0.2 * scaled(:, 2);
    original = compute_respiratory_phase_offset_metrics(data, [], config);
    transformed = compute_respiratory_phase_offset_metrics(scaled, [], config);

    verifyEqual(testCase, ...
        median(transformed.absolute_mean_phase_deg, 'omitnan'), ...
        median(original.absolute_mean_phase_deg, 'omitnan'), ...
        'AbsTol', 0.1);
    verifyEqual(testCase, ...
        median(transformed.resultant_length, 'omitnan'), ...
        median(original.resultant_length, 'omitnan'), ...
        'AbsTol', 0.01);
end

function testFlatSegmentsAreUnevaluable(testCase)
    [data, config, time_sec] = phase_fixture(90, 1);
    flat = time_sec >= 45 & time_sec < 75;
    data(flat, :) = 0;
    metrics = compute_respiratory_phase_offset_metrics(data, [], config);
    central = metrics.time_sec >= 55 & metrics.time_sec < 65;

    verifyFalse(testCase, any(metrics.valid_phase_mask(central)));
    verifyFalse(testCase, any(metrics.reliable_phase_mask(central)));
    verifyTrue(testCase, all(isnan( ...
        metrics.absolute_mean_phase_deg(central))));
end

function testMissingBeltMakesPhaseMethodUnavailable(testCase)
    [data, config] = phase_fixture(90, 1);
    config.channels.diaph_idx = [];
    metrics = compute_respiratory_phase_offset_metrics(data(:, 1), [], config);

    verifyFalse(testCase, metrics.available);
    verifyEqual(testCase, metrics.availability_reason, ...
        'missing_respiratory_belt_channel');
end

function testMissingReferenceDoesNotBlockPhasePrimary(testCase)
    [data, config] = phase_fixture(90, 1);
    reference = struct('available', false);
    [events, diagnostics] = detect_respiratory_asynchrony( ...
        data, reference, [], config);

    verifyTrue(testCase, diagnostics.primary_available);
    verifyNotEmpty(testCase, events);
    verifyFalse(testCase, diagnostics.methods.wavelet_coherence_drop.available);
    verifyTrue(testCase, diagnostics.methods.wavelet_phase_offset.available);
    verifyFalse(testCase, diagnostics.comparison.available);
    verifyEqual(testCase, diagnostics.comparison.jointly_assessable_sec, 0);
    verifyTrue(testCase, isnan(diagnostics.comparison.agreement_fraction));
end

function testSelectedPhaseAvailabilityAndAssessabilityPropagate(testCase)
    [data, config] = phase_fixture(90, 1);
    [~, diagnostics] = detect_respiratory_asynchrony( ...
        data, struct('available', false), [], config);
    resp_features = minimal_resp_features();
    [available, reason] = compute_label_availability( ...
        {'async'}, resp_features, struct(), diagnostics, ...
        struct(), struct(), struct());
    [assessable, info] = compute_label_assessable_mask( ...
        data, {'async'}, available, diagnostics, ...
        diagnostics.methods.wavelet_phase_offset.time_sec, config);

    verifyTrue(testCase, available);
    verifyEqual(testCase, reason, {'available'});
    verifyTrue(testCase, any(assessable));
    verifyFalse(testCase, all(assessable));
    verifyEqual(testCase, info.version, 'label_assessability_v2');
end

function testUnavailableSelectedMethodDoesNotFallBack(testCase)
    [data, config] = phase_fixture(20, 1);
    config.async.phase_offset.min_magnitude_fraction = 1e6;
    reference = struct( ...
        'available', true, ...
        'complete', true, ...
        'reference_start_t', 0, ...
        'reference_end_t', 120);

    [events, diagnostics] = detect_respiratory_asynchrony( ...
        data, reference, [], config);

    verifyTrue(testCase, ...
        diagnostics.methods.wavelet_coherence_drop.available);
    verifyFalse(testCase, ...
        diagnostics.methods.wavelet_phase_offset.available);
    verifyFalse(testCase, diagnostics.primary_available);
    verifyEmpty(testCase, events);
end

function testLegacyCoherencePayloadAndEventsRemainUnchanged(testCase)
    [data, config] = phase_fixture(20, 1);
    config.async = rmfield(config.async, ...
        {'primary_method', 'compare_methods'});
    reference = struct( ...
        'available', true, ...
        'complete', true, ...
        'reference_start_t', 0, ...
        'reference_end_t', 120);
    legacy = compute_respiratory_asynchrony_metrics( ...
        data, [], reference, config);
    [expected_events, ~] = sustained_condition_to_events( ...
        legacy.low_coherence_mask, legacy.time_sec, config.fs, ...
        size(data, 1), legacy.min_dur_sec, 'respiratory_asynchrony');
    [actual_events, diagnostics] = detect_respiratory_asynchrony( ...
        data, reference, [], config);

    verifyEqual(testCase, actual_events, expected_events);
    verifyEqual(testCase, diagnostics.valid_analysis, legacy.valid_analysis);
    verifyEqual(testCase, diagnostics.phase_coherence_high, ...
        legacy.phase_coherence_high);
    verifyEqual(testCase, diagnostics.phase_coherence_mid, ...
        legacy.phase_coherence_mid);
    verifyEqual(testCase, diagnostics.phase_coherence_low, ...
        legacy.phase_coherence_low);
    verifyEqual(testCase, diagnostics.low_coherence_mask, ...
        legacy.low_coherence_mask);
    verifyEqual(testCase, diagnostics.thresholds, legacy.thresholds);
    verifyEqual(testCase, diagnostics.primary_method, ...
        'wavelet_coherence_drop');
end

function testBreathGuidedFrequencyTracksKnownFundamentals(testCase)
    frequencies = [0.10 0.15 0.25 0.40];
    for frequency = frequencies
        duration_sec = max(180, 18 / frequency);
        [data, config] = frequency_fixture(frequency, 45, duration_sec);
        cycles = reviewed_cycles(frequency, duration_sec, true, true);
        metrics = compute_respiratory_phase_offset_metrics( ...
            data, cycles, config);
        valid = metrics.valid_phase_mask;

        verifyTrue(testCase, metrics.available, metrics.availability_reason);
        verifyEqual(testCase, metrics.frequency_min_hz, 0.052);
        verifyEqual(testCase, median( ...
            metrics.expected_resp_frequency_hz(valid), 'omitnan'), ...
            frequency, 'AbsTol', 1e-12);
        verifyEqual(testCase, median( ...
            metrics.selected_resp_frequency_hz(valid), 'omitnan'), ...
            frequency, 'AbsTol', 0.02);
        modes = metrics.frequency_selection_mode(valid);
        verifyGreaterThan(testCase, mean(strcmp( ...
            modes, 'breath_timing_guided')), 0.75);
        verifyTrue(testCase, all( ...
            metrics.frequency_consistent_with_breath_timing(valid) == 1));
    end
end

function testBreathGuidanceRejectsStrongerSecondHarmonic(testCase)
    frequency = 0.20;
    duration_sec = 200;
    [~, config, time_sec] = frequency_fixture( ...
        frequency, 0, duration_sec);
    waveform = sin(2 * pi * frequency * time_sec) + ...
        2.5 * sin(2 * pi * 2 * frequency * time_sec);
    data = [waveform waveform];
    cycles = reviewed_cycles(frequency, duration_sec, true, true);

    guided = compute_respiratory_phase_offset_metrics(data, cycles, config);
    fallback = compute_respiratory_phase_offset_metrics(data, [], config);
    guided_valid = guided.valid_phase_mask;
    fallback_valid = fallback.valid_phase_mask;

    verifyEqual(testCase, median( ...
        guided.selected_resp_frequency_hz(guided_valid), 'omitnan'), ...
        frequency, 'AbsTol', 0.03);
    verifyGreaterThan(testCase, mean(strcmp( ...
        guided.frequency_selection_mode(guided_valid), ...
        'breath_timing_guided')), 0.75);
    verifyEqual(testCase, median( ...
        fallback.selected_resp_frequency_hz(fallback_valid), 'omitnan'), ...
        2 * frequency, 'AbsTol', 0.04);
    verifyTrue(testCase, all(strcmp( ...
        fallback.frequency_selection_mode(fallback_valid), ...
        'joint_wavelet_magnitude_fallback')));
    verifyTrue(testCase, all(isnan( ...
        fallback.expected_resp_frequency_hz(fallback_valid))));
end

function testSingleBeltTimingCanGuideTwoUsableRawBelts(testCase)
    frequency = 0.15;
    duration_sec = 180;
    [data, config] = frequency_fixture(frequency, 30, duration_sec);
    cycles = reviewed_cycles(frequency, duration_sec, true, false);
    metrics = compute_respiratory_phase_offset_metrics(data, cycles, config);
    valid = metrics.valid_phase_mask;

    verifyTrue(testCase, metrics.available);
    verifyTrue(testCase, metrics.breath_timing_available_lungs);
    verifyFalse(testCase, metrics.breath_timing_available_diaph);
    verifyEqual(testCase, median( ...
        metrics.expected_resp_frequency_hz(valid), 'omitnan'), ...
        frequency, 'AbsTol', 1e-12);
    verifyGreaterThan(testCase, mean(strcmp( ...
        metrics.frequency_selection_mode(valid), ...
        'breath_timing_guided')), 0.75);
end

function testFixedPolarityMultipliersAreAppliedWithoutOptimization(testCase)
    [data, config] = frequency_fixture(0.25, 0, 160);
    recorded = compute_respiratory_phase_offset_metrics(data, [], config);
    config.async.phase_offset.diaph_polarity_multiplier = -1;
    corrected = compute_respiratory_phase_offset_metrics(data, [], config);

    verifyLessThan(testCase, median( ...
        recorded.absolute_mean_phase_deg, 'omitnan'), 2);
    verifyEqual(testCase, recorded.lungs_polarity_multiplier, 1);
    verifyEqual(testCase, recorded.diaph_polarity_multiplier, 1);
    verifyEqual(testCase, recorded.polarity_source, ...
        'recorded_channel_polarity');
    verifyEqual(testCase, median( ...
        corrected.absolute_mean_phase_deg, 'omitnan'), 180, 'AbsTol', 2);
    verifyEqual(testCase, corrected.lungs_polarity_multiplier, 1);
    verifyEqual(testCase, corrected.diaph_polarity_multiplier, -1);
    verifyEqual(testCase, corrected.provenance.diaph_polarity_multiplier, -1);
    verifyEqual(testCase, corrected.polarity_source, ...
        'user_configured_fixed_hardware_correction');
    verifyEqual(testCase, config.async.phase_offset.diaph_polarity_multiplier, -1);
    verifyGreaterThan(testCase, ...
        corrected.cohort_qc.fraction_reliable_near_180deg, 0.95);
end

function testInvalidPolarityMultiplierIsRejected(testCase)
    [data, config] = frequency_fixture(0.25, 0, 120);
    config.async.phase_offset.diaph_polarity_multiplier = 0;

    verifyError(testCase, @() compute_respiratory_phase_offset_metrics( ...
        data, [], config), 'MAGMA:RespiratoryPhaseOffset:InvalidSetting');
end

function testCentralGapExcludesEdgesAndSeparatesEvents(testCase)
    duration_sec = 300;
    frequency = 0.25;
    [data, config, time_sec] = frequency_fixture( ...
        frequency, 90, duration_sec);
    gap = time_sec >= 135 & time_sec < 165;
    data(gap, :) = NaN;
    cycles = reviewed_cycles(frequency, duration_sec, true, true);

    metrics = compute_respiratory_phase_offset_metrics(data, cycles, config);
    gap_grid = metrics.time_sec >= 135 & metrics.time_sec < 165;
    gap_adjacent = metrics.time_sec >= 125 & metrics.time_sec <= 175;
    far_from_gap = (metrics.time_sec >= 60 & metrics.time_sec <= 90) | ...
        (metrics.time_sec >= 210 & metrics.time_sec <= 240);

    verifyFalse(testCase, any(metrics.valid_phase_mask(gap_grid)));
    verifyFalse(testCase, any(metrics.valid_phase_mask(gap_adjacent)));
    verifyTrue(testCase, all(isnan( ...
        metrics.selected_resp_frequency_hz(gap_grid))));
    verifyTrue(testCase, any(metrics.valid_phase_mask(far_from_gap)));
    verifyEqual(testCase, median( ...
        metrics.absolute_mean_phase_deg(far_from_gap), 'omitnan'), ...
        90, 'AbsTol', 2);
    verifyEqual(testCase, metrics.valid_block_count, 2);

    [events, diagnostics] = detect_respiratory_asynchrony( ...
        data, struct('available', false), cycles, config);
    verifyEqual(testCase, numel(events), 2);
    verifyLessThan(testCase, events(1).end_t, 135);
    verifyGreaterThan(testCase, events(2).start_t, 165);
    verifyFalse(testCase, any( ...
        diagnostics.primary_valid_evidence_mask(gap_grid)));
end

function testShortBlocksAndMultipleBoundaryGapsRemainUnevaluable(testCase)
    duration_sec = 300;
    frequency = 0.25;
    [data, config, time_sec] = frequency_fixture( ...
        frequency, 60, duration_sec);
    gaps = time_sec < 10 | ...
        (time_sec >= 90 & time_sec < 105) | ...
        (time_sec >= 112 & time_sec < 127) | ...
        time_sec >= 285;
    data(gaps, :) = NaN;
    cycles = reviewed_cycles(frequency, duration_sec, true, true);

    metrics = compute_respiratory_phase_offset_metrics(data, cycles, config);
    gap_grid = metrics.time_sec < 10 | ...
        (metrics.time_sec >= 90 & metrics.time_sec < 105) | ...
        (metrics.time_sec >= 112 & metrics.time_sec < 127) | ...
        metrics.time_sec >= 285;
    short_grid = metrics.time_sec >= 105 & metrics.time_sec < 112;
    far = (metrics.time_sec >= 40 & metrics.time_sec <= 60) | ...
        (metrics.time_sec >= 200 & metrics.time_sec <= 240);

    verifyGreaterThanOrEqual(testCase, metrics.short_block_count, 1);
    verifyEqual(testCase, metrics.valid_block_count, 2);
    verifyFalse(testCase, any(metrics.valid_phase_mask(gap_grid)));
    verifyFalse(testCase, any(metrics.valid_phase_mask(short_grid)));
    verifyTrue(testCase, all(isnan(metrics.valid_block_id(short_grid))));
    verifyTrue(testCase, any(metrics.valid_phase_mask(far)));
    verifyTrue(testCase, all(isnan( ...
        metrics.absolute_mean_phase_deg(gap_grid))));
end

function [data, config, time_sec] = frequency_fixture( ...
    frequency_hz, angle_deg, duration_sec)
% FREQUENCY_FIXTURE Build two clean equal-frequency respiratory belts.

    [~, config] = phase_fixture(angle_deg, 1);
    time_sec = (0:1/config.fs:(duration_sec - 1/config.fs))';
    data = [ ...
        sin(2 * pi * frequency_hz * time_sec), ...
        sin(2 * pi * frequency_hz * time_sec + deg2rad(angle_deg))];
end

function cycles = reviewed_cycles(frequency_hz, duration_sec, lungs_ok, diaph_ok)
% REVIEWED_CYCLES Build canonical peak timing without redetecting raw breaths.

    peak_t = (0:1/frequency_hz:(duration_sec - 1/frequency_hz))';
    lungs = struct('ok', logical(lungs_ok), 'peak_t', peak_t);
    diaph = struct('ok', logical(diaph_ok), 'peak_t', peak_t);
    if ~lungs_ok
        lungs.peak_t = [];
    end
    if ~diaph_ok
        diaph.peak_t = [];
    end
    cycles = struct('lungs', lungs, 'diaph', diaph);
end

function [data, config, time_sec] = phase_fixture(angle_deg, amplitude)
    fs = 20;
    time_sec = (0:1/fs:(120 - 1/fs))';
    data = [ ...
        amplitude * sin(2 * pi * 0.25 * time_sec), ...
        amplitude * sin(2 * pi * 0.25 * time_sec + deg2rad(angle_deg))];
    config = struct();
    config.fs = fs;
    config.grid_step_sec = 1;
    config.subject = 999;
    config.measure = 1;
    config.make_figs_visible = 'off';
    config.data_columns = {'Resp-Lungs', 'Resp-Diaphragm'};
    config.channels = struct( ...
        'lungs_idx', 1, 'diaph_idx', 2, 'spo2_idx', []);
    config.problems = struct('missing_lung_belt', zeros(0, 2));
    config.async = struct( ...
        'primary_method', 'wavelet_phase_offset', ...
        'compare_methods', true, ...
        'analysis_fs', 20, ...
        'f0', 1, ...
        'fmin', 0.052, ...
        'low_mid_cut_hz', 0.145, ...
        'mid_high_cut_hz', 0.6, ...
        'fmax', 2, ...
        'tlphcoh_cycles', 10, ...
        'min_dur_sec', 5, ...
        'reference_mad_k', 3, ...
        'min_abs_drop', 0.15, ...
        'min_deviating_bins', 1, ...
        'plot_step_sec', 5, ...
        'do_plot', false, ...
        'phase_offset', struct( ...
            'angle_threshold_deg', 30, ...
            'summary_cycles', 5, ...
            'min_resultant_length', 0.80, ...
            'min_valid_fraction', 0.80, ...
            'min_magnitude_fraction', 0.05, ...
            'frequency_min_hz', 0.052, ...
            'frequency_max_hz', 0.6, ...
            'frequency_tolerance_fraction', 0.30, ...
            'frequency_ratio_qc_range', [0.5 1.5], ...
            'lungs_polarity_multiplier', 1, ...
            'diaph_polarity_multiplier', 1, ...
            'edge_exclusion_cycles', 1));
end

function features = minimal_resp_features()
    belt = struct( ...
        'available', true, ...
        'session_amplitude_available', false, ...
        'rate_slow_window_bpm', [], ...
        'rate_rapid_window_bpm', [], ...
        'irregularity', struct('cov', []));
    features = struct( ...
        'lungs', belt, ...
        'diaph', belt, ...
        'thoracoabdominal_balance', struct('available', false));
end
