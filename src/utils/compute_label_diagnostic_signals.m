function diagnostic_signals = compute_label_diagnostic_signals(data, baseline, resp_feat, spo2_feat, config, rea_metrics)
% compute_label_diagnostic_signals
% Save detector-adjacent signals on the config.fs master recording timeline.

    N = size(data, 1);
    t_grid = (0:config.grid_step_sec:(N-1)/config.fs)';

    rapid_win_sec = get_config_value(config, 'RaB', 'min_dur_sec', 30);
    slow_win_sec = get_config_value(config, 'SlB', 'analysis_win_sec', 60);
    irregularity_win_sec = get_config_value(config, 'IrB', 'min_dur_sec', 60);
    amplitude_win_sec = get_config_value(config, 'ShB', 'min_dur_sec', 30);
    cov_thr = get_config_value(config, 'IrB', 'cov_thr', 0.3);
    robust_cov_thr = get_config_value(config, 'IrB', 'robust_cov_thr', 0.25);
    rmssd_thr = get_config_value(config, 'IrB', 'rmssd_thr', 0.0);
    pause_thr_sec = get_config_value(config, 'IrB', 'pause_thr_sec', 10);
    detection_metric = get_config_value(config, 'IrB', 'detection_metric', 'robust_cov');

    diagnostic_signals = struct();
    diagnostic_signals.time_sec = t_grid;
    diagnostic_signals.grid_step_sec = config.grid_step_sec;
    diagnostic_signals.rapid_bpm_window_sec = rapid_win_sec;
    diagnostic_signals.slow_bpm_window_sec = slow_win_sec;
    diagnostic_signals.irregularity_window_sec = irregularity_win_sec;
    diagnostic_signals.amplitude_window_sec = amplitude_win_sec;
    diagnostic_signals.irregularity_detection_metric = detection_metric;
    diagnostic_signals.irregularity_cov_thr = cov_thr;
    diagnostic_signals.irregularity_robust_cov_thr = robust_cov_thr;

    diagnostic_signals.breathing_rate_rapid_window_bpm_lungs = breath_rate_trace(resp_feat.lungs, t_grid, rapid_win_sec);
    diagnostic_signals.breathing_rate_rapid_window_bpm_diaph = breath_rate_trace(resp_feat.diaph, t_grid, rapid_win_sec);
    diagnostic_signals.breathing_rate_slow_window_bpm_lungs = breath_rate_trace(resp_feat.lungs, t_grid, slow_win_sec);
    diagnostic_signals.breathing_rate_slow_window_bpm_diaph = breath_rate_trace(resp_feat.diaph, t_grid, slow_win_sec);

    [~, diagnostic_signals.irregularity_cov_lungs, diagnostic_signals.irregularity_robust_cov_lungs, diagnostic_signals.irregularity_rmssd_sec_lungs] = ...
        compute_irregularity_metrics(resp_feat.lungs, t_grid, irregularity_win_sec, cov_thr, robust_cov_thr, rmssd_thr, pause_thr_sec, detection_metric);
    [~, diagnostic_signals.irregularity_cov_diaph, diagnostic_signals.irregularity_robust_cov_diaph, diagnostic_signals.irregularity_rmssd_sec_diaph] = ...
        compute_irregularity_metrics(resp_feat.diaph, t_grid, irregularity_win_sec, cov_thr, robust_cov_thr, rmssd_thr, pause_thr_sec, detection_metric);

    amp_lungs = median_breath_amplitude_on_grid(resp_feat.lungs, t_grid, amplitude_win_sec);
    amp_diaph = median_breath_amplitude_on_grid(resp_feat.diaph, t_grid, amplitude_win_sec);
    ref_lungs = get_resp_ref_on_grid(baseline, 'lungs', t_grid);
    ref_diaph = get_resp_ref_on_grid(baseline, 'diaph', t_grid);

    diagnostic_signals.breath_amplitude_median_lungs = amp_lungs;
    diagnostic_signals.breath_amplitude_median_diaph = amp_diaph;
    diagnostic_signals.breath_amplitude_ratio_to_reference_lungs = amp_lungs ./ ref_lungs;
    diagnostic_signals.breath_amplitude_ratio_to_reference_diaph = amp_diaph ./ ref_diaph;

    [diagnostic_signals.spo2_percent, diagnostic_signals.spo2_drop_from_baseline_percent] = ...
        spo2_on_grid(spo2_feat, baseline, t_grid);

    if nargin < 7 || isempty(rea_metrics)
        rea_metrics = compute_respiratory_asynchrony_metrics(data, resp_feat, config);
    end
    diagnostic_signals = add_respiratory_asynchrony_diagnostics(diagnostic_signals, rea_metrics);
end

function rr_bpm = breath_rate_trace(breaths, t_grid, win_sec)
    rr_bpm = nan(size(t_grid));
    if is_valid_breath_signal(breaths, false)
        [~, rr_bpm] = compute_breath_rate_mask(breaths.peak_t, t_grid, win_sec, nan, '>=', false);
    end
end

function amp_median = median_breath_amplitude_on_grid(breaths, t_grid, win_sec)
    amp_median = nan(size(t_grid));
    if ~is_valid_breath_signal(breaths, true)
        return;
    end

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

        amp_win = amp(peak_t >= lb & peak_t <= t);
        amp_win = amp_win(isfinite(amp_win) & amp_win > 0);
        if ~isempty(amp_win)
            amp_median(i) = median(amp_win, 'omitnan');
        end
    end
end

function [spo2_grid, spo2_drop_grid] = spo2_on_grid(spo2_feat, baseline, t_grid)
    spo2_grid = nan(size(t_grid));
    spo2_drop_grid = nan(size(t_grid));

    if isempty(spo2_feat) || ~isstruct(spo2_feat) || ~isfield(spo2_feat, 't_spo2') || ~isfield(spo2_feat, 'spo2')
        return;
    end

    t_spo2 = spo2_feat.t_spo2(:);
    spo2 = spo2_feat.spo2(:);
    valid = isfinite(t_spo2) & isfinite(spo2);
    if nnz(valid) < 2
        return;
    end

    spo2_grid = interp1(t_spo2(valid), spo2(valid), t_grid, 'linear', nan);
    if isfield(baseline, 'SpO2_median') && isfinite(baseline.SpO2_median)
        spo2_drop_grid = baseline.SpO2_median - spo2_grid;
    end
end

function diagnostic_signals = add_respiratory_asynchrony_diagnostics(diagnostic_signals, rea)
    diagnostic_signals.resp_asynchrony_analysis_fs = rea.analysis_fs;
    diagnostic_signals.resp_asynchrony_analysis_n_samples = rea.analysis_n_samples;
    diagnostic_signals.resp_asynchrony_valid_analysis = double(rea.valid_analysis);
    diagnostic_signals.resp_asynchrony_skip_code = double(rea.skip_code);
    diagnostic_signals.resp_asynchrony_min_dur_sec = rea.min_dur_sec;
    diagnostic_signals.resp_asynchrony_low_mid_cut_hz = rea.low_mid_cut_hz;
    diagnostic_signals.resp_asynchrony_mid_high_cut_hz = rea.mid_high_cut_hz;
    diagnostic_signals.resp_asynchrony_min_deviating_bins = rea.min_deviating_bins;
    diagnostic_signals.resp_asynchrony_min_abs_drop = rea.min_abs_drop;
    diagnostic_signals.resp_asynchrony_baseline_mad_k = rea.baseline_mad_k;

    diagnostic_signals.resp_asynchrony_phase_coherence_high = rea.phase_coherence_high;
    diagnostic_signals.resp_asynchrony_phase_coherence_mid = rea.phase_coherence_mid;
    diagnostic_signals.resp_asynchrony_phase_coherence_low = rea.phase_coherence_low;
    diagnostic_signals.resp_asynchrony_deviation_bin_count = rea.deviation_bin_count;
    diagnostic_signals.resp_asynchrony_low_coherence_mask = double(rea.low_coherence_mask);
    diagnostic_signals.resp_asynchrony_baseline_mask = double(rea.baseline_mask);

    diagnostic_signals.resp_asynchrony_baseline_coherence_high = rea.baselines.high;
    diagnostic_signals.resp_asynchrony_baseline_coherence_mid = rea.baselines.mid;
    diagnostic_signals.resp_asynchrony_baseline_coherence_low = rea.baselines.low;
    diagnostic_signals.resp_asynchrony_threshold_coherence_high = rea.thresholds.high;
    diagnostic_signals.resp_asynchrony_threshold_coherence_mid = rea.thresholds.mid;
    diagnostic_signals.resp_asynchrony_threshold_coherence_low = rea.thresholds.low;
end
