function summary = build_label_evidence_summary( ...
    label_names, label_available, reasons, phys_feat, diagnostic_signals, ...
    detector_diagnostics, label_burden)
% build_label_evidence_summary
% Recording-level descriptive detector evidence. Values retain their native
% physiological scales; no generic confidence or probability is created.

    label_names = cellstr(string(label_names));
    summary = struct('version', 'detector_specific_evidence_summary_v1', ...
        'kind', 'descriptive_detector_evidence');
    for i = 1:numel(label_names)
        summary.(label_names{i}) = struct( ...
            'available', logical(label_available(i)), ...
            'availability_reason', reasons{i});
    end

    lungs = phys_feat.resp.lungs;
    diaph = phys_feat.resp.diaph;
    summary.shallow.analysis_window_sec = phys_feat.resp.amplitude_windows_sec.shallow;
    summary.shallow.ratio_band = phys_feat.resp.shallow_band_ratio;
    summary.shallow.median_ratio_lungs = finite_median(lungs.amp_ratio_session_window_median);
    summary.shallow.median_ratio_diaph = finite_median(diaph.amp_ratio_session_window_median);
    summary.shallow.reference_quality_lungs = lungs.reference_quality;
    summary.shallow.reference_quality_diaph = diaph.reference_quality;
    summary.shallow.supporting_belts = belt_support( ...
        lungs.session_amplitude_available, diaph.session_amplitude_available);

    summary.deep.analysis_window_sec = phys_feat.resp.amplitude_windows_sec.deep;
    summary.deep.ratio_threshold = phys_feat.resp.deep_ratio_threshold;
    summary.deep.median_ratio_lungs = finite_median(lungs.deep_amp_ratio_session_window_median);
    summary.deep.median_ratio_diaph = finite_median(diaph.deep_amp_ratio_session_window_median);
    summary.deep.median_margin_lungs = finite_median( ...
        lungs.deep_amp_ratio_session_window_median - phys_feat.resp.deep_ratio_threshold);
    summary.deep.median_margin_diaph = finite_median( ...
        diaph.deep_amp_ratio_session_window_median - phys_feat.resp.deep_ratio_threshold);
    summary.deep.reference_quality_lungs = lungs.reference_quality;
    summary.deep.reference_quality_diaph = diaph.reference_quality;
    summary.deep.supporting_belts = belt_support( ...
        lungs.session_amplitude_available, diaph.session_amplitude_available);

    summary.slow.analysis_window_sec = phys_feat.resp.rate_windows_sec.slow;
    summary.slow.median_rr_lungs = finite_median(lungs.rate_slow_window_bpm);
    summary.slow.median_rr_diaph = finite_median(diaph.rate_slow_window_bpm);
    summary.slow.rr_threshold_bpm = diagnostic_signals.slow_bpm_threshold;
    summary.slow.median_margin_lungs = finite_median(diagnostic_signals.slow_margin_bpm_lungs);
    summary.slow.median_margin_diaph = finite_median(diagnostic_signals.slow_margin_bpm_diaph);
    summary.slow.supporting_belts = belt_support( ...
        any_finite(lungs.rate_slow_window_bpm), any_finite(diaph.rate_slow_window_bpm));

    summary.rapid.analysis_window_sec = phys_feat.resp.rate_windows_sec.rapid;
    summary.rapid.median_rr_lungs = finite_median(lungs.rate_rapid_window_bpm);
    summary.rapid.median_rr_diaph = finite_median(diaph.rate_rapid_window_bpm);
    summary.rapid.rr_threshold_bpm = diagnostic_signals.rapid_bpm_threshold;
    summary.rapid.median_margin_lungs = finite_median(diagnostic_signals.rapid_margin_bpm_lungs);
    summary.rapid.median_margin_diaph = finite_median(diagnostic_signals.rapid_margin_bpm_diaph);
    summary.rapid.supporting_belts = belt_support( ...
        any_finite(lungs.rate_rapid_window_bpm), any_finite(diaph.rate_rapid_window_bpm));

    summary.irregular.detection_metric = diagnostic_signals.irregularity_detection_metric;
    summary.irregular.cov_threshold = diagnostic_signals.irregularity_cov_thr;
    summary.irregular.robust_cov_threshold = diagnostic_signals.irregularity_robust_cov_thr;
    summary.irregular.median_cov_lungs = finite_median(lungs.irregularity.cov);
    summary.irregular.median_cov_diaph = finite_median(diaph.irregularity.cov);
    summary.irregular.median_selected_metric_lungs = finite_median( ...
        diagnostic_signals.irregularity_selected_metric_lungs);
    summary.irregular.median_selected_metric_diaph = finite_median( ...
        diagnostic_signals.irregularity_selected_metric_diaph);
    summary.irregular.median_selected_margin_lungs = finite_median( ...
        diagnostic_signals.irregularity_selected_margin_lungs);
    summary.irregular.median_selected_margin_diaph = finite_median( ...
        diagnostic_signals.irregularity_selected_margin_diaph);
    summary.irregular.pause_excluded_endpoint_fraction_lungs = finite_mean(lungs.irregularity.pause_exclusion_mask);
    summary.irregular.pause_excluded_endpoint_fraction_diaph = finite_mean(diaph.irregularity.pause_exclusion_mask);
    summary.irregular.supporting_belts = belt_support( ...
        any_finite(lungs.irregularity.cov), any_finite(diaph.irregularity.cov));

    balance = phys_feat.resp.thoracoabdominal_balance;
    summary.thoracic.analysis_window_sec = balance.analysis_window_sec;
    summary.thoracic.ratio_threshold = balance.dominance_ratio_threshold;
    summary.thoracic.median_T = finite_median(balance.thoracic_ratio_window_median);
    summary.thoracic.median_A = finite_median(balance.abdominal_ratio_window_median);
    summary.thoracic.median_ratio = finite_median(balance.thoracic_to_abdominal_ratio);
    summary.thoracic.median_log_ratio = finite_median(balance.thoracic_dominance_log_ratio);
    summary.thoracic.median_relative_fraction = finite_median(balance.thoracic_relative_fraction);
    summary.thoracic.median_ratio_margin = finite_median( ...
        balance.thoracic_to_abdominal_ratio - balance.dominance_ratio_threshold);
    summary.thoracic.supporting_belts = 'both';

    rea = detector_diagnostics.respiratory_asynchrony;
    summary.async.analysis_valid = logical(rea.valid_analysis);
    summary.async.baseline_coherence = rea.baselines;
    summary.async.thresholds = rea.thresholds;
    summary.async.median_observed_coherence = struct( ...
        'high', finite_median(rea.phase_coherence_high), ...
        'mid', finite_median(rea.phase_coherence_mid), ...
        'low', finite_median(rea.phase_coherence_low));
    summary.async.maximum_deviating_bins = finite_max(rea.deviation_bin_count);

    summary.desat.median_spo2_percent = finite_median(diagnostic_signals.spo2_percent);
    summary.desat.minimum_spo2_percent = finite_min(diagnostic_signals.spo2_percent);
    summary.desat.maximum_drop_percent = finite_max(diagnostic_signals.spo2_drop_from_baseline_percent);
    summary.desat.duration_sec = label_burden.by_label.desat.duration_sec;
    summary.desat.supporting_signal = 'SpO2';

    apnea = detector_diagnostics.apnea;
    summary.apnea.peak_path_available = apnea.peak_path_available;
    summary.apnea.raw_flat_path_available = apnea.raw_flat_path_available;
    summary.apnea.peak_support_belts = apnea.peak_support_belts;
    summary.apnea.raw_flat_support_belts = apnea.raw_flat_support_belts;
    summary.apnea.amp_ratio_threshold = apnea.amp_ratio_threshold;
    summary.apnea.peak_supported_fraction = finite_mean(apnea.peak_state_mask);
    summary.apnea.raw_flat_supported_fraction = finite_mean(apnea.raw_flat_state_mask);

    sigh = detector_diagnostics.sigh;
    summary.sigh.method = sigh.method;
    summary.sigh.ratio_threshold_lungs = sigh.lungs.decision_threshold;
    summary.sigh.ratio_threshold_diaph = sigh.diaph.decision_threshold;
    summary.sigh.global_reference_quality_lungs = sigh.lungs.reference_quality;
    summary.sigh.global_reference_quality_diaph = sigh.diaph.reference_quality;
    summary.sigh.sigh_count = label_burden.sigh_count;
    summary.sigh.sighs_per_15_min = label_burden.sighs_per_15_min;
    summary.sigh.supporting_belts = belt_support( ...
        sigh.lungs.available, sigh.diaph.available);

    csr = detector_diagnostics.periodic_breathing;
    summary.csr.minimum_cycles = csr.minimum_cycles;
    summary.csr.minimum_modulation_ratio = csr.minimum_modulation_ratio;
    summary.csr.detected_cycle_count_lungs = numel(csr.lungs.cycles);
    summary.csr.detected_cycle_count_diaph = numel(csr.diaph.cycles);
    summary.csr.median_modulation_ratio_lungs = finite_median(cycle_values(csr.lungs.cycles));
    summary.csr.median_modulation_ratio_diaph = finite_median(cycle_values(csr.diaph.cycles));
    summary.csr.supporting_belts = belt_support( ...
        csr.lungs.analysis_available, csr.diaph.analysis_available);
end

function values = cycle_values(cycles)
    if isempty(cycles), values = []; else, values = [cycles.modulation_ratio]; end
end

function value = finite_median(x)
    x = x(isfinite(x));
    if isempty(x), value = NaN; else, value = median(x, 'omitnan'); end
end
function value = finite_mean(x)
    x = double(x(:)); x = x(isfinite(x));
    if isempty(x), value = NaN; else, value = mean(x, 'omitnan'); end
end
function value = finite_min(x)
    x = x(isfinite(x));
    if isempty(x), value = NaN; else, value = min(x); end
end
function value = finite_max(x)
    x = x(isfinite(x));
    if isempty(x), value = NaN; else, value = max(x); end
end
function tf = any_finite(x)
    tf = any(isfinite(x(:)));
end
function belt = belt_support(lungs, diaph)
    if lungs && diaph
        belt = 'both';
    elseif lungs
        belt = 'lungs';
    elseif diaph
        belt = 'diaph';
    else
        belt = '';
    end
end
