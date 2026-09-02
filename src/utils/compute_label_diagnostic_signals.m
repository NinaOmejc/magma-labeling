function diagnostic_signals = compute_label_diagnostic_signals(phys_feat, baseline, spo2_feat, config, rea_metrics)
% compute_label_diagnostic_signals
% Save detector-adjacent signals on the config.fs master recording timeline.

    t_grid = phys_feat.resp.time_sec;

    rapid_win_sec = phys_feat.resp.rate_windows_sec.rapid;
    slow_win_sec = phys_feat.resp.rate_windows_sec.slow;
    irregularity_win_sec = get_config_value(config, 'IrB', 'min_dur_sec', 60);
    amplitude_win_sec = phys_feat.resp.amplitude_windows_sec.shallow;
    cov_thr = get_config_value(config, 'IrB', 'cov_thr', 0.3);
    robust_cov_thr = get_config_value(config, 'IrB', 'robust_cov_thr', 0.25);
    rmssd_thr = get_config_value(config, 'IrB', 'rmssd_thr', 0.0);
    pause_thr_sec = get_config_value(config, 'IrB', 'pause_thr_sec', 10);
    detection_metric = get_config_value(config, 'IrB', 'detection_metric', 'cov');

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
    diagnostic_signals.irregularity_rmssd_thr_sec = rmssd_thr;
    diagnostic_signals.irregularity_pause_thr_sec = pause_thr_sec;

    diagnostic_signals.breathing_rate_rapid_window_bpm_lungs = phys_feat.resp.lungs.rate_rapid_window_bpm;
    diagnostic_signals.breathing_rate_rapid_window_bpm_diaph = phys_feat.resp.diaph.rate_rapid_window_bpm;
    diagnostic_signals.breathing_rate_slow_window_bpm_lungs = phys_feat.resp.lungs.rate_slow_window_bpm;
    diagnostic_signals.breathing_rate_slow_window_bpm_diaph = phys_feat.resp.diaph.rate_slow_window_bpm;

    diagnostic_signals.irregularity_cov_lungs = phys_feat.resp.lungs.irregularity.cov;
    diagnostic_signals.irregularity_robust_cov_lungs = phys_feat.resp.lungs.irregularity.robust_cov;
    diagnostic_signals.irregularity_rmssd_sec_lungs = phys_feat.resp.lungs.irregularity.rmssd_sec;
    diagnostic_signals.irregularity_cov_diaph = phys_feat.resp.diaph.irregularity.cov;
    diagnostic_signals.irregularity_robust_cov_diaph = phys_feat.resp.diaph.irregularity.robust_cov;
    diagnostic_signals.irregularity_rmssd_sec_diaph = phys_feat.resp.diaph.irregularity.rmssd_sec;

    diagnostic_signals.breath_amplitude_median_raw_units_lungs = phys_feat.resp.lungs.amp_window_median_raw_units;
    diagnostic_signals.breath_amplitude_median_raw_units_diaph = phys_feat.resp.diaph.amp_window_median_raw_units;
    diagnostic_signals.breath_amplitude_session_reference_raw_units_lungs = phys_feat.resp.lungs.session_reference_value;
    diagnostic_signals.breath_amplitude_session_reference_raw_units_diaph = phys_feat.resp.diaph.session_reference_value;
    diagnostic_signals.breath_amplitude_session_reference_available_lungs = double(phys_feat.resp.lungs.session_reference_available);
    diagnostic_signals.breath_amplitude_session_reference_available_diaph = double(phys_feat.resp.diaph.session_reference_available);
    diagnostic_signals.breath_amplitude_ratio_to_reference_lungs = phys_feat.resp.lungs.amp_ratio_session_window_median;
    diagnostic_signals.breath_amplitude_ratio_to_reference_diaph = phys_feat.resp.diaph.amp_ratio_session_window_median;
    diagnostic_signals.deep_breath_amplitude_ratio_to_reference_lungs = phys_feat.resp.lungs.deep_amp_ratio_session_window_median;
    diagnostic_signals.deep_breath_amplitude_ratio_to_reference_diaph = phys_feat.resp.diaph.deep_amp_ratio_session_window_median;

    balance = phys_feat.resp.thoracoabdominal_balance;
    diagnostic_signals.thoracic_dominance_available = double(balance.available);
    diagnostic_signals.thoracic_ratio_window_median = balance.thoracic_ratio_window_median;
    diagnostic_signals.abdominal_ratio_window_median = balance.abdominal_ratio_window_median;
    diagnostic_signals.thoracic_to_abdominal_ratio = balance.thoracic_to_abdominal_ratio;
    diagnostic_signals.thoracic_dominance_log_ratio = balance.thoracic_dominance_log_ratio;
    diagnostic_signals.thoracic_relative_fraction = balance.thoracic_relative_fraction;

    [diagnostic_signals.spo2_percent, diagnostic_signals.spo2_drop_from_baseline_percent] = ...
        spo2_on_grid(spo2_feat, baseline, t_grid);

    if nargin < 5 || isempty(rea_metrics)
        error('MAGMA:Diagnostics:MissingReAMetrics', ...
            'Respiratory-asynchrony diagnostics must be supplied by the specialized ReA computation.');
    end
    diagnostic_signals = add_respiratory_asynchrony_diagnostics(diagnostic_signals, rea_metrics);
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
