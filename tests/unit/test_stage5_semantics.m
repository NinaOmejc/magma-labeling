function tests = test_stage5_semantics
% Deterministic Stage-5 temporal, availability, burden, and phenotype tests.
    tests = functiontests(localfunctions);
end

function testEvidenceVersionAndCanonicalOrder(testCase)
    [data, resp_feat, resp_ref, spo2_feat, config] = physiological_fixture();
    phys = compute_physiological_features(data, resp_feat, resp_ref, spo2_feat, config);
    verifyEqual(testCase, phys.version, 'independent_physiological_evidence_v2');
    verifyEqual(testCase, {config.labels.short}, ...
        {'shallowB', 'irregB', 'slowB', 'rapidB', 'asyncB', 'desat', ...
         'apnea', 'sigh', 'CSR', 'deepB', 'thorDomB'});
end

function testThoracicEndpointAndStateHaveDistinctSemantics(testCase)
    config = stage_config();
    t = (0:100)';
    endpoint = false(size(t));
    endpoint(t == 60) = true;
    state = analysis_window_endpoints_to_state_mask( ...
        endpoint, t, config.TDB.analysis_win_sec);
    verifyEqual(testCase, find(endpoint), 61);
    verifyEqual(testCase, find(state), (31:61)');

    evidence = struct('available', true, ...
        'dominance_endpoint_mask', endpoint, ...
        'dominance_state_mask', state, ...
        'dominance_mask', state);
    phys = struct('resp', struct('time_sec', t, ...
        'thoracoabdominal_balance', evidence));
    data = zeros(101, 6);
    events = detect_thoracic_dominant_breathing(data, phys, config);
    verifyNumElements(testCase, events, 1);
    verifyEqual(testCase, events.start_t, 30);
    verifyLessThan(testCase, events.end_t, 62);
end

function testThirtySecondThoracicStateDoesNotRequireSixtySeconds(testCase)
    config = stage_config();
    t = (0:90)';
    endpoint = false(size(t));
    endpoint(t == 45) = true;
    state = analysis_window_endpoints_to_state_mask(endpoint, t, 30);
    evidence = struct('available', true, ...
        'dominance_endpoint_mask', endpoint, ...
        'dominance_state_mask', state, 'dominance_mask', state);
    phys.resp = struct('time_sec', t, 'thoracoabdominal_balance', evidence);
    events = detect_thoracic_dominant_breathing(zeros(91, 6), phys, config);
    verifyNotEmpty(testCase, events);
    verifyGreaterThanOrEqual(testCase, events.duration, 30);
    verifyLessThan(testCase, events.duration, 35);
end

function testRapidAndSlowWindowsAreSeparateFromMinimumDuration(testCase)
    config = stage_config();
    verifyEqual(testCase, config.RaB.analysis_win_sec, 30);
    verifyEqual(testCase, config.RaB.min_dur_sec, 30);
    verifyEqual(testCase, config.SlB.analysis_win_sec, 60);
    verifyEqual(testCase, config.SlB.min_dur_sec, 30);

    t = (0:100)';
    rapid_endpoint = t == 60;
    slow_endpoint = t == 80;
    lungs = empty_detector_belt(t);
    lungs.available = true;
    lungs.rate_rapid_window_bpm(rapid_endpoint) = 25;
    lungs.rate_rapid_endpoint_mask = rapid_endpoint;
    lungs.rate_rapid_state_mask = analysis_window_endpoints_to_state_mask(rapid_endpoint, t, 30);
    lungs.rate_slow_window_bpm(slow_endpoint) = 8;
    lungs.rate_slow_endpoint_mask = slow_endpoint;
    lungs.rate_slow_state_mask = analysis_window_endpoints_to_state_mask(slow_endpoint, t, 60);
    diaph = empty_detector_belt(t);
    phys.resp = struct('time_sec', t, 'rate_windows_sec', ...
        struct('slow', 60, 'rapid', 30), 'lungs', lungs, 'diaph', diaph);

    rapid = detect_rapid_breathing(zeros(101, 6), phys, config);
    slow = detect_slow_breathing(zeros(101, 6), phys, config);
    verifyNotEmpty(testCase, rapid);
    verifyEqual(testCase, rapid.start_t, 30);
    verifyNotEmpty(testCase, slow);
    verifyEqual(testCase, slow.start_t, 20);
end

function testIrregularWindowAndDurationAreSeparateWithoutDoubleApplication(testCase)
    config = stage_config();
    verifyEqual(testCase, config.IrB.analysis_win_sec, 60);
    verifyEqual(testCase, config.IrB.min_dur_sec, 60);
    t = (0:100)';
    lungs = empty_detector_belt(t);
    lungs.available = true;
    lungs.irregularity.window_mask(t <= 60) = true;
    lungs.irregularity.endpoint_mask(t == 60) = true;
    lungs.irregularity.cov(t == 60) = 0.4;
    diaph = empty_detector_belt(t);
    phys.resp = struct('time_sec', t, 'lungs', lungs, 'diaph', diaph);
    events = detect_irregular_breathing(zeros(101, 6), phys, config);
    verifyNotEmpty(testCase, events);
    verifyEqual(testCase, events.start_t, 0);
    verifyLessThan(testCase, events.duration, 65);
end

function testTenSecondApneaWindowDoesNotRequireTwentySeconds(testCase)
    config = stage_config();
    config.Apn.raw_flat_enabled = false;
    t = (0:50)';
    lungs = empty_detector_belt(t);
    lungs.available = true;
    lungs.session_amplitude_available = true;
    lungs.apnea_amp_ratio_session_window_median(t == 20) = 0.05;
    diaph = empty_detector_belt(t);
    phys.resp = struct('time_sec', t, 'lungs', lungs, 'diaph', diaph);
    [events, diagnostics] = detect_apnea(zeros(51, 6), phys, config);
    verifyNotEmpty(testCase, events);
    verifyEqual(testCase, events.start_t, 10);
    verifyLessThan(testCase, events.duration, 15);
    verifyNotEqual(testCase, diagnostics.peak_endpoint_mask, diagnostics.peak_state_mask);
end

function testEvidenceAwareAvailabilityAndReasonOrder(testCase)
    [names, phys, spo2, rea, apnea, sigh, csr] = availability_fixture();
    rea.valid_analysis = false;
    rea.skip_code = 5;
    phys.spo2.available = false;
    spo2.detection_available = false;
    [available, reasons] = compute_label_availability( ...
        names, phys, spo2, rea, apnea, sigh, csr);
    verifySize(testCase, available, [1 11]);
    verifySize(testCase, reasons, [1 11]);
    verifyFalse(testCase, available(strcmp(names, 'asyncB')));
    verifyEqual(testCase, reasons{strcmp(names, 'asyncB')}, ...
        'respiratory_asynchrony_analysis_invalid');
    verifyFalse(testCase, available(strcmp(names, 'desat')));
    verifyEqual(testCase, reasons{strcmp(names, 'desat')}, 'invalid_spo2');
    verifyEqual(testCase, reasons(available), repmat({'available'}, 1, nnz(available)));
end

function testKnownOneBeltCaseMakesThoracicAndAsynchronyUnavailable(testCase)
    [names, phys, spo2, rea, apnea, sigh, csr] = availability_fixture();
    phys.resp.lungs.available = false;
    phys.resp.lungs.session_amplitude_available = false;
    phys.resp.thoracoabdominal_balance.available = false;
    rea.valid_analysis = false;
    rea.skip_code = 2;
    [available, reasons] = compute_label_availability( ...
        names, phys, spo2, rea, apnea, sigh, csr);
    verifyFalse(testCase, available(strcmp(names, 'thorDomB')));
    verifyEqual(testCase, reasons{strcmp(names, 'thorDomB')}, 'one_belt_only');
    verifyFalse(testCase, available(strcmp(names, 'asyncB')));
    verifyEqual(testCase, reasons{strcmp(names, 'asyncB')}, 'one_belt_only');
end

function testAssessedZeroAndUnavailableBurdenAreDistinct(testCase)
    config = stage_config();
    names = {config.labels.short};
    mask = false(100, 11);
    available = true(1, 11);
    available(strcmp(names, 'thorDomB')) = false;
    burden = compute_recording_label_burden( ...
        mask, names, available, normalize_event_types_and_meta(empty_events()), config.fs);
    verifyEqual(testCase, burden.by_label.rapidB.duration_sec, 0);
    verifyEqual(testCase, burden.by_label.rapidB.fraction, 0);
    verifyEqual(testCase, burden.by_label.rapidB.event_count, 0);
    verifyTrue(testCase, isnan(burden.by_label.thorDomB.duration_sec));
    verifyTrue(testCase, isnan(burden.by_label.thorDomB.fraction));
    verifyTrue(testCase, isnan(burden.by_label.thorDomB.event_count));
end

function testBurdenUsesAssessableSamplesWhenProvided(testCase)
    config = stage_config();
    names = {config.labels.short};
    mask = false(100, 11);
    rapid_idx = strcmp(names, 'rapidB');
    mask(1:25, rapid_idx) = true;
    assessable = true(100, 11);
    assessable(51:end, rapid_idx) = false;
    burden = compute_recording_label_burden(mask, names, true(1,11), ...
        normalize_event_types_and_meta(empty_events()), 10, assessable);
    verifyEqual(testCase, burden.by_label.rapidB.duration_sec, 2.5);
    verifyEqual(testCase, burden.by_label.rapidB.assessable_duration_sec, 5);
    verifyEqual(testCase, burden.by_label.rapidB.fraction, 0.5);
end

function testPrespecifiedOverlapsDoNotCreateMaskColumns(testCase)
    config = stage_config();
    names = {config.labels.short};
    mask = false(100, 11);
    mask(1:20, strcmp(names, 'rapidB')) = true;
    mask(11:30, strcmp(names, 'deepB')) = true;
    mask(41:50, strcmp(names, 'apnea')) = true;
    mask(46:55, strcmp(names, 'desat')) = true;
    original_size = size(mask);
    overlaps = compute_label_overlap_summary(mask, names, true(1,11), 10);
    verifyEqual(testCase, size(mask), original_size);
    verifyEqual(testCase, overlaps.rapid_deep.overlap_duration_sec, 1);
    verifyEqual(testCase, overlaps.rapid_deep.fraction_of_a_overlapped_by_b, 0.5);
    verifyEqual(testCase, overlaps.rapid_deep.fraction_of_b_overlapped_by_a, 0.5);
    verifyEqual(testCase, overlaps.apnea_desaturation.fraction_of_a_overlapped_by_b, 0.5);
end

function testFivePhenotypesAreEvidenceNotNewDiagnoses(testCase)
    [burden, overlaps, label_evidence] = phenotype_fixture();
    evidence = build_db_phenotype_evidence(burden, overlaps, label_evidence);
    phenotype_names = setdiff(fieldnames(evidence), {'version'; 'levels'});
    verifyEqual(testCase, numel(phenotype_names), 5);
    verifyFalse(testCase, evidence.hyperventilation_syndrome.assessable_from_current_signals);
    verifyFalse(testCase, isfield(evidence.hyperventilation_syndrome, 'diagnosis'));
    verifyFalse(testCase, evidence.forced_abdominal_expiration.assessable_from_current_signals);
    verifyFalse(testCase, evidence.forced_abdominal_expiration.evidence_available);
    verifyTrue(testCase, evidence.periodic_deep_sighing.evidence_available);
    verifyFalse(testCase, isfield( ...
        evidence.periodic_deep_sighing.signal_derived_measures, 'CSR'));
    verifyEqual(testCase, ...
        evidence.thoracic_dominant_breathing.signal_derived_measures.median_thoracic_to_abdominal_ratio, 1.7);
    verifyTrue(testCase, evidence.thoracoabdominal_asynchrony.signal_derived_measures.analysis_valid);
end

function testEvidenceSummaryDoesNotInventConfidence(testCase)
    repo_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    source = fileread(fullfile(repo_root, 'src', 'utils', 'build_label_evidence_summary.m'));
    invented_field = regexp(lower(source), ...
        '(?m)^\s*summary\.[^=]*(confidence|probability)\s*=', 'once');
    verifyEmpty(testCase, invented_field);
end

function config = stage_config()
    config = make_test_config();
    config.fs = 1;
    config.grid_step_sec = 1;
    config.TDB.do_plot = false;
    config.RaB.do_plot = false;
    config.SlB.do_plot = false;
    config.IrB.do_plot = false;
    config.Apn.do_plot = false;
end

function belt = empty_detector_belt(t)
    belt = struct( ...
        'available', false, 'session_amplitude_available', false, ...
        'global_amplitude_available', false, 'ignored', false, ...
        'rate_slow_window_bpm', nan(size(t)), ...
        'rate_rapid_window_bpm', nan(size(t)), ...
        'rate_slow_endpoint_mask', false(size(t)), ...
        'rate_slow_state_mask', false(size(t)), ...
        'rate_rapid_endpoint_mask', false(size(t)), ...
        'rate_rapid_state_mask', false(size(t)), ...
        'apnea_amp_ratio_session_window_median', nan(size(t)), ...
        'irregularity', struct('window_mask', false(size(t)), ...
            'endpoint_mask', false(size(t)), 'cov', nan(size(t)), ...
            'robust_cov', nan(size(t)), 'rmssd_sec', nan(size(t)), ...
            'pause_exclusion_mask', false(size(t))));
end

function [data, resp_feat, resp_ref, spo2_feat, config] = physiological_fixture()
    config = stage_config();
    config.fs = 2;
    config.grid_step_sec = 1;
    t = (0:5:100)';
    idx = round(t * config.fs) + 1;
    amp = ones(size(t)); amp(end) = NaN;
    belt = struct('ok', true, 'peak_idx', idx, 'peak_t', t, ...
        'amp', amp, 'ibi', diff(t), 'rr_bpm', 60 ./ diff(t));
    resp_feat = struct('lungs', belt, 'diaph', belt);
    reference = struct('session', struct('value', 1, 'available', true), ...
        'global', struct('value', 1, 'available', true), ...
        'reference_quality', 'good');
    resp_ref = struct('lungs', reference, 'diaph', reference);
    data = zeros(201, 6);
    spo2_feat = struct('spo2', 97 * ones(201,1), ...
        'desat_events', empty_events());
end

function [names, phys, spo2, rea, apnea, sigh, csr] = availability_fixture()
    config = stage_config();
    names = {config.labels.short};
    t = (0:100)';
    belt = empty_detector_belt(t);
    belt.available = true;
    belt.session_amplitude_available = true;
    belt.global_amplitude_available = true;
    belt.rate_slow_window_bpm(61:end) = 12;
    belt.rate_rapid_window_bpm(31:end) = 12;
    belt.irregularity.cov(61:end) = 0.1;
    balance = struct('available', true);
    phys = struct('resp', struct('lungs', belt, 'diaph', belt, ...
        'thoracoabdominal_balance', balance), ...
        'spo2', struct('available', true));
    spo2 = struct('idx_spo2', 3, 'spo2', 97*ones(101,1), ...
        'detection_available', true);
    rea = struct('valid_analysis', true, 'skip_code', 0);
    apnea = struct('available', true);
    sigh = struct('available', true);
    csr = struct('available', true);
end

function [burden, overlaps, evidence] = phenotype_fixture()
    config = stage_config();
    names = {config.labels.short};
    mask = false(100, 11);
    available = true(1, 11);
    burden = compute_recording_label_burden( ...
        mask, names, available, normalize_event_types_and_meta(empty_events()), 1);
    burden.sigh_count = 2;
    burden.sighs_per_15_min = 18;
    overlaps = compute_label_overlap_summary(mask, names, available, 1);
    evidence.rapidB = struct('median_rr_lungs', 22, 'median_rr_diaph', 21);
    evidence.deepB = struct('median_ratio_lungs', 1.3, 'median_ratio_diaph', 1.4);
    evidence.thorDomB = struct('median_ratio', 1.7, ...
        'median_log_ratio', log(1.7), 'median_relative_fraction', 1.7/2.7);
    evidence.asyncB = struct('analysis_valid', true, ...
        'baseline_coherence', struct('high', 0.8, 'mid', 0.8, 'low', 0.8), ...
        'median_observed_coherence', struct('high', 0.5, 'mid', 0.5, 'low', 0.5), ...
        'maximum_deviating_bins', 2);
end
