function tests = test_periodic_breathing_methods
% Synthetic regression coverage for the two periodic-breathing methods.
    tests = functiontests(localfunctions);
end

function testCurrentPeriodicConfigurationContainsBothMethods(testCase)
    config = get_config();
    verifyEqual(testCase, fieldnames(config.periodic), ...
        {'primary_method'; 'do_plot'; 'eami'; 'guyot'});
    verifyFalse(testCase, isfield(config, 'csr'));
    verifyEqual(testCase, config.periodic.primary_method, 'eami');
    verifyEqual(testCase, fieldnames(config.periodic.eami), ...
        {'resp_band_hz'; 'bandpass_order'; 'resample_hz'; ...
         'envelope_lowpass_hz'; 'envelope_lowpass_order'; ...
         'energy_win_sec'; 'threshold'});
    verifyEqual(testCase, fieldnames(config.periodic.guyot), ...
        {'resample_hz'; 'window_sec'; 'overlap_fraction'; ...
         'h_threshold'; 'fm_band_hz'; 'min_zone_sec'; 'gap_factor'});
    verifyEqual(testCase, config.periodic.eami.threshold, 0.60, ...
        'AbsTol', eps);
    verifyEqual(testCase, config.periodic.guyot.fm_band_hz, ...
        [0.008 0.050], 'AbsTol', eps);
end

function testPeriodicDetectorComputesBothAndSelectsExplicitPrimary(testCase)
    config = periodic_config(10);
    t = (0:1 / config.fs:420)';
    data = belt_data(strong_modulated_carrier(t), nan(size(t)), config);
    breaths = periodic_breaths(0:3:420, 0.5, 0.015);
    resp_cycles = struct('lungs', breaths, ...
        'diaph', empty_respiration_feature('Resp-Diaphragm'));
    expected_eami = compute_eami_periodic_breathing(data, config);
    expected_guyot = compute_guyot_periodic_breathing( ...
        data, resp_cycles, config);

    config.periodic.primary_method = 'eami';
    [events_eami, eami_primary, candidates_eami] = detect_periodic_breathing( ...
        data, resp_cycles, config);
    config.periodic.primary_method = 'guyot';
    [events_guyot, guyot_primary, candidates_guyot] = detect_periodic_breathing( ...
        data, resp_cycles, config);

    verifyTrue(testCase, isfield(eami_primary, 'eami'));
    verifyTrue(testCase, isfield(eami_primary, 'guyot'));
    verifyEqual(testCase, events_eami, expected_eami.combined.events);
    verifyEqual(testCase, events_guyot, expected_guyot.combined.events);
    verifyEqual(testCase, candidates_eami, ...
        expected_eami.combined.candidate_events);
    verifyEqual(testCase, candidates_guyot, ...
        expected_guyot.combined.candidate_events);
    verifyEqual(testCase, eami_primary.eami, guyot_primary.eami);
    verifyEqual(testCase, eami_primary.guyot, guyot_primary.guyot);
    verifyEqual(testCase, eami_primary.primary_method, 'eami');
    verifyEqual(testCase, guyot_primary.primary_method, 'guyot');
    verifyFalse(testCase, isfield(eami_primary, 'primary_events'));
    verifyFalse(testCase, isfield(eami_primary.eami.lungs, 't_sec'));
    verifyEqual(testCase, eami_primary.eami.time_sec, ...
        expected_eami.combined.t_sec);
    verifyEqual(testCase, eami_primary.eami.lungs.index, ...
        expected_eami.lungs.eami);
    verifyEqual(testCase, eami_primary.eami.diaph.index, ...
        expected_eami.diaph.eami);
    verifyFalse(testCase, isfield(eami_primary.eami.lungs, 'eami'));
    verifyFalse(testCase, isfield(eami_primary.eami.diaph, 'eami'));
    verifyFalse(testCase, isfield(eami_primary.eami, 'method_name'));
    verifyFalse(testCase, isfield(eami_primary.guyot, 'method_name'));
end

function testInvalidPrimaryMethodErrorsClearly(testCase)
    config = periodic_config(10);
    config.periodic.primary_method = 'automatic';
    data = zeros(100, numel(config.data_columns));
    resp_cycles = empty_belts();
    verifyError(testCase, ...
        @() detect_periodic_breathing(data, resp_cycles, config), ...
        'MAGMA:Periodic:InvalidPrimaryMethod');
end

function testUnavailablePrimaryDoesNotFallBackToAlternative(testCase)
    config = periodic_config(10);
    config.periodic.primary_method = 'guyot';
    t = (0:1 / config.fs:420)';
    data = belt_data(strong_modulated_carrier(t), nan(size(t)), config);
    [events, diagnostics] = detect_periodic_breathing( ...
        data, empty_belts(), config);

    verifyTrue(testCase, diagnostics.eami.available);
    verifyFalse(testCase, diagnostics.guyot.available);
    verifyFalse(testCase, diagnostics.available);
    verifyEmpty(testCase, events);
    verifyNotEmpty(testCase, diagnostics.primary_unavailable_reason);
end

function testConstantAmplitudeRespirationHasLowEAMI(testCase)
    config = periodic_config(10);
    t = (0:1 / config.fs:300)';
    signal = sin(2 * pi * 0.2 * t);
    diagnostics = compute_eami_periodic_breathing( ...
        belt_data(signal, nan(size(signal)), config), config);
    values = diagnostics.lungs.eami(diagnostics.lungs.evaluable_mask);

    verifyNotEmpty(testCase, values);
    verifyLessThan(testCase, median(values, 'omitnan'), ...
        config.periodic.eami.threshold);
    verifyEmpty(testCase, diagnostics.combined.events);
end

function testStrongAmplitudeModulationCanExceedEAMIThreshold(testCase)
    config = periodic_config(10);
    t = (0:1 / config.fs:300)';
    signal = strong_modulated_carrier(t);
    diagnostics = compute_eami_periodic_breathing( ...
        belt_data(signal, nan(size(signal)), config), config);

    verifyGreaterThan(testCase, max(diagnostics.lungs.eami, [], 'omitnan'), ...
        config.periodic.eami.threshold);
    verifyTrue(testCase, any(diagnostics.lungs.threshold_mask));
end

function testEAMIEnergyUsesLocalMeanRemoval(testCase)
    config = periodic_config(10);
    t = (0:1 / config.fs:240)';
    signal = strong_modulated_carrier(t);
    diagnostics = compute_eami_periodic_breathing( ...
        belt_data(signal, nan(size(signal)), config), config);
    belt = diagnostics.lungs;
    center = find(belt.evaluable_mask, 1, 'first');
    half_window = round(config.periodic.eami.energy_win_sec / 2);
    idx = center - half_window:center + half_window;
    resp = belt.resp_filtered(idx);
    am = belt.amplitude_envelope(idx);
    energy_resp = mean((resp - mean(resp)) .^ 2);
    energy_am = mean((am - mean(am)) .^ 2);
    expected = 1 - 0.5 * log(energy_resp / energy_am);

    verifyEqual(testCase, belt.energy_resp(center), energy_resp, ...
        'AbsTol', 1e-12);
    verifyEqual(testCase, belt.energy_am(center), energy_am, ...
        'AbsTol', 1e-12);
    verifyEqual(testCase, belt.eami(center), expected, 'AbsTol', 1e-12);
end

function testShortModulationDoesNotMeetDerivedEAMIDuration(testCase)
    config = periodic_config(10);
    t = (0:1 / config.fs:150)';
    signal = strong_modulated_carrier(t);
    diagnostics = compute_eami_periodic_breathing( ...
        belt_data(signal, nan(size(signal)), config), config);

    verifyEqual(testCase, diagnostics.min_event_duration_sec, ...
        2 * config.periodic.eami.energy_win_sec);
    verifyEmpty(testCase, diagnostics.combined.events);
end

function testSustainedModulationProducesEAMIEvent(testCase)
    config = periodic_config(10);
    t = (0:1 / config.fs:420)';
    signal = strong_modulated_carrier(t);
    diagnostics = compute_eami_periodic_breathing( ...
        belt_data(signal, nan(size(signal)), config), config);
    verifyNotEmpty(testCase, diagnostics.combined.events);
end

function testEAMIClassificationIsInvariantToPositiveScaling(testCase)
    config = periodic_config(10);
    t = (0:1 / config.fs:360)';
    signal = strong_modulated_carrier(t);
    original = compute_eami_periodic_breathing( ...
        belt_data(signal, nan(size(signal)), config), config);
    scaled = compute_eami_periodic_breathing( ...
        belt_data(7.5 * signal, nan(size(signal)), config), config);

    common = original.lungs.evaluable_mask & scaled.lungs.evaluable_mask;
    verifyEqual(testCase, original.lungs.threshold_mask, ...
        scaled.lungs.threshold_mask);
    verifyEqual(testCase, original.lungs.eami(common), ...
        scaled.lungs.eami(common), 'AbsTol', 1e-8);
end

function testIsolatedTransientDoesNotCreateSustainedEAMIEvent(testCase)
    config = periodic_config(10);
    t = (0:1 / config.fs:360)';
    amplitude = 1 + 8 * exp(-0.5 * ((t - 180) / 1.5) .^ 2);
    signal = amplitude .* sin(2 * pi * 0.2 * t);
    diagnostics = compute_eami_periodic_breathing( ...
        belt_data(signal, nan(size(signal)), config), config);
    verifyEmpty(testCase, diagnostics.combined.events);
end

function testEAMIDoesNotEvaluateAcrossNaNRegions(testCase)
    config = periodic_config(10);
    t = (0:1 / config.fs:360)';
    signal = strong_modulated_carrier(t);
    signal(t >= 140 & t <= 220) = NaN;
    diagnostics = compute_eami_periodic_breathing( ...
        belt_data(signal, nan(size(signal)), config), config);
    unsupported = diagnostics.lungs.t_sec >= 140 & ...
        diagnostics.lungs.t_sec <= 220;
    verifyFalse(testCase, any(diagnostics.lungs.evaluable_mask(unsupported)));
    verifyTrue(testCase, all(isnan(diagnostics.lungs.eami(unsupported))));
end

function testEAMIBothBeltsMustAgree(testCase)
    config = periodic_config(10);
    t = (0:1 / config.fs:420)';
    lungs = strong_modulated_carrier(t);
    diaph = sin(2 * pi * 0.2 * t);
    diagnostics = compute_eami_periodic_breathing( ...
        belt_data(lungs, diaph, config), config);

    verifyTrue(testCase, diagnostics.lungs.available);
    verifyTrue(testCase, diagnostics.diaph.available);
    verifyEmpty(testCase, diagnostics.combined.events);
end

function testEAMISingleAvailableBeltDeterminesResult(testCase)
    config = periodic_config(10);
    t = (0:1 / config.fs:420)';
    lungs = strong_modulated_carrier(t);
    diagnostics = compute_eami_periodic_breathing( ...
        belt_data(lungs, nan(size(lungs)), config), config);

    verifyTrue(testCase, diagnostics.lungs.available);
    verifyFalse(testCase, diagnostics.diaph.available);
    verifyNotEmpty(testCase, diagnostics.combined.events);
end

function testMatrixPencilRecoversSyntheticModulation(testCase)
    fs = 1;
    t = (0:120)';
    expected_h = 0.5;
    expected_fm = 0.015;
    envelope = 1 * (1 + expected_h * cos( ...
        2 * pi * expected_fm * t + 0.4));
    estimate = estimate_matrix_pencil_modulation(envelope, fs);

    verifyTrue(testCase, estimate.evaluable, estimate.failure_reason);
    verifyEqual(testCase, estimate.h, expected_h, 'AbsTol', 0.03);
    verifyEqual(testCase, estimate.fm_hz, expected_fm, 'AbsTol', 0.001);
    verifyLessThan(testCase, estimate.reconstruction_error, 1e-6);
end

function testMatrixPencilReturnsUnavailableForUnidentifiableInputs(testCase)
    constant = estimate_matrix_pencil_modulation(ones(121, 1), 1);
    nearly_constant = estimate_matrix_pencil_modulation( ...
        1 + 1e-12 * (0:120)', 1);
    invalid = estimate_matrix_pencil_modulation([ones(60, 1); NaN], 1);
    too_short = estimate_matrix_pencil_modulation(ones(5, 1), 1);
    no_pair = estimate_matrix_pencil_modulation(linspace(1, 2, 121)', 1);

    verifyFalse(testCase, constant.evaluable);
    verifyFalse(testCase, nearly_constant.evaluable);
    verifyFalse(testCase, invalid.evaluable);
    verifyFalse(testCase, too_short.evaluable);
    verifyFalse(testCase, no_pair.evaluable);
end

function testGuyotEnvelopeInterpolatesOrdinaryBreaths(testCase)
    result = reconstruct_guyot_envelope( ...
        [1; 3; 5], [2; 4; 2], 8, 1, 3);
    verifyEqual(testCase, result.envelope(result.envelope_t == 2), 3, ...
        'AbsTol', eps);
    verifyTrue(testCase, result.evaluable_mask(result.envelope_t == 2));
end

function testGuyotEnvelopeZerosLongBreathGap(testCase)
    result = reconstruct_guyot_envelope( ...
        [10; 12; 14; 30; 32], [1; 2; 3; 2; 1], 40, 1, 3);
    inside = result.envelope_t > 14 & result.envelope_t < 30;
    verifyTrue(testCase, all(result.envelope(inside) == 0));
    verifyTrue(testCase, all(result.long_gap_mask(inside)));
end

function testGuyotEnvelopeDoesNotExtrapolate(testCase)
    result = reconstruct_guyot_envelope( ...
        [10; 12; 14], [1; 2; 1], 20, 1, 3);
    before = result.envelope_t < 10;
    after = result.envelope_t > 14;
    verifyFalse(testCase, any(result.evaluable_mask(before | after)));
    verifyTrue(testCase, all(isnan(result.envelope(before | after))));
end

function testGuyotUsesCanonicalMAGMABreathAmplitude(testCase)
    config = periodic_config(10);
    breath_t = (0:3:300)';
    breaths = periodic_breaths(breath_t, 0.5, 0.015);
    breaths.peak_val = 100 + zeros(size(breath_t));
    breaths.trough_val = -100 + zeros(size(breath_t));
    expected_amp = breaths.amp;
    resp_cycles = struct('lungs', breaths, ...
        'diaph', empty_respiration_feature('Resp-Diaphragm'));
    data = zeros(300 * config.fs + 1, numel(config.data_columns));
    diagnostics = compute_guyot_periodic_breathing(data, resp_cycles, config);

    verifyEqual(testCase, diagnostics.lungs.canonical_breath_amp, expected_amp);
end

function testGuyotClassificationUsesConfiguredMAGMAThresholds(testCase)
    h = [0.13; 0.12; 0.50; 0.50; 0.50];
    fm = [0.015; 0.015; 0.007; 0.051; 0.050];
    actual = classify_guyot_modulation( ...
        h, fm, true(size(h)), 0.12, [0.008 0.050]);
    verifyEqual(testCase, actual, [true; false; false; false; true]);
end

function testGuyotCenterProjectionAndPersistence(testCase)
    window_sec = 120;
    overlap_fraction = 0.80;
    expected_step = window_sec * (1 - overlap_fraction);
    centers = (60:expected_step:156)';
    verifyEqual(testCase, diff(centers), ...
        expected_step * ones(numel(centers) - 1, 1), 'AbsTol', 1e-12);

    t = (0:240)';
    evaluable = true(size(centers));
    isolated = logical([0; 0; 1; 0; 0]);
    two_consecutive = logical([0; 1; 1; 0; 0]);
    three_consecutive = logical([0; 1; 1; 1; 0]);
    [evaluable_time, isolated_time] = project_guyot_window_estimates( ...
        t, centers, evaluable, isolated);
    [~, two_time] = project_guyot_window_estimates( ...
        t, centers, evaluable, two_consecutive);
    [~, three_time] = project_guyot_window_estimates( ...
        t, centers, evaluable, three_consecutive);

    isolated_support = t(isolated_time);
    verifyLessThanOrEqual(testCase, ...
        abs(isolated_support(1) - mean(centers(2:3))), 1);
    verifyLessThanOrEqual(testCase, ...
        abs(isolated_support(end) - mean(centers(3:4))), 1);

    unavailable = false(size(t));
    isolated_combined = combine_periodic_belt_evidence( ...
        t, evaluable_time, isolated_time, unavailable, unavailable, ...
        60, numel(t), 1);
    two_combined = combine_periodic_belt_evidence( ...
        t, evaluable_time, two_time, unavailable, unavailable, ...
        60, numel(t), 1);
    three_combined = combine_periodic_belt_evidence( ...
        t, evaluable_time, three_time, unavailable, unavailable, ...
        60, numel(t), 1);

    verifyEmpty(testCase, isolated_combined.events);
    verifyEmpty(testCase, two_combined.events);
    verifyNotEmpty(testCase, three_combined.events);
    verifyGreaterThanOrEqual(testCase, ...
        three_combined.events(1).duration, 60);
end

function testGuyotPersistenceRequiresFullMinute(testCase)
    t = (10:108)';
    short = false(size(t)); short(1:59) = true;
    long = false(size(t)); long(1:60) = true;
    none = false(size(t));
    short_combined = combine_periodic_belt_evidence( ...
        t, true(size(t)), short, none, none, 60, 120, 1);
    long_combined = combine_periodic_belt_evidence( ...
        t, true(size(t)), long, none, none, 60, 120, 1);

    verifyEmpty(testCase, short_combined.events);
    verifyNotEmpty(testCase, long_combined.events);
end

function testGuyotBeltCombinationRequiresAgreement(testCase)
    t = (10:100)';
    evaluable = true(size(t));
    positive = true(size(t));
    negative = false(size(t));
    both = combine_periodic_belt_evidence( ...
        t, evaluable, positive, evaluable, negative, 60, 120, 1);
    one = combine_periodic_belt_evidence( ...
        t, evaluable, positive, negative, negative, 60, 120, 1);

    verifyEmpty(testCase, both.events);
    verifyNotEmpty(testCase, one.events);
end

function testGuyotSlidingWindowsDetectSyntheticPathologicalEnvelope(testCase)
    config = periodic_config(10);
    breath_t = (0:3:420)';
    breaths = periodic_breaths(breath_t, 0.5, 0.015);
    resp_cycles = struct('lungs', breaths, ...
        'diaph', empty_respiration_feature('Resp-Diaphragm'));
    data = zeros(420 * config.fs + 1, numel(config.data_columns));
    diagnostics = compute_guyot_periodic_breathing(data, resp_cycles, config);

    expected_step = config.periodic.guyot.window_sec * ...
        (1 - config.periodic.guyot.overlap_fraction);
    verifyEqual(testCase, diagnostics.step_sec, expected_step, 'AbsTol', eps);
    verifyEqual(testCase, diff(diagnostics.lungs.window_center_t), ...
        expected_step * ones(numel(diagnostics.lungs.window_center_t) - 1, 1), ...
        'AbsTol', 1 / config.periodic.guyot.resample_hz);
    verifyTrue(testCase, any(diagnostics.lungs.pathological_window_mask));
    verifyNotEmpty(testCase, diagnostics.combined.events);
end

function testMethodMetadataAndComparisonPlotArePresent(testCase)
    repo_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    detector = fileread(fullfile(repo_root, 'src', ...
        'label_detection', 'detect_periodic_breathing.m'));
    required = {'compute_eami_periodic_breathing', ...
        'compute_guyot_periodic_breathing', 'primary_method', ...
        'diagnostics.primary_events', ...
        'Raw respiratory effort belts + final periodic label', ...
        'title(''eAMI'')', ...
        'Guyot canonical breath-amplitude envelope', ...
        'eami.combined.events', 'guyot.combined.events'};
    for i = 1:numel(required)
        verifyTrue(testCase, contains(detector, required{i}));
    end
    verifyEqual(testCase, count(detector, 'subplot(3, 1'), 3);
    removed = {'subplot(6, 1', 'Guyot modulation depth', ...
        'Guyot modulation frequency', 'Final method timelines'};
    for i = 1:numel(removed)
        verifyFalse(testCase, contains(detector, removed{i}));
    end
end

function testEvidenceConsumersUseBothLiteratureMethods(testCase)
    repo_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    summary_source = fileread(fullfile(repo_root, 'src', 'utils', ...
        'build_label_evidence_summary.m'));
    group_source = fileread(fullfile(repo_root, 'src', 'group', ...
        'build_group_label_table.m'));
    plot_source = fileread(fullfile(repo_root, 'src', 'group', ...
        'plot_group_diagnostic_overview.m'));
    required_summary = {'detector_specific_evidence_summary_v3', ...
        'eami_available', 'eami_event_count', ...
        'eami_event_duration_sec', 'eami_max', 'eami_median', ...
        'guyot_available', 'guyot_event_count', ...
        'guyot_event_duration_sec', 'guyot_max_h', ...
        'guyot_median_h', 'guyot_median_fm_mhz'};
    for i = 1:numel(required_summary)
        verifyTrue(testCase, contains(summary_source, required_summary{i}));
    end
    removed_summary = {'eami_candidate_event_count', ...
        'eami_candidate_duration_sec', 'guyot_candidate_event_count', ...
        'guyot_candidate_duration_sec', ...
        'global_reference_quality_lungs', ...
        'global_reference_quality_diaph'};
    for i = 1:numel(removed_summary)
        verifyFalse(testCase, contains(summary_source, removed_summary{i}));
    end
    verifyTrue(testCase, contains(group_source, ...
        '''detector_diagnostics'', ''periodic.eami.lungs.index'''));
    verifyTrue(testCase, contains(group_source, '''trace_eami_lungs'''));
    verifyTrue(testCase, contains(plot_source, ...
        '''detector_diagnostics'', ...'));
    verifyTrue(testCase, contains(plot_source, ...
        '''periodic.eami.time_sec'''));
    verifyTrue(testCase, contains(plot_source, '''trace_eami_lungs'''));
    verifyFalse(testCase, isfile(fullfile(repo_root, 'src', 'utils', ...
        'compute_label_diagnostic_signals.m')));
end

function config = periodic_config(fs)
% PERIODIC_CONFIG Build a non-interactive resolved test configuration.

    config = make_test_config();
    config.fs = fs;
    config.periodic.do_plot = false;
    config.problems.missing_lung_belt = zeros(0, 2);
    config = resolve_signal_channels(config);
end

function data = belt_data(lungs, diaph, config)
% BELT_DATA Place two synthetic belts in the configured recording matrix.

    data = zeros(numel(lungs), numel(config.data_columns));
    data(:, config.channels.lungs_idx) = lungs(:);
    data(:, config.channels.diaph_idx) = diaph(:);
end

function signal = strong_modulated_carrier(t)
% STRONG_MODULATED_CARRIER Produce sustained 0.015-Hz amplitude modulation.

    amplitude = exp(4.0 * cos(2 * pi * 0.015 * t));
    signal = amplitude .* sin(2 * pi * 0.2 * t);
end

function breaths = periodic_breaths(breath_t, h, fm_hz)
% PERIODIC_BREATHS Return canonical breath amplitudes on a sinusoidal envelope.

    breath_t = breath_t(:);
    breaths = empty_respiration_feature('Resp-Lungs');
    breaths.ok = true;
    breaths.peak_t = breath_t;
    breaths.peak_idx = (1:numel(breath_t))';
    breaths.amp = 1 + h * cos(2 * pi * fm_hz * breath_t + 0.4);
end

function resp_cycles = empty_belts()
% EMPTY_BELTS Return the two expected unavailable belt structs.

    resp_cycles = struct( ...
        'lungs', empty_respiration_feature('Resp-Lungs'), ...
        'diaph', empty_respiration_feature('Resp-Diaphragm'));
end
