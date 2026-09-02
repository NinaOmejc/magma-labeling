function tests = test_independent_labels
% Deterministic Phase-4 tests for independent physiological labels.
    tests = functiontests(localfunctions);
end

function testCanonicalLabelOrderAndConfiguration(testCase)
    config = get_config();
    expected = {'shallowB', 'irregB', 'slowB', 'rapidB', 'asyncB', ...
        'desat', 'apnea', 'sigh', 'CSR', 'deepB'};
    verifyEqual(testCase, {config.labels.short}, expected);
    verifyEqual(testCase, [config.labels.idx], 1:10);
    verifyEqual(testCase, config.DeB.amp_ratio_thr, 1.20);
    verifyEqual(testCase, config.DeB.min_dur_sec, 30);

    obsolete = {'classify_depth', 'mark_desat', 'deep_lo_ratio', ...
        'deep_hi_ratio', 'subtype_min_overlap_frac'};
    verifyFalse(testCase, isfield(config.ShB, 'exclude_desat'));
    verifyFalse(testCase, any(isfield(config.SlB, obsolete)));
    verifyFalse(testCase, any(isfield(config.RaB, obsolete)));
    verifyFalse(testCase, isfield(config.Apn, 'mark_desat'));
end

function testDeepThresholdHasNoUpperCutoffAndUsesSessionReference(testCase)
    state_ratios = repmat([1.20; 1.60; 2.00], 9, 1);
    [data, resp_feat, resp_ref, spo2_feat, config] = ...
        amplitude_fixture(state_ratios, state_ratios, 2, 10, 4, 20);
    phys_feat = compute_physiological_features( ...
        data, resp_feat, resp_ref, spo2_feat, config);
    events = detect_deep_breathing(data, phys_feat, config);

    verifyNotEmpty(testCase, events);
    verifyTrue(testCase, any(phys_feat.resp.lungs.deep_amplitude_mask));
    verifyEqual(testCase, phys_feat.resp.deep_ratio_threshold, 1.20);
    deep_peak = resp_feat.lungs.peak_t >= 60 & resp_feat.lungs.peak_t <= 120;
    verifyTrue(testCase, all(phys_feat.resp.lungs.amp_ratio_session(deep_peak) >= 1.20));
    verifyTrue(testCase, any(phys_feat.resp.lungs.amp_ratio_session(deep_peak) >= 2.00));
    verifyTrue(testCase, all(phys_feat.resp.lungs.amp_ratio_global(deep_peak) < 1.20));
    verifyEqual(testCase, phys_feat.resp.lungs.session_reference_value, 2);
    verifyEqual(testCase, phys_feat.resp.diaph.session_reference_value, 10);
    verifyNotEqual(testCase, resp_feat.lungs.amp(find(deep_peak, 1)), ...
        resp_feat.diaph.amp(find(deep_peak, 1)));

    normalized = normalize_event_types_and_meta(events);
    verifyEqual(testCase, numel(normalized), 1);
    verifyEqual(testCase, normalized.type, 'deepB');
    verifyEqual(testCase, normalized.belt, 'both');
end

function testRatioBelowDeepThresholdIsNotDeep(testCase)
    state_ratios = 1.10 * ones(20, 1);
    [data, resp_feat, resp_ref, spo2_feat, config] = ...
        amplitude_fixture(state_ratios, state_ratios, 2, 3, 2, 3);
    phys_feat = compute_physiological_features( ...
        data, resp_feat, resp_ref, spo2_feat, config);
    verifyFalse(testCase, any(phys_feat.resp.lungs.deep_amplitude_mask));
    verifyEmpty(testCase, detect_deep_breathing(data, phys_feat, config));
end

function testMissingLungBeltUsesDiaphragmForDeep(testCase)
    state_ratios = 1.60 * ones(20, 1);
    [data, resp_feat, resp_ref, spo2_feat, config] = ...
        amplitude_fixture(state_ratios, state_ratios, 2, 7, 2, 7);
    config.subject = 7;
    config.measure = 1;
    config.problems.missing_lung_belt = [7 1];
    phys_feat = compute_physiological_features( ...
        data, resp_feat, resp_ref, spo2_feat, config);
    events = detect_deep_breathing(data, phys_feat, config);

    verifyTrue(testCase, phys_feat.resp.lungs.ignored);
    verifyNotEmpty(testCase, events);
    verifyTrue(testCase, all(contains(string({events.type}), '_diaph')));
    normalized = normalize_event_types_and_meta(events);
    verifyEqual(testCase, normalized.belt, 'diaph');
end

function testIndependentDetectorsAndOverlappingMask(testCase)
    [data, phys_feat, config] = detector_fixture();
    shallow = detect_shallow_breathing(data, phys_feat, config);
    deep = detect_deep_breathing(data, phys_feat, config);
    slow = detect_slow_breathing(data, phys_feat, config);
    rapid = detect_rapid_breathing(data, phys_feat, config);
    apnea = detect_apnea(data, phys_feat, config);
    desat = phys_feat.spo2.desaturation_events;

    verifyNotEmpty(testCase, shallow);
    verifyNotEmpty(testCase, deep);
    verifyNotEmpty(testCase, slow);
    verifyNotEmpty(testCase, rapid);
    verifyNotEmpty(testCase, apnea);
    verifyTrue(testCase, all(startsWith(string({rapid.type}), 'rapid_breathing_')));
    verifyTrue(testCase, all(startsWith(string({slow.type}), 'slow_breathing_')));
    verifyTrue(testCase, all(strcmp({apnea.type}, 'apnea')));
    verifyEqual(testCase, unique([rapid.start_t]), 30);
    verifyEqual(testCase, unique([rapid.end_t]), 101);
    verifyEqual(testCase, unique([slow.start_t]), 30);
    verifyEqual(testCase, unique([slow.end_t]), 101);

    events = normalize_event_types_and_meta(merge_events( ...
        {shallow, deep, slow, rapid, apnea, desat}));
    [mask, names] = events_to_time_mask(events, size(data, 1), config);
    sample = 50;
    overlapping = {'shallowB', 'deepB', 'slowB', 'rapidB', 'apnea', 'desat'};
    for i = 1:numel(overlapping)
        verifyTrue(testCase, mask(sample, strcmp(names, overlapping{i})));
    end
    verifySize(testCase, mask, [size(data, 1), 10]);
end

function testNormalizationSchemaAndDeepBeltMerge(testCase)
    lungs = make_event('deep_breathing_lungs', 10, 50, 1);
    diaph = make_event('deep_breathing_diaph', 20, 60, 1);
    events = normalize_event_types_and_meta([lungs; diaph]);

    verifyEqual(testCase, numel(events), 1);
    verifyEqual(testCase, events.type, 'deepB');
    verifyEqual(testCase, events.belt, 'both');
    verifyEqual(testCase, events.start_t, 10);
    verifyEqual(testCase, events.end_t, 60);
    verifyEqual(testCase, fieldnames(events), ...
        {'type'; 'start_idx'; 'end_idx'; 'start_t'; 'end_t'; 'duration'; 'belt'});
end

function testUnknownEventsAreRejectedByFinalMask(testCase)
    config = make_test_config();
    event = make_event('not_a_canonical_label', 1, 2, config.fs);
    verifyError(testCase, @() events_to_time_mask(event, 100, config), ...
        'MAGMA:Mask:UnknownEventType');
end

function testCompoundRawEventTypeIsRejected(testCase)
    event = make_event(['rapid_' 'deep'], 1, 2, 1);
    verifyError(testCase, @() normalize_event_types_and_meta(event), ...
        'MAGMA:Events:UnknownType');
end

function testManualEditorIncludesDeepButNotSigh(testCase)
    definitions = manual_label_definitions();
    fields = {definitions.field};
    verifyTrue(testCase, ismember('deepB', fields));
    verifyFalse(testCase, ismember('sigh', fields));
    verifyEqual(testCase, numel(fields), 9);
end

function testArtificialDeepManipulationAndTenSpecs(testCase)
    fs = 10;
    t = (0:1/fs:120)';
    data = [97 * ones(size(t)), sin(2*pi*0.2*t), 0.8*sin(2*pi*0.2*t + 0.1)];
    modified = modify_data_to_test(data, fs, [2 3], [0.5 1.5], 'deep_breathing', false);
    in_event = t >= 30 & t <= 90;
    verifyEqual(testCase, modified(:, 1), data(:, 1));
    verifyGreaterThan(testCase, std(modified(in_event, 2)), 1.20 * std(data(in_event, 2)));

    repo_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    source = fileread(fullfile(repo_root, 'src', 'utils', 'create_artificial_test_data.m'));
    assignments = regexp(source, 'test_specs\(\d+\)\s*=', 'match');
    verifyEqual(testCase, numel(assignments), 10);
    verifyTrue(testCase, contains(source, "'deepB'"));
    verifyTrue(testCase, contains(source, "'deep_breathing'"));
end

function testNoCompoundDetectorSemanticsRemain(testCase)
    repo_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    detector_names = {'detect_shallow_breathing.m', 'detect_slow_breathing.m', ...
        'detect_rapid_breathing.m', 'detect_apnea.m'};
    forbidden = {['classify_' 'depth'], ['mark_' 'desat'], ['exclude_' 'desat'], ...
        ['rapid_' 'shallow'], ['rapid_' 'deep'], ['rapid_' 'desat'], ...
        ['apnea_' 'desat']};
    for i = 1:numel(detector_names)
        source = fileread(fullfile(repo_root, 'src', 'label_detection', detector_names{i}));
        for j = 1:numel(forbidden)
            verifyFalse(testCase, contains(source, forbidden{j}));
        end
    end
end

function testIrregularityMoveAndFallbacks(testCase)
    repo_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    verifyTrue(testCase, isfile(fullfile(repo_root, 'src', 'feature_extraction', ...
        'compute_irregularity_metrics.m')));
    verifyFalse(testCase, isfile(fullfile(repo_root, 'src', 'label_detection', ...
        'compute_irregularity_metrics.m')));

    files = { ...
        fullfile(repo_root, 'src', 'feature_extraction', 'compute_physiological_features.m'), ...
        fullfile(repo_root, 'src', 'feature_extraction', 'compute_irregularity_metrics.m'), ...
        fullfile(repo_root, 'src', 'label_detection', 'detect_irregular_breathing.m'), ...
        fullfile(repo_root, 'src', 'utils', 'compute_label_diagnostic_signals.m'), ...
        fullfile(repo_root, 'src', 'plotting', 'rewrite_changed_manual_label_figures.m')};
    for i = 1:numel(files)
        source = fileread(files{i});
        verifyFalse(testCase, contains(source, "detection_metric = 'robust_cov'"));
        verifyFalse(testCase, contains(source, "'detection_metric', 'robust_cov'"));
    end
end

function testRespiratoryAmplitudeDocumentationMatchesAlignment(testCase)
    repo_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    source = fileread(fullfile(repo_root, 'src', 'feature_extraction', ...
        'extract_respiration_feature.m'));
    verifyFalse(testCase, contains(source, ['n_peaks' '-1']));
    verifyTrue(testCase, contains(source, 'length n_peaks'));
    verifyTrue(testCase, contains(source, 'final entry is'));
end

function [data, resp_feat, resp_ref, spo2_feat, config] = amplitude_fixture( ...
    state_ratios_lungs, state_ratios_diaph, session_lungs, session_diaph, global_lungs, global_diaph)

    config = make_test_config();
    config.fs = 1;
    config.grid_step_sec = 1;
    config.DeB.do_plot = false;
    config.ShB.do_plot = false;
    N = 181;
    data = zeros(N, 6);
    peak_t = (0:5:180)';
    peak_idx = peak_t + 1;

    ratios_lungs = ones(size(peak_t));
    ratios_diaph = ones(size(peak_t));
    in_state = peak_t >= 60 & peak_t <= 120;
    ratios_lungs(in_state) = repeat_to_length(state_ratios_lungs, nnz(in_state));
    ratios_diaph(in_state) = repeat_to_length(state_ratios_diaph, nnz(in_state));
    amp_lungs = session_lungs * ratios_lungs;
    amp_diaph = session_diaph * ratios_diaph;
    amp_lungs(end) = NaN;
    amp_diaph(end) = NaN;

    resp_feat = struct();
    resp_feat.lungs = reviewed_belt(peak_idx, peak_t, amp_lungs, config.fs);
    resp_feat.diaph = reviewed_belt(peak_idx, peak_t, amp_diaph, config.fs);
    resp_ref = struct();
    resp_ref.lungs = belt_reference(session_lungs, global_lungs);
    resp_ref.diaph = belt_reference(session_diaph, global_diaph);
    spo2_feat = struct('spo2', 97 * ones(N, 1), 'desat_events', empty_events());
end

function values = repeat_to_length(values, n)
    values = values(:);
    values = repmat(values, ceil(n / numel(values)), 1);
    values = values(1:n);
end

function belt = reviewed_belt(peak_idx, peak_t, amp, fs)
    ibi = diff(peak_idx) / fs;
    belt = struct( ...
        'ok', true, ...
        'peak_idx', peak_idx(:), ...
        'peak_t', peak_t(:), ...
        'amp', amp(:), ...
        'ibi', ibi(:), ...
        'rr_bpm', 60 ./ ibi(:));
end

function reference = belt_reference(session_value, global_value)
    reference = struct( ...
        'session', struct('value', session_value, 'available', true), ...
        'global', struct('value', global_value, 'available', true), ...
        'reference_quality', 'good');
end

function [data, phys_feat, config] = detector_fixture()
    config = make_test_config();
    config.fs = 1;
    config.grid_step_sec = 1;
    config.Apn.raw_flat_enabled = false;
    N = 141;
    data = zeros(N, 6);
    t_grid = (0:N-1)';
    state = t_grid >= 30 & t_grid <= 100;

    belt = struct( ...
        'available', true, ...
        'session_amplitude_available', true, ...
        'ignored', false, ...
        'shallow_amplitude_mask', state, ...
        'deep_amplitude_mask', state, ...
        'rate_slow_window_bpm', replace_where(nan(size(t_grid)), state, 8), ...
        'rate_rapid_window_bpm', replace_where(nan(size(t_grid)), state, 25), ...
        'apnea_amp_ratio_session_window_median', replace_where(nan(size(t_grid)), state, 0.05));
    phys_feat = struct();
    phys_feat.resp = struct('time_sec', t_grid, 'lungs', belt, 'diaph', belt);
    phys_feat.spo2 = struct('available', true, ...
        'desaturation_events', make_event('desaturation', 30, 100, config.fs));
end

function values = replace_where(values, mask, replacement)
    values(mask) = replacement;
end

function event = make_event(type, start_t, end_t, fs)
    event = struct( ...
        'type', type, ...
        'start_idx', round(start_t * fs) + 1, ...
        'end_idx', round(end_t * fs) + 1, ...
        'start_t', start_t, ...
        'end_t', end_t, ...
        'duration', end_t - start_t);
end
