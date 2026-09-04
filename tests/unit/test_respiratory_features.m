function tests = test_respiratory_features
% Deterministic regression tests for the respiratory evidence layer.
    tests = functiontests(localfunctions);
end

function testReviewedBreathsAndAlignmentArePreserved(testCase)
    [data, resp_cycles, resp_ref, diagnostics_desat, config] = feature_fixture();
    resp_features = compute_respiratory_features( ...
        data, resp_cycles, resp_ref, config);
    lungs = resp_features.resp.lungs;

    verifyEqual(testCase, lungs.peak_idx, resp_cycles.lungs.peak_idx);
    verifyEqual(testCase, lungs.peak_t, resp_cycles.lungs.peak_t);
    verifyEqual(testCase, lungs.amp, resp_cycles.lungs.amp);
    verifyEqual(testCase, lungs.ibi, resp_cycles.lungs.ibi);
    verifyEqual(testCase, lungs.rr_bpm, resp_cycles.lungs.rr_bpm);
    verifyEqual(testCase, numel(lungs.ibi), numel(lungs.peak_t) - 1);
    verifyEqual(testCase, numel(lungs.rr_bpm), numel(lungs.peak_t) - 1);
    verifyTrue(testCase, isnan(lungs.amp(end)));
    verifyFalse(testCase, resp_features.provenance.redetected_respiratory_peaks);
    verifyEqual(testCase, resp_features.provenance.cycle_source, 'resp_cycles');
    verifyEqual(testCase, resp_features.provenance.cycle_review_status, 'automatic');
    verifyFalse(testCase, resp_features.provenance.manual_review_performed);
    verifyFalse(testCase, resp_features.provenance.manual_edits_made);
end

function testSessionAndGlobalRatiosHandleInvalidAmplitudes(testCase)
    [data, resp_cycles, resp_ref, diagnostics_desat, config] = feature_fixture();
    resp_cycles.lungs.amp(8) = 0;
    resp_cycles.lungs.amp(9) = -1;
    resp_cycles.lungs.amp(10) = NaN;
    resp_features = compute_respiratory_features( ...
        data, resp_cycles, resp_ref, config);
    lungs = resp_features.resp.lungs;

    valid = isfinite(resp_cycles.lungs.amp) & resp_cycles.lungs.amp > 0;
    expected_session = nan(size(resp_cycles.lungs.amp));
    expected_session(valid) = resp_cycles.lungs.amp(valid) / 2;
    expected_global = nan(size(resp_cycles.lungs.amp));
    expected_global(valid) = resp_cycles.lungs.amp(valid) / 1.5;

    verifyTrue(testCase, isequaln(lungs.amp_ratio_session, expected_session));
    verifyTrue(testCase, isequaln(lungs.amp_ratio_global, expected_global));
    verifyTrue(testCase, all(isnan(lungs.amp_ratio_session(8:10))));
    verifyTrue(testCase, isnan(lungs.amp_ratio_session(end)));
end

function testBeltsRemainIndependentAndSpo2IsExcluded(testCase)
    [data, resp_cycles, resp_ref, diagnostics_desat, config] = feature_fixture();
    resp_features = compute_respiratory_features( ...
        data, resp_cycles, resp_ref, config);

    verifyEqual(testCase, resp_features.resp.lungs.session_reference_value, 2);
    verifyEqual(testCase, resp_features.resp.diaph.session_reference_value, 4);
    verifyEqual(testCase, resp_features.resp.lungs.amp_ratio_session(1), 1);
    verifyEqual(testCase, resp_features.resp.diaph.amp_ratio_session(1), 0.5);
    verifyTrue(testCase, resp_features.resp.both_belts_available);
    verifyFalse(testCase, isfield(resp_features, 'spo2'));
end

function testMissingLungBeltLeavesDiaphragmValid(testCase)
    [data, resp_cycles, resp_ref, diagnostics_desat, config] = feature_fixture();
    config.subject = 1;
    config.measure = 1;
    config.problems.missing_lung_belt = [1 1];
    resp_features = compute_respiratory_features( ...
        data, resp_cycles, resp_ref, config);

    verifyTrue(testCase, resp_features.resp.lungs.ignored);
    verifyFalse(testCase, resp_features.resp.lungs.available);
    verifyFalse(testCase, resp_features.resp.lungs.session_reference_available);
    verifyTrue(testCase, all(isnan(resp_features.resp.lungs.amp_ratio_session)));
    verifyTrue(testCase, resp_features.resp.diaph.available);
    verifyTrue(testCase, resp_features.resp.diaph.session_amplitude_available);
    verifyFalse(testCase, resp_features.resp.both_belts_available);
end

function testRateAndIrregularityEvidenceMatchesDefinitions(testCase)
    [data, resp_cycles, resp_ref, diagnostics_desat, config] = feature_fixture();
    resp_features = compute_respiratory_features( ...
        data, resp_cycles, resp_ref, config);
    t_grid = resp_features.resp.time_sec;

    expected_slow = ibi_rate_trace_reference( ...
        resp_cycles.lungs.peak_t, t_grid, config.slow.analysis_win_sec);
    expected_rapid = ibi_rate_trace_reference( ...
        resp_cycles.lungs.peak_t, t_grid, config.rapid.analysis_win_sec);
    verifyTrue(testCase, isequaln( ...
        resp_features.resp.lungs.rate_slow_window_bpm, expected_slow));
    verifyTrue(testCase, isequaln( ...
        resp_features.resp.lungs.rate_rapid_window_bpm, expected_rapid));

    [expected_mask, expected_cov, expected_robust, expected_rmssd, expected_endpoint] = ...
        compute_irregularity_metrics(resp_cycles.lungs, t_grid, ...
        config.irregular.analysis_win_sec, config.irregular.cov_thr, ...
        config.irregular.robust_cov_thr, config.irregular.rmssd_thr, ...
        config.irregular.pause_thr_sec, config.irregular.detection_metric);
    actual = resp_features.resp.lungs.irregularity;
    verifyTrue(testCase, isequaln(actual.window_mask, expected_mask));
    verifyTrue(testCase, isequaln(actual.endpoint_mask, expected_endpoint));
    verifyTrue(testCase, isequaln(actual.cov, expected_cov));
    verifyTrue(testCase, isequaln(actual.robust_cov, expected_robust));
    verifyTrue(testCase, isequaln(actual.rmssd_sec, expected_rmssd));
end

function testWindowRateUsesSixtyOverMeanIbiAndIsShared(testCase)
    peaks = [10; 20; 40; 50];
    [data, resp_cycles, resp_ref, diagnostics_desat, config] = ...
        rate_only_feature_fixture(peaks, 120);
    resp_features = compute_respiratory_features( ...
        data, resp_cycles, resp_ref, config);
    t_grid = resp_features.resp.time_sec;
    endpoint = t_grid == 60;

    expected = 60 / mean(diff(peaks));
    count_based = nnz(peaks >= 0 & peaks < 60) / 60 * 60;
    actual_slow = resp_features.resp.lungs.rate_slow_window_bpm(endpoint);
    actual_rapid = resp_features.resp.lungs.rate_rapid_window_bpm(endpoint);

    verifyEqual(testCase, expected, 4.5, 'AbsTol', eps);
    verifyNotEqual(testCase, expected, count_based);
    verifyEqual(testCase, actual_slow, expected, 'AbsTol', eps);
    verifyEqual(testCase, actual_rapid, expected, 'AbsTol', eps);
    verifyTrue(testCase, isequaln( ...
        resp_features.resp.lungs.rate_slow_window_bpm, ...
        resp_features.resp.lungs.rate_rapid_window_bpm));
    verifyEqual(testCase, resp_features.provenance.respiratory_rate_estimator, ...
        '60_over_mean_complete_ibi_in_full_trailing_window');
end

function testRateWindowRequiresFullHistoryAndAtLeastTwoValidIbis(testCase)
    [data, resp_cycles, resp_ref, diagnostics_desat, config] = ...
        rate_only_feature_fixture([10; 30; 50], 120);
    resp_features = compute_respiratory_features( ...
        data, resp_cycles, resp_ref, config);
    t_grid = resp_features.resp.time_sec;
    verifyTrue(testCase, all(isnan( ...
        resp_features.resp.lungs.rate_slow_window_bpm(t_grid < 60))));
    verifyTrue(testCase, all(isnan( ...
        resp_features.resp.lungs.rate_rapid_window_bpm(t_grid < 60))));

    [data, resp_cycles, resp_ref, diagnostics_desat, config] = ...
        rate_only_feature_fixture([10; 50], 120);
    resp_features = compute_respiratory_features( ...
        data, resp_cycles, resp_ref, config);
    endpoint = resp_features.resp.time_sec == 60;
    verifyTrue(testCase, isnan( ...
        resp_features.resp.lungs.rate_slow_window_bpm(endpoint)));
    verifyTrue(testCase, isnan( ...
        resp_features.resp.lungs.rate_rapid_window_bpm(endpoint)));

    [data, resp_cycles, resp_ref, diagnostics_desat, config] = ...
        rate_only_feature_fixture([10; 10; 50], 120);
    resp_features = compute_respiratory_features( ...
        data, resp_cycles, resp_ref, config);
    endpoint = resp_features.resp.time_sec == 60;
    verifyTrue(testCase, isnan( ...
        resp_features.resp.lungs.rate_slow_window_bpm(endpoint)));
end

function testRapidWindowDefaultsCannotRevertToThirtySeconds(testCase)
    config = make_test_config();
    config.rapid = rmfield(config.rapid, 'analysis_win_sec');
    [data, resp_cycles, resp_ref, diagnostics_desat, config] = ...
        rate_only_feature_fixture((0:2:80)', 100, config);
    resp_features = compute_respiratory_features( ...
        data, resp_cycles, resp_ref, config);
    verifyEqual(testCase, resp_features.resp.rate_windows_sec.rapid, 60);

    repo_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    files = {fullfile(repo_root, 'src', 'feature_extraction', ...
        'compute_respiratory_features.m'), ...
        fullfile(repo_root, 'src', 'label_detection', ...
        'detect_rapid_breathing.m')};
    for i = 1:numel(files)
        source = fileread(files{i});
        verifyEmpty(testCase, regexp(source, ...
            '''rapid'',\s*''analysis_win_sec'',\s*30', 'once'));
    end
end

function testAmplitudeEvidenceMatchesPreviousCalculations(testCase)
    [data, resp_cycles, resp_ref, diagnostics_desat, config] = feature_fixture();
    resp_features = compute_respiratory_features( ...
        data, resp_cycles, resp_ref, config);
    t_grid = resp_features.resp.time_sec;

    expected_shallow = legacy_amplitude_band_mask( ...
        resp_cycles.lungs, t_grid, config.shallow.analysis_win_sec, 2, ...
        config.shallow.amp_ratio_low, config.shallow.amp_ratio_high);
    expected_apnea = legacy_apnea_ratio_trace( ...
        resp_cycles.lungs, t_grid, config.apnea.amp_analysis_win_sec, 2);

    verifyEqual(testCase, resp_features.resp.lungs.shallow_amplitude_mask, expected_shallow);
    verifyTrue(testCase, isequaln( ...
        resp_features.resp.lungs.apnea_amp_ratio_session_window_median, expected_apnea));
    verifyEqual(testCase, resp_features.resp.lungs.amp_ratio_global, ...
        expected_global_ratio(resp_cycles.lungs.amp, 1.5));
end

function testUnavailableSessionReferenceDoesNotUseGlobal(testCase)
    [data, resp_cycles, resp_ref, diagnostics_desat, config] = feature_fixture();
    resp_ref.lungs.session.value = NaN;
    resp_ref.lungs.session.available = false;
    resp_ref.lungs.reference_quality = 'insufficient_breaths';
    resp_features = compute_respiratory_features( ...
        data, resp_cycles, resp_ref, config);

    verifyFalse(testCase, resp_features.resp.lungs.session_reference_available);
    verifyTrue(testCase, resp_features.resp.lungs.global_reference_available);
    verifyTrue(testCase, all(isnan(resp_features.resp.lungs.amp_ratio_session)));
    verifyTrue(testCase, any(isfinite(resp_features.resp.lungs.amp_ratio_global)));
    verifyEqual(testCase, resp_features.resp.lungs.reference_quality, 'insufficient_breaths');
end

function testDiagnosticSignalsReusePhysiologicalEvidence(testCase)
    [data, resp_cycles, resp_ref, diagnostics_desat, config] = feature_fixture();
    resp_features = compute_respiratory_features( ...
        data, resp_cycles, resp_ref, config);
    spo2_ref = struct('median_percent', 96);
    rea = synthetic_rea_metrics(resp_features.resp.time_sec);
    diagnostic = compute_label_diagnostic_signals( ...
        resp_features, spo2_ref, diagnostics_desat, config, rea);

    verifyEqual(testCase, diagnostic.breathing_rate_slow_window_bpm_lungs, ...
        resp_features.resp.lungs.rate_slow_window_bpm);
    verifyEqual(testCase, diagnostic.breathing_rate_rapid_window_bpm_diaph, ...
        resp_features.resp.diaph.rate_rapid_window_bpm);
    verifyEqual(testCase, diagnostic.irregularity_robust_cov_lungs, ...
        resp_features.resp.lungs.irregularity.robust_cov);
    verifyEqual(testCase, diagnostic.breath_amplitude_ratio_to_reference_diaph, ...
        resp_features.resp.diaph.amp_ratio_session_window_median);
    verifyEqual(testCase, diagnostic.breath_amplitude_median_raw_units_lungs, ...
        resp_features.resp.lungs.amp_window_median_raw_units);
end

function testShallowAndApneaEventsMatchDerivedEvidence(testCase)
    [data, resp_cycles, resp_ref, diagnostics_desat, config] = feature_fixture();
    config.apnea.raw_flat_enabled = false;

    resp_features = compute_respiratory_features( ...
        data, resp_cycles, resp_ref, config);
    [actual_shallow, shallow_boundary] = detect_shallow_breathing(data, resp_features, config);
    t_grid = resp_features.resp.time_sec;
    expected_lungs_mask = legacy_amplitude_band_mask( ...
        resp_cycles.lungs, t_grid, config.shallow.analysis_win_sec, 2, ...
        config.shallow.amp_ratio_low, config.shallow.amp_ratio_high);
    expected_diaph_mask = legacy_amplitude_band_mask( ...
        resp_cycles.diaph, t_grid, config.shallow.analysis_win_sec, 4, ...
        config.shallow.amp_ratio_low, config.shallow.amp_ratio_high);
    [expected_lungs, ~] = sustained_condition_to_events( ...
        expected_lungs_mask, t_grid, config.fs, size(data,1), ...
        config.shallow.min_dur_sec, 'shallow_breathing_lungs');
    [expected_diaph, ~] = sustained_condition_to_events( ...
        expected_diaph_mask, t_grid, config.fs, size(data,1), ...
        config.shallow.min_dur_sec, 'shallow_breathing_diaph');
    expected_shallow = merge_events({expected_lungs, expected_diaph});
    verifyLocalizedEventEvidence(testCase, actual_shallow, expected_shallow, shallow_boundary);

    low_lungs = resp_cycles.lungs.peak_t >= 300 & resp_cycles.lungs.peak_t <= 350;
    low_diaph = resp_cycles.diaph.peak_t >= 300 & resp_cycles.diaph.peak_t <= 350;
    resp_cycles.lungs.amp(low_lungs) = 0.1;
    resp_cycles.diaph.amp(low_diaph) = 0.2;
    resp_features = compute_respiratory_features( ...
        data, resp_cycles, resp_ref, config);
    session_reference = get_session_reference_interval(size(data,1), config);
    [actual_apnea, ~, apnea_boundary] = detect_apnea( ...
        data, resp_features, session_reference, config);

    endpoint = resp_features.resp.lungs.apnea_amplitude_endpoint_mask & ...
        resp_features.resp.diaph.apnea_amplitude_endpoint_mask;
    peak_mask = analysis_window_endpoints_to_state_mask( ...
        endpoint, t_grid, config.apnea.amp_analysis_win_sec);
    [expected_apnea, ~] = sustained_condition_to_events( ...
        peak_mask, t_grid, config.fs, size(data,1), ...
        config.apnea.min_dur_sec, 'apnea');
    verifyLocalizedEventEvidence(testCase, actual_apnea, expected_apnea, apnea_boundary);
end

function testMigratedDetectorsDoNotOwnPeakDetectionOrReferenceDivision(testCase)
    repo_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    detector_files = { ...
        'detect_shallow_breathing.m', ...
        'detect_deep_breathing.m', ...
        'detect_slow_breathing.m', ...
        'detect_rapid_breathing.m', ...
        'detect_irregular_breathing.m', ...
        'detect_apnea.m', ...
        'detect_sigh.m'};
    for i = 1:numel(detector_files)
        source = fileread(fullfile(repo_root, 'src', 'label_detection', detector_files{i}));
        verifyFalse(testCase, contains(source, 'extract_respiration_feature('));
        verifyFalse(testCase, contains(source, 'findpeaks('));
        verifyFalse(testCase, contains(source, 'get_resp_session_reference('));
        verifyFalse(testCase, contains(source, 'get_resp_ref_on_grid('));
    end
    verifyFalse(testCase, isfile(fullfile(repo_root, 'src', 'label_detection', ...
        'compute_shallow_breathing_mask.m')));
    verifyFalse(testCase, isfile(fullfile(repo_root, 'src', 'label_detection', ...
        'compute_amplitude_band_mask.m')));
    main_source = fileread(fullfile(repo_root, 'src', 'main_single.m'));
    verifyTrue(testCase, contains(main_source, ...
        'resp_features = compute_respiratory_features('));
    verifyTrue(testCase, contains(main_source, ...
        'results.resp_features = resp_features;'));
end

function verifyEventEvidenceEqual(testCase, actual, expected)
    verifyEqual(testCase, string({actual.type})', string({expected.type})');
    verifyEqual(testCase, [actual.start_idx]', [expected.start_idx]');
    verifyEqual(testCase, [actual.end_idx]', [expected.end_idx]');
end

function verifyLocalizedEventEvidence(testCase, actual, expected, boundary)
    verifyEqual(testCase, string({actual.type})', string({expected.type})');
    verifyNumElements(testCase, boundary.events, numel(expected));
    verifyEqual(testCase, [boundary.events.candidate_start_t]', [expected.start_t]');
    verifyEqual(testCase, [boundary.events.candidate_end_t]', [expected.end_t]');
    verifyGreaterThanOrEqual(testCase, [actual.start_t]', [expected.start_t]');
    verifyLessThanOrEqual(testCase, [actual.end_t]', [expected.end_t]');
end

function [data, resp_cycles, resp_ref, diagnostics_desat, config] = feature_fixture()
    config = make_test_config();
    config.fs = 10;
    config.grid_step_sec = 1;
    config.subject = 999;
    config.measure = 1;
    config.problems.missing_lung_belt = zeros(0, 2);
    config.irregular.rmssd_thr = 0.2;
    N = 5001;
    data = zeros(N, 6);

    peak_t_l = (0:4:480)';
    peak_idx_l = round(peak_t_l * config.fs) + 1;
    amp_l = 2 * ones(size(peak_t_l));
    amp_l(peak_t_l >= 200 & peak_t_l <= 240) = 1.4;
    amp_l(end) = NaN;
    resp_cycles.lungs = reviewed_belt(peak_idx_l, peak_t_l, amp_l, config.fs);

    peak_t_d = (1:5:481)';
    peak_idx_d = round(peak_t_d * config.fs) + 1;
    amp_d = 2 * ones(size(peak_t_d));
    amp_d(end) = NaN;
    resp_cycles.diaph = reviewed_belt(peak_idx_d, peak_t_d, amp_d, config.fs);

    resp_ref = struct();
    resp_ref.lungs = belt_reference(2, 1.5, 'good');
    resp_ref.diaph = belt_reference(4, 2.5, 'edge_disagreement');

    diagnostics_desat = struct();
    diagnostics_desat.time_sec = (0:N-1)' / config.fs;
    diagnostics_desat.spo2 = 96 * ones(N, 1);
    diagnostics_desat.events = empty_events();
    diagnostics_desat.signal_available = true;
    diagnostics_desat.reference_available = true;
    diagnostics_desat.reference_quality = 'good';
    diagnostics_desat.detection_available = true;
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

function reference = belt_reference(session_value, global_value, quality)
    reference = struct( ...
        'session', struct('value', session_value, 'available', true), ...
        'global', struct('value', global_value, 'available', true), ...
        'reference_quality', quality);
end

function trace = ibi_rate_trace_reference(peak_t, t_grid, win_sec)
    trace = nan(size(t_grid));
    peak_t = peak_t(:);
    for i = 1:numel(t_grid)
        t = t_grid(i);
        lb = t - win_sec;
        if lb < 0
            continue;
        end
        idx = find(isfinite(peak_t) & peak_t >= lb & peak_t <= t);
        if numel(idx) < 3
            continue;
        end
        ibi = diff(peak_t(idx));
        ibi = ibi(isfinite(ibi) & ibi > 0);
        if numel(ibi) >= 2
            trace(i) = 60 / mean(ibi);
        end
    end
end

function [data, resp_cycles, resp_ref, diagnostics_desat, config] = ...
    rate_only_feature_fixture(peak_t, duration_sec, config)

    if nargin < 3
        config = make_test_config();
    end
    config.fs = 10;
    config.grid_step_sec = 1;
    config.subject = 999;
    config.measure = 1;
    config.problems.missing_lung_belt = zeros(0, 2);
    N = duration_sec * config.fs + 1;
    data = zeros(N, 6);
    peak_idx = round(peak_t * config.fs) + 1;
    resp_cycles = struct( ...
        'lungs', reviewed_belt(peak_idx, peak_t, ones(size(peak_t)), config.fs), ...
        'diaph', empty_respiration_feature('Resp-Diaphragm'));
    resp_ref = struct( ...
        'lungs', belt_reference(1, 1, 'good'), ...
        'diaph', belt_reference(NaN, NaN, 'belt_unavailable'));
    diagnostics_desat = struct();
end

function mask = legacy_amplitude_band_mask(breaths, t_grid, win_sec, reference, lo, hi)
    mask = false(size(t_grid));
    peak_t = breaths.peak_t(:);
    amp = breaths.amp(:);
    n = min(numel(peak_t), numel(amp));
    peak_t = peak_t(1:n);
    amp = amp(1:n);
    for i = 1:numel(t_grid)
        t = t_grid(i);
        lb = t - win_sec;
        if lb < 0
            continue;
        end
        values = amp(peak_t <= t & peak_t >= lb);
        if numel(values) >= 3 && all(isfinite(values) & ...
                values >= reference * lo & values <= reference * hi)
            mask(t_grid >= lb & t_grid <= t) = true;
        end
    end
end

function trace = legacy_apnea_ratio_trace(breaths, t_grid, win_sec, reference)
    peak_t = breaths.peak_t(:);
    amp = breaths.amp(:);
    n = min(numel(peak_t), numel(amp));
    peak_t = peak_t(1:n);
    amp = amp(1:n);
    valid = isfinite(peak_t) & isfinite(amp) & amp > 0;
    peak_t = peak_t(valid);
    amp = amp(valid);
    trace = nan(size(t_grid));
    for i = 1:numel(t_grid)
        t = t_grid(i);
        if t - win_sec < 0
            continue;
        end
        values = amp(peak_t <= t & peak_t >= t-win_sec);
        if numel(values) >= 2
            trace(i) = median(values, 'omitnan') / reference;
        end
    end
end

function ratio = expected_global_ratio(amp, reference)
    ratio = nan(size(amp));
    valid = isfinite(amp) & amp > 0;
    ratio(valid) = amp(valid) / reference;
end

function rea = synthetic_rea_metrics(t_grid)
    z = nan(size(t_grid));
    rea = struct( ...
        'analysis_fs', 20, ...
        'analysis_n_samples', numel(t_grid), ...
        'valid_analysis', false, ...
        'skip_code', 1, ...
        'min_dur_sec', 30, ...
        'low_mid_cut_hz', 0.145, ...
        'mid_high_cut_hz', 0.6, ...
        'min_deviating_bins', 1, ...
        'min_abs_drop', 0.15, ...
        'reference_mad_k', 3, ...
        'phase_coherence_high', z, ...
        'phase_coherence_mid', z, ...
        'phase_coherence_low', z, ...
        'deviation_bin_count', z, ...
        'low_coherence_mask', false(size(t_grid)), ...
        'reference_mask', false(size(t_grid)), ...
        'references', struct('high', NaN, 'mid', NaN, 'low', NaN), ...
        'thresholds', struct('high', NaN, 'mid', NaN, 'low', NaN));
end
