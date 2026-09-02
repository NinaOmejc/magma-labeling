function tests = test_physiological_features
% Deterministic regression tests for the common physiological evidence layer.
    tests = functiontests(localfunctions);
end

function testReviewedBreathsAndAlignmentArePreserved(testCase)
    [data, resp_feat, resp_ref, spo2_feat, config] = feature_fixture();
    phys_feat = compute_physiological_features( ...
        data, resp_feat, resp_ref, spo2_feat, config);
    lungs = phys_feat.resp.lungs;

    verifyEqual(testCase, lungs.peak_idx, resp_feat.lungs.peak_idx);
    verifyEqual(testCase, lungs.peak_t, resp_feat.lungs.peak_t);
    verifyEqual(testCase, lungs.amp, resp_feat.lungs.amp);
    verifyEqual(testCase, lungs.ibi, resp_feat.lungs.ibi);
    verifyEqual(testCase, lungs.rr_bpm, resp_feat.lungs.rr_bpm);
    verifyEqual(testCase, numel(lungs.ibi), numel(lungs.peak_t) - 1);
    verifyEqual(testCase, numel(lungs.rr_bpm), numel(lungs.peak_t) - 1);
    verifyTrue(testCase, isnan(lungs.amp(end)));
    verifyFalse(testCase, phys_feat.provenance.redetected_respiratory_peaks);
    verifyEqual(testCase, phys_feat.provenance.breath_source, 'reviewed_resp_feat');
end

function testSessionAndGlobalRatiosHandleInvalidAmplitudes(testCase)
    [data, resp_feat, resp_ref, spo2_feat, config] = feature_fixture();
    resp_feat.lungs.amp(8) = 0;
    resp_feat.lungs.amp(9) = -1;
    resp_feat.lungs.amp(10) = NaN;
    phys_feat = compute_physiological_features( ...
        data, resp_feat, resp_ref, spo2_feat, config);
    lungs = phys_feat.resp.lungs;

    valid = isfinite(resp_feat.lungs.amp) & resp_feat.lungs.amp > 0;
    expected_session = nan(size(resp_feat.lungs.amp));
    expected_session(valid) = resp_feat.lungs.amp(valid) / 2;
    expected_global = nan(size(resp_feat.lungs.amp));
    expected_global(valid) = resp_feat.lungs.amp(valid) / 1.5;

    verifyTrue(testCase, isequaln(lungs.amp_ratio_session, expected_session));
    verifyTrue(testCase, isequaln(lungs.amp_ratio_global, expected_global));
    verifyTrue(testCase, all(isnan(lungs.amp_ratio_session(8:10))));
    verifyTrue(testCase, isnan(lungs.amp_ratio_session(end)));
end

function testBeltsRemainIndependentAndSpo2IsIndependent(testCase)
    [data, resp_feat, resp_ref, spo2_feat, config] = feature_fixture();
    phys_feat = compute_physiological_features( ...
        data, resp_feat, resp_ref, spo2_feat, config);

    verifyEqual(testCase, phys_feat.resp.lungs.session_reference_value, 2);
    verifyEqual(testCase, phys_feat.resp.diaph.session_reference_value, 4);
    verifyEqual(testCase, phys_feat.resp.lungs.amp_ratio_session(1), 1);
    verifyEqual(testCase, phys_feat.resp.diaph.amp_ratio_session(1), 0.5);
    verifyTrue(testCase, phys_feat.resp.both_belts_available);
    verifyTrue(testCase, phys_feat.spo2.available);
    verifyEqual(testCase, phys_feat.spo2.desaturation_events, spo2_feat.desat_events);
    verifyEqual(testCase, sort(fieldnames(phys_feat.spo2)), ...
        sort({'available'; 'desaturation_events'}));
end

function testMissingLungBeltLeavesDiaphragmValid(testCase)
    [data, resp_feat, resp_ref, spo2_feat, config] = feature_fixture();
    config.subject = 1;
    config.measure = 1;
    config.problems.missing_lung_belt = [1 1];
    phys_feat = compute_physiological_features( ...
        data, resp_feat, resp_ref, spo2_feat, config);

    verifyTrue(testCase, phys_feat.resp.lungs.ignored);
    verifyFalse(testCase, phys_feat.resp.lungs.available);
    verifyFalse(testCase, phys_feat.resp.lungs.session_reference_available);
    verifyTrue(testCase, all(isnan(phys_feat.resp.lungs.amp_ratio_session)));
    verifyTrue(testCase, phys_feat.resp.diaph.available);
    verifyTrue(testCase, phys_feat.resp.diaph.session_amplitude_available);
    verifyFalse(testCase, phys_feat.resp.both_belts_available);
end

function testRateAndIrregularityEvidenceMatchesPreviousCalculations(testCase)
    [data, resp_feat, resp_ref, spo2_feat, config] = feature_fixture();
    phys_feat = compute_physiological_features( ...
        data, resp_feat, resp_ref, spo2_feat, config);
    t_grid = phys_feat.resp.time_sec;

    expected_slow = legacy_rate_trace( ...
        resp_feat.lungs.peak_t, t_grid, config.SlB.analysis_win_sec);
    expected_rapid = legacy_rate_trace( ...
        resp_feat.lungs.peak_t, t_grid, config.RaB.min_dur_sec);
    verifyTrue(testCase, isequaln( ...
        phys_feat.resp.lungs.rate_slow_window_bpm, expected_slow));
    verifyTrue(testCase, isequaln( ...
        phys_feat.resp.lungs.rate_rapid_window_bpm, expected_rapid));

    [expected_mask, expected_cov, expected_robust, expected_rmssd, expected_endpoint] = ...
        compute_irregularity_metrics(resp_feat.lungs, t_grid, ...
        config.IrB.min_dur_sec, config.IrB.cov_thr, ...
        config.IrB.robust_cov_thr, config.IrB.rmssd_thr, ...
        config.IrB.pause_thr_sec, config.IrB.detection_metric);
    actual = phys_feat.resp.lungs.irregularity;
    verifyTrue(testCase, isequaln(actual.window_mask, expected_mask));
    verifyTrue(testCase, isequaln(actual.endpoint_mask, expected_endpoint));
    verifyTrue(testCase, isequaln(actual.cov, expected_cov));
    verifyTrue(testCase, isequaln(actual.robust_cov, expected_robust));
    verifyTrue(testCase, isequaln(actual.rmssd_sec, expected_rmssd));
end

function testAmplitudeEvidenceMatchesPreviousCalculations(testCase)
    [data, resp_feat, resp_ref, spo2_feat, config] = feature_fixture();
    phys_feat = compute_physiological_features( ...
        data, resp_feat, resp_ref, spo2_feat, config);
    t_grid = phys_feat.resp.time_sec;

    expected_shallow = legacy_amplitude_band_mask( ...
        resp_feat.lungs, t_grid, config.ShB.min_dur_sec, 2, ...
        config.ShB.amp_ratio_low, config.ShB.amp_ratio_high);
    expected_apnea = legacy_apnea_ratio_trace( ...
        resp_feat.lungs, t_grid, config.Apn.min_dur_sec, 2);

    verifyEqual(testCase, phys_feat.resp.lungs.shallow_amplitude_mask, expected_shallow);
    verifyTrue(testCase, isequaln( ...
        phys_feat.resp.lungs.apnea_amp_ratio_session_window_median, expected_apnea));
    verifyEqual(testCase, phys_feat.resp.lungs.amp_ratio_global, ...
        expected_global_ratio(resp_feat.lungs.amp, 1.5));
end

function testUnavailableSessionReferenceDoesNotUseGlobal(testCase)
    [data, resp_feat, resp_ref, spo2_feat, config] = feature_fixture();
    resp_ref.lungs.session.value = NaN;
    resp_ref.lungs.session.available = false;
    resp_ref.lungs.reference_quality = 'insufficient_breaths';
    phys_feat = compute_physiological_features( ...
        data, resp_feat, resp_ref, spo2_feat, config);

    verifyFalse(testCase, phys_feat.resp.lungs.session_reference_available);
    verifyTrue(testCase, phys_feat.resp.lungs.global_reference_available);
    verifyTrue(testCase, all(isnan(phys_feat.resp.lungs.amp_ratio_session)));
    verifyTrue(testCase, any(isfinite(phys_feat.resp.lungs.amp_ratio_global)));
    verifyEqual(testCase, phys_feat.resp.lungs.reference_quality, 'insufficient_breaths');
end

function testDiagnosticSignalsReusePhysiologicalEvidence(testCase)
    [data, resp_feat, resp_ref, spo2_feat, config] = feature_fixture();
    phys_feat = compute_physiological_features( ...
        data, resp_feat, resp_ref, spo2_feat, config);
    baseline = struct('SpO2_median', 96);
    rea = synthetic_rea_metrics(phys_feat.resp.time_sec);
    diagnostic = compute_label_diagnostic_signals( ...
        phys_feat, baseline, spo2_feat, config, rea);

    verifyEqual(testCase, diagnostic.breathing_rate_slow_window_bpm_lungs, ...
        phys_feat.resp.lungs.rate_slow_window_bpm);
    verifyEqual(testCase, diagnostic.breathing_rate_rapid_window_bpm_diaph, ...
        phys_feat.resp.diaph.rate_rapid_window_bpm);
    verifyEqual(testCase, diagnostic.irregularity_robust_cov_lungs, ...
        phys_feat.resp.lungs.irregularity.robust_cov);
    verifyEqual(testCase, diagnostic.breath_amplitude_ratio_to_reference_diaph, ...
        phys_feat.resp.diaph.amp_ratio_session_window_median);
    verifyEqual(testCase, diagnostic.breath_amplitude_median_raw_units_lungs, ...
        phys_feat.resp.lungs.amp_window_median_raw_units);
end

function testShallowAndApneaEventsMatchPreviousEvidence(testCase)
    [data, resp_feat, resp_ref, spo2_feat, config] = feature_fixture();
    config.Apn.raw_flat_enabled = false;

    phys_feat = compute_physiological_features( ...
        data, resp_feat, resp_ref, spo2_feat, config);
    actual_shallow = detect_shallow_breathing(data, phys_feat, config);
    t_grid = phys_feat.resp.time_sec;
    expected_lungs_mask = legacy_amplitude_band_mask( ...
        resp_feat.lungs, t_grid, config.ShB.min_dur_sec, 2, ...
        config.ShB.amp_ratio_low, config.ShB.amp_ratio_high);
    expected_diaph_mask = legacy_amplitude_band_mask( ...
        resp_feat.diaph, t_grid, config.ShB.min_dur_sec, 4, ...
        config.ShB.amp_ratio_low, config.ShB.amp_ratio_high);
    [expected_lungs, ~] = sustained_condition_to_events( ...
        expected_lungs_mask, t_grid, config.fs, size(data,1), ...
        config.ShB.min_dur_sec, 'shallow_breathing_lungs');
    [expected_diaph, ~] = sustained_condition_to_events( ...
        expected_diaph_mask, t_grid, config.fs, size(data,1), ...
        config.ShB.min_dur_sec, 'shallow_breathing_diaph');
    expected_shallow = merge_events({expected_lungs, expected_diaph});
    verifyEventEvidenceEqual(testCase, actual_shallow, expected_shallow);

    low_lungs = resp_feat.lungs.peak_t >= 300 & resp_feat.lungs.peak_t <= 350;
    low_diaph = resp_feat.diaph.peak_t >= 300 & resp_feat.diaph.peak_t <= 350;
    resp_feat.lungs.amp(low_lungs) = 0.1;
    resp_feat.diaph.amp(low_diaph) = 0.2;
    phys_feat = compute_physiological_features( ...
        data, resp_feat, resp_ref, spo2_feat, config);
    actual_apnea = detect_apnea(data, phys_feat, config);

    lungs_ratio = legacy_apnea_ratio_trace( ...
        resp_feat.lungs, t_grid, config.Apn.min_dur_sec, 2);
    diaph_ratio = legacy_apnea_ratio_trace( ...
        resp_feat.diaph, t_grid, config.Apn.min_dur_sec, 4);
    endpoint = isfinite(lungs_ratio) & lungs_ratio <= config.Apn.amp_ratio_thr & ...
        isfinite(diaph_ratio) & diaph_ratio <= config.Apn.amp_ratio_thr;
    [~, peak_mask] = sustained_condition_to_events( ...
        endpoint, t_grid, config.fs, size(data,1), ...
        config.Apn.min_dur_sec, 'apnea');
    [expected_apnea, ~] = sustained_condition_to_events( ...
        peak_mask, t_grid, config.fs, size(data,1), ...
        config.Apn.min_dur_sec, 'apnea');
    verifyEventEvidenceEqual(testCase, actual_apnea, expected_apnea);
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
    verifyTrue(testCase, contains(main_source, 'phys_feat = compute_physiological_features('));
    verifyTrue(testCase, contains(main_source, 'results.phys_feat = phys_feat;'));
end

function verifyEventEvidenceEqual(testCase, actual, expected)
    verifyEqual(testCase, string({actual.type})', string({expected.type})');
    verifyEqual(testCase, [actual.start_idx]', [expected.start_idx]');
    verifyEqual(testCase, [actual.end_idx]', [expected.end_idx]');
end

function [data, resp_feat, resp_ref, spo2_feat, config] = feature_fixture()
    config = make_test_config();
    config.fs = 10;
    config.grid_step_sec = 1;
    config.subject = 999;
    config.measure = 1;
    config.problems.missing_lung_belt = zeros(0, 2);
    config.IrB.rmssd_thr = 0.2;
    N = 5001;
    data = zeros(N, 6);

    peak_t_l = (0:4:480)';
    peak_idx_l = round(peak_t_l * config.fs) + 1;
    amp_l = 2 * ones(size(peak_t_l));
    amp_l(peak_t_l >= 200 & peak_t_l <= 240) = 1.4;
    amp_l(end) = NaN;
    resp_feat.lungs = reviewed_belt(peak_idx_l, peak_t_l, amp_l, config.fs);

    peak_t_d = (1:5:481)';
    peak_idx_d = round(peak_t_d * config.fs) + 1;
    amp_d = 2 * ones(size(peak_t_d));
    amp_d(end) = NaN;
    resp_feat.diaph = reviewed_belt(peak_idx_d, peak_t_d, amp_d, config.fs);

    resp_ref = struct();
    resp_ref.lungs = belt_reference(2, 1.5, 'good');
    resp_ref.diaph = belt_reference(4, 2.5, 'edge_disagreement');

    spo2_feat = struct();
    spo2_feat.t_spo2 = (0:N-1)' / config.fs;
    spo2_feat.spo2 = 96 * ones(N, 1);
    spo2_feat.desat_events = empty_events();
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

function trace = legacy_rate_trace(peak_t, t_grid, win_sec)
    trace = nan(size(t_grid));
    peak_t = peak_t(isfinite(peak_t));
    for i = 1:numel(t_grid)
        t = t_grid(i);
        lb = t - win_sec;
        if lb < 0
            continue;
        end
        n_breaths = sum(peak_t >= lb & peak_t < t);
        if n_breaths >= 2
            trace(i) = n_breaths / win_sec * 60;
        end
    end
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
        'baseline_mad_k', 3, ...
        'phase_coherence_high', z, ...
        'phase_coherence_mid', z, ...
        'phase_coherence_low', z, ...
        'deviation_bin_count', z, ...
        'low_coherence_mask', false(size(t_grid)), ...
        'baseline_mask', false(size(t_grid)), ...
        'baselines', struct('high', NaN, 'mid', NaN, 'low', NaN), ...
        'thresholds', struct('high', NaN, 'mid', NaN, 'low', NaN));
end
