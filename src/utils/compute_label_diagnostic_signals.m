function diagnostic_signals = compute_label_diagnostic_signals( ...
    resp_features, spo2_ref, diagnostics_desat, config, rea_metrics, apnea_metrics, sigh_metrics, csr_metrics)
% COMPUTE_LABEL_DIAGNOSTIC_SIGNALS Compute label diagnostic signals.
%
% Syntax:
%   diagnostic_signals = compute_label_diagnostic_signals(resp_features, spo2_ref, diagnostics_desat, config, rea_metrics, apnea_metrics, sigh_metrics, csr_metrics)
%
% Inputs:
%   resp_features - Respiratory-feature structure.
%   spo2_ref - SpO2-reference structure.
%   diagnostics_desat - Detector diagnostic data.
%   config - Pipeline configuration structure.
%   rea_metrics - Input value `rea_metrics`.
%   apnea_metrics - Input value `apnea_metrics`.
%   sigh_metrics - Input value `sigh_metrics`.
%   csr_metrics - Input value `csr_metrics`.
%
% Outputs:
%   diagnostic_signals - Detector diagnostic structure.

    t_grid = resp_features.resp.time_sec;

    rapid_win_sec = resp_features.resp.rate_windows_sec.rapid;
    slow_win_sec = resp_features.resp.rate_windows_sec.slow;
    irregularity_win_sec = get_config_value(config, 'irregular', 'analysis_win_sec', 60);
    amplitude_win_sec = resp_features.resp.amplitude_windows_sec.shallow;
    cov_thr = get_config_value(config, 'irregular', 'cov_thr', 0.3);

    diagnostic_signals = struct();
    diagnostic_signals.time_sec = t_grid;
    diagnostic_signals.grid_step_sec = config.grid_step_sec;
    diagnostic_signals.rapid_bpm_window_sec = rapid_win_sec;
    diagnostic_signals.slow_bpm_window_sec = slow_win_sec;
    diagnostic_signals.rapid_bpm_threshold = config.rapid.rr_thr_bpm;
    diagnostic_signals.slow_bpm_threshold = config.slow.rr_thr_bpm;
    diagnostic_signals.irregularity_window_sec = irregularity_win_sec;
    diagnostic_signals.amplitude_window_sec = amplitude_win_sec;
    diagnostic_signals.irregularity_cov_thr = cov_thr;

    diagnostic_signals.breathing_rate_rapid_window_bpm_lungs = resp_features.resp.lungs.rate_rapid_window_bpm;
    diagnostic_signals.breathing_rate_rapid_window_bpm_diaph = resp_features.resp.diaph.rate_rapid_window_bpm;
    diagnostic_signals.breathing_rate_slow_window_bpm_lungs = resp_features.resp.lungs.rate_slow_window_bpm;
    diagnostic_signals.breathing_rate_slow_window_bpm_diaph = resp_features.resp.diaph.rate_slow_window_bpm;
    diagnostic_signals.rapid_evidence_endpoint_lungs = double(resp_features.resp.lungs.rate_rapid_endpoint_mask);
    diagnostic_signals.rapid_evidence_endpoint_diaph = double(resp_features.resp.diaph.rate_rapid_endpoint_mask);
    diagnostic_signals.rapid_inferred_state_lungs = double(resp_features.resp.lungs.rate_rapid_state_mask);
    diagnostic_signals.rapid_inferred_state_diaph = double(resp_features.resp.diaph.rate_rapid_state_mask);
    diagnostic_signals.slow_evidence_endpoint_lungs = double(resp_features.resp.lungs.rate_slow_endpoint_mask);
    diagnostic_signals.slow_evidence_endpoint_diaph = double(resp_features.resp.diaph.rate_slow_endpoint_mask);
    diagnostic_signals.slow_inferred_state_lungs = double(resp_features.resp.lungs.rate_slow_state_mask);
    diagnostic_signals.slow_inferred_state_diaph = double(resp_features.resp.diaph.rate_slow_state_mask);
    diagnostic_signals.rapid_margin_bpm_lungs = ...
        resp_features.resp.lungs.rate_rapid_window_bpm - config.rapid.rr_thr_bpm;
    diagnostic_signals.rapid_margin_bpm_diaph = ...
        resp_features.resp.diaph.rate_rapid_window_bpm - config.rapid.rr_thr_bpm;
    diagnostic_signals.slow_margin_bpm_lungs = ...
        config.slow.rr_thr_bpm - resp_features.resp.lungs.rate_slow_window_bpm;
    diagnostic_signals.slow_margin_bpm_diaph = ...
        config.slow.rr_thr_bpm - resp_features.resp.diaph.rate_slow_window_bpm;

    diagnostic_signals.irregularity_cov_lungs = resp_features.resp.lungs.irregularity.cov;
    diagnostic_signals.irregularity_robust_cov_lungs = resp_features.resp.lungs.irregularity.robust_cov;
    diagnostic_signals.irregularity_cov_diaph = resp_features.resp.diaph.irregularity.cov;
    diagnostic_signals.irregularity_robust_cov_diaph = resp_features.resp.diaph.irregularity.robust_cov;
    diagnostic_signals.irregularity_evidence_endpoint_lungs = double(resp_features.resp.lungs.irregularity.endpoint_mask);
    diagnostic_signals.irregularity_evidence_endpoint_diaph = double(resp_features.resp.diaph.irregularity.endpoint_mask);
    diagnostic_signals.irregularity_inferred_state_lungs = double(resp_features.resp.lungs.irregularity.window_mask);
    diagnostic_signals.irregularity_inferred_state_diaph = double(resp_features.resp.diaph.irregularity.window_mask);
    diagnostic_signals.irregularity_cov_margin_lungs = ...
        resp_features.resp.lungs.irregularity.cov - cov_thr;
    diagnostic_signals.irregularity_cov_margin_diaph = ...
        resp_features.resp.diaph.irregularity.cov - cov_thr;

    diagnostic_signals.breath_amplitude_median_raw_units_lungs = resp_features.resp.lungs.amp_window_median_raw_units;
    diagnostic_signals.breath_amplitude_median_raw_units_diaph = resp_features.resp.diaph.amp_window_median_raw_units;
    diagnostic_signals.breath_amplitude_session_reference_raw_units_lungs = resp_features.resp.lungs.session_reference_value;
    diagnostic_signals.breath_amplitude_session_reference_raw_units_diaph = resp_features.resp.diaph.session_reference_value;
    diagnostic_signals.breath_amplitude_session_reference_available_lungs = double(resp_features.resp.lungs.session_reference_available);
    diagnostic_signals.breath_amplitude_session_reference_available_diaph = double(resp_features.resp.diaph.session_reference_available);
    diagnostic_signals.breath_amplitude_ratio_to_reference_lungs = resp_features.resp.lungs.amp_ratio_session_window_median;
    diagnostic_signals.breath_amplitude_ratio_to_reference_diaph = resp_features.resp.diaph.amp_ratio_session_window_median;
    diagnostic_signals.deep_breath_amplitude_ratio_to_reference_lungs = resp_features.resp.lungs.deep_amp_ratio_session_window_median;
    diagnostic_signals.deep_breath_amplitude_ratio_to_reference_diaph = resp_features.resp.diaph.deep_amp_ratio_session_window_median;
    diagnostic_signals.shallow_evidence_endpoint_lungs = double(resp_features.resp.lungs.shallow_amplitude_endpoint_mask);
    diagnostic_signals.shallow_evidence_endpoint_diaph = double(resp_features.resp.diaph.shallow_amplitude_endpoint_mask);
    diagnostic_signals.shallow_inferred_state_lungs = double(resp_features.resp.lungs.shallow_amplitude_mask);
    diagnostic_signals.shallow_inferred_state_diaph = double(resp_features.resp.diaph.shallow_amplitude_mask);
    diagnostic_signals.deep_evidence_endpoint_lungs = double(resp_features.resp.lungs.deep_amplitude_endpoint_mask);
    diagnostic_signals.deep_evidence_endpoint_diaph = double(resp_features.resp.diaph.deep_amplitude_endpoint_mask);
    diagnostic_signals.deep_inferred_state_lungs = double(resp_features.resp.lungs.deep_amplitude_mask);
    diagnostic_signals.deep_inferred_state_diaph = double(resp_features.resp.diaph.deep_amplitude_mask);
    diagnostic_signals.deep_margin_ratio_lungs = ...
        resp_features.resp.lungs.deep_amp_ratio_session_window_median - config.deep.amp_ratio_thr;
    diagnostic_signals.deep_margin_ratio_diaph = ...
        resp_features.resp.diaph.deep_amp_ratio_session_window_median - config.deep.amp_ratio_thr;
    diagnostic_signals.shallow_lower_margin_ratio_lungs = ...
        resp_features.resp.lungs.amp_ratio_session_window_median - config.shallow.amp_ratio_low;
    diagnostic_signals.shallow_upper_margin_ratio_lungs = ...
        config.shallow.amp_ratio_high - resp_features.resp.lungs.amp_ratio_session_window_median;
    diagnostic_signals.shallow_lower_margin_ratio_diaph = ...
        resp_features.resp.diaph.amp_ratio_session_window_median - config.shallow.amp_ratio_low;
    diagnostic_signals.shallow_upper_margin_ratio_diaph = ...
        config.shallow.amp_ratio_high - resp_features.resp.diaph.amp_ratio_session_window_median;

    balance = resp_features.resp.thoracoabdominal_balance;
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
        spo2_on_grid(diagnostics_desat, spo2_ref, t_grid);

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
% CYCLE_FIELD Perform the cycle field operation.
%
% Syntax:
%   values = cycle_field(cycles, name)
%
% Inputs:
%   cycles - Input value `cycles`.
%   name - Input value `name`.
%
% Outputs:
%   values - Computed numeric value.

    if isempty(cycles)
        values = [];
    else
        values = [cycles.(name)]';
    end
end

function [spo2_grid, spo2_drop_grid] = spo2_on_grid(diagnostics_desat, spo2_ref, t_grid)
% SPO2_ON_GRID Perform the spo2 on grid operation.
%
% Syntax:
%   [spo2_grid, spo2_drop_grid] = spo2_on_grid(diagnostics_desat, spo2_ref, t_grid)
%
% Inputs:
%   diagnostics_desat - Detector diagnostic data.
%   spo2_ref - SpO2-reference structure.
%   t_grid - Time coordinates in seconds.
%
% Outputs:
%   spo2_grid - Computed output value `spo2_grid`.
%   spo2_drop_grid - Computed output value `spo2_drop_grid`.

    spo2_grid = nan(size(t_grid));
    spo2_drop_grid = nan(size(t_grid));

    if isempty(diagnostics_desat) || ~isstruct(diagnostics_desat) || ...
            ~isfield(diagnostics_desat, 'time_sec') || ...
            ~isfield(diagnostics_desat, 'spo2')
        return;
    end

    t_spo2 = diagnostics_desat.time_sec(:);
    spo2 = diagnostics_desat.spo2(:);
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
% ADD_RESPIRATORY_ASYNCHRONY_DIAGNOSTICS Add respiratory asynchrony diagnostics.
%
% Syntax:
%   diagnostic_signals = add_respiratory_asynchrony_diagnostics(diagnostic_signals, rea)
%
% Inputs:
%   diagnostic_signals - Detector diagnostic data.
%   rea - Input value `rea`.
%
% Outputs:
%   diagnostic_signals - Detector diagnostic structure.

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
