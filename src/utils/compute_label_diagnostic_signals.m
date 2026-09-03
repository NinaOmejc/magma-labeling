function diagnostic_signals = compute_label_diagnostic_signals( ...
    phys_feat, spo2_ref, spo2_feat, config, rea_metrics, apnea_metrics, sigh_metrics, csr_metrics)
% compute_label_diagnostic_signals
% Save detector-adjacent signals on the config.fs master recording timeline.

    t_grid = phys_feat.resp.time_sec;

    rapid_win_sec = phys_feat.resp.rate_windows_sec.rapid;
    slow_win_sec = phys_feat.resp.rate_windows_sec.slow;
    irregularity_win_sec = get_config_value(config, 'IrB', 'analysis_win_sec', 60);
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
    diagnostic_signals.rapid_bpm_threshold = config.RaB.rr_thr_bpm;
    diagnostic_signals.slow_bpm_threshold = config.SlB.rr_thr_bpm;
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
    diagnostic_signals.rapid_evidence_endpoint_lungs = double(phys_feat.resp.lungs.rate_rapid_endpoint_mask);
    diagnostic_signals.rapid_evidence_endpoint_diaph = double(phys_feat.resp.diaph.rate_rapid_endpoint_mask);
    diagnostic_signals.rapid_inferred_state_lungs = double(phys_feat.resp.lungs.rate_rapid_state_mask);
    diagnostic_signals.rapid_inferred_state_diaph = double(phys_feat.resp.diaph.rate_rapid_state_mask);
    diagnostic_signals.slow_evidence_endpoint_lungs = double(phys_feat.resp.lungs.rate_slow_endpoint_mask);
    diagnostic_signals.slow_evidence_endpoint_diaph = double(phys_feat.resp.diaph.rate_slow_endpoint_mask);
    diagnostic_signals.slow_inferred_state_lungs = double(phys_feat.resp.lungs.rate_slow_state_mask);
    diagnostic_signals.slow_inferred_state_diaph = double(phys_feat.resp.diaph.rate_slow_state_mask);
    diagnostic_signals.rapid_margin_bpm_lungs = ...
        phys_feat.resp.lungs.rate_rapid_window_bpm - config.RaB.rr_thr_bpm;
    diagnostic_signals.rapid_margin_bpm_diaph = ...
        phys_feat.resp.diaph.rate_rapid_window_bpm - config.RaB.rr_thr_bpm;
    diagnostic_signals.slow_margin_bpm_lungs = ...
        config.SlB.rr_thr_bpm - phys_feat.resp.lungs.rate_slow_window_bpm;
    diagnostic_signals.slow_margin_bpm_diaph = ...
        config.SlB.rr_thr_bpm - phys_feat.resp.diaph.rate_slow_window_bpm;

    diagnostic_signals.irregularity_cov_lungs = phys_feat.resp.lungs.irregularity.cov;
    diagnostic_signals.irregularity_robust_cov_lungs = phys_feat.resp.lungs.irregularity.robust_cov;
    diagnostic_signals.irregularity_rmssd_sec_lungs = phys_feat.resp.lungs.irregularity.rmssd_sec;
    diagnostic_signals.irregularity_cov_diaph = phys_feat.resp.diaph.irregularity.cov;
    diagnostic_signals.irregularity_robust_cov_diaph = phys_feat.resp.diaph.irregularity.robust_cov;
    diagnostic_signals.irregularity_rmssd_sec_diaph = phys_feat.resp.diaph.irregularity.rmssd_sec;
    diagnostic_signals.irregularity_evidence_endpoint_lungs = double(phys_feat.resp.lungs.irregularity.endpoint_mask);
    diagnostic_signals.irregularity_evidence_endpoint_diaph = double(phys_feat.resp.diaph.irregularity.endpoint_mask);
    diagnostic_signals.irregularity_inferred_state_lungs = double(phys_feat.resp.lungs.irregularity.window_mask);
    diagnostic_signals.irregularity_inferred_state_diaph = double(phys_feat.resp.diaph.irregularity.window_mask);
    diagnostic_signals.irregularity_pause_exclusion_lungs = double(phys_feat.resp.lungs.irregularity.pause_exclusion_mask);
    diagnostic_signals.irregularity_pause_exclusion_diaph = double(phys_feat.resp.diaph.irregularity.pause_exclusion_mask);
    [diagnostic_signals.irregularity_selected_metric_lungs, ...
        diagnostic_signals.irregularity_selected_metric_diaph, ...
        diagnostic_signals.irregularity_selected_margin_lungs, ...
        diagnostic_signals.irregularity_selected_margin_diaph] = ...
        selected_irregularity_evidence(phys_feat, detection_metric, ...
            cov_thr, robust_cov_thr, rmssd_thr);

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
    diagnostic_signals.shallow_evidence_endpoint_lungs = double(phys_feat.resp.lungs.shallow_amplitude_endpoint_mask);
    diagnostic_signals.shallow_evidence_endpoint_diaph = double(phys_feat.resp.diaph.shallow_amplitude_endpoint_mask);
    diagnostic_signals.shallow_inferred_state_lungs = double(phys_feat.resp.lungs.shallow_amplitude_mask);
    diagnostic_signals.shallow_inferred_state_diaph = double(phys_feat.resp.diaph.shallow_amplitude_mask);
    diagnostic_signals.deep_evidence_endpoint_lungs = double(phys_feat.resp.lungs.deep_amplitude_endpoint_mask);
    diagnostic_signals.deep_evidence_endpoint_diaph = double(phys_feat.resp.diaph.deep_amplitude_endpoint_mask);
    diagnostic_signals.deep_inferred_state_lungs = double(phys_feat.resp.lungs.deep_amplitude_mask);
    diagnostic_signals.deep_inferred_state_diaph = double(phys_feat.resp.diaph.deep_amplitude_mask);
    diagnostic_signals.deep_margin_ratio_lungs = ...
        phys_feat.resp.lungs.deep_amp_ratio_session_window_median - config.DeB.amp_ratio_thr;
    diagnostic_signals.deep_margin_ratio_diaph = ...
        phys_feat.resp.diaph.deep_amp_ratio_session_window_median - config.DeB.amp_ratio_thr;
    diagnostic_signals.shallow_lower_margin_ratio_lungs = ...
        phys_feat.resp.lungs.amp_ratio_session_window_median - config.ShB.amp_ratio_low;
    diagnostic_signals.shallow_upper_margin_ratio_lungs = ...
        config.ShB.amp_ratio_high - phys_feat.resp.lungs.amp_ratio_session_window_median;
    diagnostic_signals.shallow_lower_margin_ratio_diaph = ...
        phys_feat.resp.diaph.amp_ratio_session_window_median - config.ShB.amp_ratio_low;
    diagnostic_signals.shallow_upper_margin_ratio_diaph = ...
        config.ShB.amp_ratio_high - phys_feat.resp.diaph.amp_ratio_session_window_median;

    balance = phys_feat.resp.thoracoabdominal_balance;
    diagnostic_signals.thoracic_dominance_available = double(balance.available);
    diagnostic_signals.thoracic_ratio_window_median = balance.thoracic_ratio_window_median;
    diagnostic_signals.abdominal_ratio_window_median = balance.abdominal_ratio_window_median;
    diagnostic_signals.thoracic_to_abdominal_ratio = balance.thoracic_to_abdominal_ratio;
    diagnostic_signals.thoracic_dominance_log_ratio = balance.thoracic_dominance_log_ratio;
    diagnostic_signals.thoracic_relative_fraction = balance.thoracic_relative_fraction;
    diagnostic_signals.thoracic_dominance_endpoint_mask = double(balance.dominance_endpoint_mask);
    diagnostic_signals.thoracic_dominance_state_mask = double(balance.dominance_state_mask);
    diagnostic_signals.thoracic_dominance_ratio_margin = ...
        balance.thoracic_to_abdominal_ratio - balance.dominance_ratio_threshold;

    [diagnostic_signals.spo2_percent, diagnostic_signals.spo2_drop_from_reference_percent] = ...
        spo2_on_grid(spo2_feat, spo2_ref, t_grid);

    if nargin < 5 || isempty(rea_metrics)
        error('MAGMA:Diagnostics:MissingReAMetrics', ...
            'Respiratory-asynchrony diagnostics must be supplied by the specialized ReA computation.');
    end
    diagnostic_signals = add_respiratory_asynchrony_diagnostics(diagnostic_signals, rea_metrics);

    if nargin >= 6 && isstruct(apnea_metrics) && isfield(apnea_metrics, 'available')
        diagnostic_signals.apnea_analysis_available = double(apnea_metrics.available);
        diagnostic_signals.apnea_peak_evidence_endpoint = double(apnea_metrics.peak_endpoint_mask);
        diagnostic_signals.apnea_peak_inferred_state = double(apnea_metrics.peak_state_mask);
        diagnostic_signals.apnea_raw_flat_inferred_state = double(apnea_metrics.raw_flat_state_mask);
        diagnostic_signals.apnea_combined_state = double(apnea_metrics.combined_state_mask);
        diagnostic_signals.apnea_amp_ratio_threshold = apnea_metrics.amp_ratio_threshold;
        if isfield(apnea_metrics, 'raw_flat')
            diagnostic_signals.apnea_raw_lungs_reference_available = ...
                double(apnea_metrics.raw_flat.lungs.reference_available);
            diagnostic_signals.apnea_raw_diaph_reference_available = ...
                double(apnea_metrics.raw_flat.diaph.reference_available);
            diagnostic_signals.apnea_raw_lungs_session_motion_reference = ...
                apnea_metrics.raw_flat.lungs.session_motion_reference;
            diagnostic_signals.apnea_raw_diaph_session_motion_reference = ...
                apnea_metrics.raw_flat.diaph.session_motion_reference;
            diagnostic_signals.apnea_raw_lungs_session_slope_reference = ...
                apnea_metrics.raw_flat.lungs.session_slope_reference;
            diagnostic_signals.apnea_raw_diaph_session_slope_reference = ...
                apnea_metrics.raw_flat.diaph.session_slope_reference;
        end
    end
    if nargin >= 7 && isstruct(sigh_metrics) && isfield(sigh_metrics, 'available')
        diagnostic_signals.sigh_analysis_available = double(sigh_metrics.available);
        diagnostic_signals.sigh_ratio_threshold_lungs = sigh_metrics.lungs.decision_threshold;
        diagnostic_signals.sigh_ratio_threshold_diaph = sigh_metrics.diaph.decision_threshold;
        diagnostic_signals.sigh_selected_count_lungs = nnz(sigh_metrics.lungs.selected_breath_mask);
        diagnostic_signals.sigh_selected_count_diaph = nnz(sigh_metrics.diaph.selected_breath_mask);
    end
    if nargin >= 8 && isstruct(csr_metrics) && isfield(csr_metrics, 'available')
        diagnostic_signals.periodic_analysis_available = double(csr_metrics.available);
        diagnostic_signals.periodic_cycle_count_lungs = numel(csr_metrics.lungs.cycles);
        diagnostic_signals.periodic_cycle_count_diaph = numel(csr_metrics.diaph.cycles);
        diagnostic_signals.periodic_modulation_ratio_lungs = ...
            cycle_field(csr_metrics.lungs.cycles, 'modulation_ratio');
        diagnostic_signals.periodic_modulation_ratio_diaph = ...
            cycle_field(csr_metrics.diaph.cycles, 'modulation_ratio');
    end
end

function values = cycle_field(cycles, name)
    if isempty(cycles)
        values = [];
    else
        values = [cycles.(name)]';
    end
end

function [metric_lungs, metric_diaph, margin_lungs, margin_diaph] = ...
    selected_irregularity_evidence(phys_feat, metric_name, cov_thr, robust_thr, rmssd_thr)

    [metric_lungs, margin_lungs] = selected_for_belt( ...
        phys_feat.resp.lungs.irregularity, metric_name, cov_thr, robust_thr, rmssd_thr);
    [metric_diaph, margin_diaph] = selected_for_belt( ...
        phys_feat.resp.diaph.irregularity, metric_name, cov_thr, robust_thr, rmssd_thr);
end

function [metric, margin] = selected_for_belt(irregularity, metric_name, cov_thr, robust_thr, rmssd_thr)
    cov_margin = irregularity.cov - cov_thr;
    robust_margin = irregularity.robust_cov - robust_thr;
    switch lower(strtrim(char(string(metric_name))))
        case {'robust_cov', 'robust'}
            metric = irregularity.robust_cov;
            margin = robust_margin;
        case 'either'
            metric = max([irregularity.cov(:), irregularity.robust_cov(:)], [], 2, 'omitnan');
            margin = max([cov_margin(:), robust_margin(:)], [], 2, 'omitnan');
        case 'both'
            metric = min([irregularity.cov(:), irregularity.robust_cov(:)], [], 2, 'omitnan');
            margin = min([cov_margin(:), robust_margin(:)], [], 2, 'omitnan');
        otherwise
            metric = irregularity.cov;
            margin = cov_margin;
    end
    if isfinite(rmssd_thr) && rmssd_thr > 0
        rmssd_margin = irregularity.rmssd_sec - rmssd_thr;
        margin = max([margin(:), rmssd_margin(:)], [], 2, 'omitnan');
    end
end

function [spo2_grid, spo2_drop_grid] = spo2_on_grid(spo2_feat, spo2_ref, t_grid)
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
    if isfield(spo2_ref, 'median_percent') && isfinite(spo2_ref.median_percent)
        spo2_drop_grid = spo2_ref.median_percent - spo2_grid;
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
    diagnostic_signals.resp_asynchrony_reference_mad_k = rea.reference_mad_k;

    diagnostic_signals.resp_asynchrony_phase_coherence_high = rea.phase_coherence_high;
    diagnostic_signals.resp_asynchrony_phase_coherence_mid = rea.phase_coherence_mid;
    diagnostic_signals.resp_asynchrony_phase_coherence_low = rea.phase_coherence_low;
    diagnostic_signals.resp_asynchrony_deviation_bin_count = rea.deviation_bin_count;
    diagnostic_signals.resp_asynchrony_low_coherence_mask = double(rea.low_coherence_mask);
    if isfield(rea, 'valid_evidence_mask')
        diagnostic_signals.resp_asynchrony_valid_evidence_mask = ...
            double(rea.valid_evidence_mask);
    else
        diagnostic_signals.resp_asynchrony_valid_evidence_mask = double( ...
            isfinite(rea.phase_coherence_high) | ...
            isfinite(rea.phase_coherence_mid) | ...
            isfinite(rea.phase_coherence_low));
    end
    diagnostic_signals.resp_asynchrony_reference_mask = double(rea.reference_mask);

    diagnostic_signals.resp_asynchrony_reference_coherence_high = rea.references.high;
    diagnostic_signals.resp_asynchrony_reference_coherence_mid = rea.references.mid;
    diagnostic_signals.resp_asynchrony_reference_coherence_low = rea.references.low;
    diagnostic_signals.resp_asynchrony_threshold_coherence_high = rea.thresholds.high;
    diagnostic_signals.resp_asynchrony_threshold_coherence_mid = rea.thresholds.mid;
    diagnostic_signals.resp_asynchrony_threshold_coherence_low = rea.thresholds.low;
end
