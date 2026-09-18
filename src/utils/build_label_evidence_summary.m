function summary = build_label_evidence_summary( ...
    label_names, label_available, reasons, data, resp_features, spo2_ref, ...
    detector_diagnostics, label_burden, config)
% BUILD_LABEL_EVIDENCE_SUMMARY Reduce detector traces to descriptive recording metrics.
% Availability/reasons align with label_names; respiratory and specialized
% diagnostics supply trace summaries; label_burden supplies event burden.
% summary has version/kind plus one struct per canonical label. Entries retain
% relevant windows/thresholds, finite medians or extrema, threshold margins,
% reference quality, supporting belts/signals, event burden, and detector-
% specific counts; unavailable statistics remain NaN.

    label_names = cellstr(string(label_names));
    summary = struct('version', 'detector_specific_evidence_summary_v4', ...
        'kind', 'descriptive_detector_evidence');
    for i = 1:numel(label_names)
        summary.(label_names{i}) = struct( ...
            'available', logical(label_available(i)), ...
            'availability_reason', reasons{i});
    end

    lungs = resp_features.lungs;
    diaph = resp_features.diaph;
    summary.shallow.ratio_band = resp_features.shallow_band_ratio;
    summary.shallow.median_ratio_lungs = finite_median(lungs.amp_ratio_session);
    summary.shallow.median_ratio_diaph = finite_median(diaph.amp_ratio_session);
    summary.shallow.minimum_ratio_lungs = finite_min(lungs.amp_ratio_session);
    summary.shallow.minimum_ratio_diaph = finite_min(diaph.amp_ratio_session);
    summary.shallow.reference_quality_lungs = lungs.reference_quality;
    summary.shallow.reference_quality_diaph = diaph.reference_quality;
    summary.shallow.supporting_belts = belt_support( ...
        lungs.session_amplitude_available, diaph.session_amplitude_available);

    summary.deep.ratio_threshold = resp_features.deep_ratio_threshold;
    summary.deep.median_ratio_lungs = finite_median(lungs.amp_ratio_session);
    summary.deep.median_ratio_diaph = finite_median(diaph.amp_ratio_session);
    summary.deep.maximum_ratio_lungs = finite_max(lungs.amp_ratio_session);
    summary.deep.maximum_ratio_diaph = finite_max(diaph.amp_ratio_session);
    summary.deep.median_margin_lungs = finite_median( ...
        lungs.amp_ratio_session - resp_features.deep_ratio_threshold);
    summary.deep.median_margin_diaph = finite_median( ...
        diaph.amp_ratio_session - resp_features.deep_ratio_threshold);
    summary.deep.reference_quality_lungs = lungs.reference_quality;
    summary.deep.reference_quality_diaph = diaph.reference_quality;
    summary.deep.supporting_belts = belt_support( ...
        lungs.session_amplitude_available, diaph.session_amplitude_available);

    summary.slow.analysis_window_sec = resp_features.rate_windows_sec.slow;
    summary.slow.median_rr_lungs = finite_median(lungs.rate_slow_window_bpm);
    summary.slow.median_rr_diaph = finite_median(diaph.rate_slow_window_bpm);
    summary.slow.minimum_rr_lungs = finite_min(lungs.rate_slow_window_bpm);
    summary.slow.minimum_rr_diaph = finite_min(diaph.rate_slow_window_bpm);
    summary.slow.rr_threshold_bpm = config.slow.rr_thr_bpm;
    summary.slow.median_margin_lungs = finite_median( ...
        config.slow.rr_thr_bpm - lungs.rate_slow_window_bpm);
    summary.slow.median_margin_diaph = finite_median( ...
        config.slow.rr_thr_bpm - diaph.rate_slow_window_bpm);
    summary.slow.supporting_belts = belt_support( ...
        any_finite(lungs.rate_slow_window_bpm), any_finite(diaph.rate_slow_window_bpm));

    summary.rapid.analysis_window_sec = resp_features.rate_windows_sec.rapid;
    summary.rapid.median_rr_lungs = finite_median(lungs.rate_rapid_window_bpm);
    summary.rapid.median_rr_diaph = finite_median(diaph.rate_rapid_window_bpm);
    summary.rapid.maximum_rr_lungs = finite_max(lungs.rate_rapid_window_bpm);
    summary.rapid.maximum_rr_diaph = finite_max(diaph.rate_rapid_window_bpm);
    summary.rapid.rr_threshold_bpm = config.rapid.rr_thr_bpm;
    summary.rapid.median_margin_lungs = finite_median( ...
        lungs.rate_rapid_window_bpm - config.rapid.rr_thr_bpm);
    summary.rapid.median_margin_diaph = finite_median( ...
        diaph.rate_rapid_window_bpm - config.rapid.rr_thr_bpm);
    summary.rapid.supporting_belts = belt_support( ...
        any_finite(lungs.rate_rapid_window_bpm), any_finite(diaph.rate_rapid_window_bpm));

    summary.irregular.cov_threshold = config.irregular.cov_thr;
    summary.irregular.median_cov_lungs = finite_median(lungs.irregularity.cov);
    summary.irregular.median_cov_diaph = finite_median(diaph.irregularity.cov);
    summary.irregular.median_robust_cov_lungs = finite_median(lungs.irregularity.robust_cov);
    summary.irregular.median_robust_cov_diaph = finite_median(diaph.irregularity.robust_cov);
    summary.irregular.median_cov_margin_lungs = finite_median( ...
        lungs.irregularity.cov - config.irregular.cov_thr);
    summary.irregular.median_cov_margin_diaph = finite_median( ...
        diaph.irregularity.cov - config.irregular.cov_thr);
    summary.irregular.supporting_belts = belt_support( ...
        any_finite(lungs.irregularity.cov), any_finite(diaph.irregularity.cov));

    balance = resp_features.thoracoabdominal_balance;
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

    rea = detector_diagnostics.async;
    summary.async.analysis_valid = logical(rea.valid_analysis);
    if isfield(rea, 'primary_method')
        summary.async.primary_method = rea.primary_method;
        summary.async.primary_available = rea.primary_available;
        summary.async.primary_availability_reason = ...
            rea.primary_availability_reason;
        summary.async.comparison = rea.comparison;
    else
        summary.async.primary_method = 'wavelet_coherence_drop';
        summary.async.primary_available = logical(rea.valid_analysis);
        summary.async.primary_availability_reason = '';
    end
    summary.async.reference_coherence = rea.references;
    summary.async.thresholds = rea.thresholds;
    summary.async.median_observed_coherence = struct( ...
        'high', finite_median(rea.phase_coherence_high), ...
        'mid', finite_median(rea.phase_coherence_mid), ...
        'low', finite_median(rea.phase_coherence_low));
    summary.async.maximum_deviating_bins = finite_max(rea.deviation_bin_count);
    if isfield(rea, 'methods') && ...
            isfield(rea.methods, 'wavelet_phase_offset')
        phase = rea.methods.wavelet_phase_offset;
        summary.async.phase_offset_available = phase.available;
        summary.async.median_absolute_phase_deg = ...
            finite_median(phase.absolute_mean_phase_deg);
        summary.async.maximum_absolute_phase_deg = ...
            finite_max(phase.absolute_mean_phase_deg);
        summary.async.median_resultant_length = ...
            finite_median(phase.resultant_length);
        summary.async.median_selected_resp_frequency_hz = ...
            finite_median(phase.selected_resp_frequency_hz);
        summary.async.median_expected_resp_frequency_hz = ...
            finite_median(optional_field( ...
                phase, 'expected_resp_frequency_hz', []));
        summary.async.median_selected_to_expected_frequency_ratio = ...
            finite_median(optional_field( ...
                phase, 'selected_to_expected_frequency_ratio', []));
        summary.async.lungs_polarity_multiplier = ...
            optional_field(phase, 'lungs_polarity_multiplier', NaN);
        summary.async.diaph_polarity_multiplier = ...
            optional_field(phase, 'diaph_polarity_multiplier', NaN);
        summary.async.phase_offset_qc = optional_field( ...
            phase, 'cohort_qc', struct());
    end

    spo2 = recording_spo2(data, config);
    summary.desat.median_spo2_percent = finite_median(spo2);
    summary.desat.minimum_spo2_percent = finite_min(spo2);
    if isstruct(spo2_ref) && isfield(spo2_ref, 'median_percent') && ...
            isfinite(spo2_ref.median_percent)
        summary.desat.maximum_drop_from_reference_percent = ...
            finite_max(spo2_ref.median_percent - spo2);
    else
        summary.desat.maximum_drop_from_reference_percent = NaN;
    end
    summary.desat.duration_sec = label_burden.by_label.desat.duration_sec;
    summary.desat.supporting_signal = 'SpO2';
    if isfield(detector_diagnostics, 'desat')
        desat = detector_diagnostics.desat;
        summary.desat.detection_mode = optional_field( ...
            desat, 'detection_mode', 'legacy');
        summary.desat.absolute_available = optional_field( ...
            desat, 'absolute_available', false);
        summary.desat.relative_available = optional_field( ...
            desat, 'relative_available', false);
        summary.desat = add_desaturation_metric_summary( ...
            summary.desat, optional_field( ...
                desat, 'event_metrics_automatic', struct([])));
    end

    apnea = detector_diagnostics.apnea;
    summary.apnea.amplitude_path_available = apnea.amplitude_path_available;
    summary.apnea.raw_excursion_path_available = apnea.raw_excursion_path_available;
    summary.apnea.amplitude_support_belts = apnea.amplitude_support_belts;
    summary.apnea.raw_excursion_support_belts = apnea.raw_excursion_support_belts;
    summary.apnea.amp_ratio_threshold = config.apnea.amp_ratio_thr;
    summary.apnea.raw_excursion_ratio_threshold = ...
        config.apnea.raw_excursion_ratio_thr;
    summary.apnea.amplitude_supported_fraction = ...
        finite_mean(apnea.amplitude_state_mask);
    summary.apnea.raw_fallback_supported_fraction = ...
        finite_mean(apnea.raw_fallback_state_mask);
    summary.apnea.combined_supported_fraction = ...
        finite_mean(apnea.combined_endpoint_mask);
    summary.apnea.median_amplitude_ratio_lungs = ...
        finite_median(lungs.amp_ratio_session);
    summary.apnea.median_amplitude_ratio_diaph = ...
        finite_median(diaph.amp_ratio_session);
    summary.apnea.minimum_amplitude_ratio_lungs = ...
        finite_min(lungs.amp_ratio_session);
    summary.apnea.minimum_amplitude_ratio_diaph = ...
        finite_min(diaph.amp_ratio_session);
    summary.apnea.median_raw_excursion_ratio_lungs = finite_median( ...
        evaluable_values(apnea.raw_excursion.lungs.excursion_ratio, ...
            apnea.raw_excursion.lungs.evaluable_endpoint_mask));
    summary.apnea.median_raw_excursion_ratio_diaph = finite_median( ...
        evaluable_values(apnea.raw_excursion.diaph.excursion_ratio, ...
            apnea.raw_excursion.diaph.evaluable_endpoint_mask));
    summary.apnea.minimum_raw_excursion_ratio_lungs = finite_min( ...
        evaluable_values(apnea.raw_excursion.lungs.excursion_ratio, ...
            apnea.raw_excursion.lungs.evaluable_endpoint_mask));
    summary.apnea.minimum_raw_excursion_ratio_diaph = finite_min( ...
        evaluable_values(apnea.raw_excursion.diaph.excursion_ratio, ...
            apnea.raw_excursion.diaph.evaluable_endpoint_mask));

    sigh = detector_diagnostics.sigh;
    summary.sigh.method = config.sigh.method;
    summary.sigh.ratio_threshold_lungs = sigh.lungs.decision_threshold;
    summary.sigh.ratio_threshold_diaph = sigh.diaph.decision_threshold;
    summary.sigh.sigh_count = label_burden.sigh_count;
    summary.sigh.sighs_per_15_min = label_burden.sighs_per_15_min;
    summary.sigh.max_sighs_in_any_15_min_window = ...
        label_burden.max_sighs_in_any_15_min_window;
    summary.sigh.median_inter_sigh_interval_sec = ...
        label_burden.median_inter_sigh_interval_sec;
    summary.sigh.minimum_inter_sigh_interval_sec = ...
        label_burden.minimum_inter_sigh_interval_sec;
    summary.sigh.median_amplitude_ratio_lungs = ...
        finite_median(selected_sigh_ratios(sigh.lungs));
    summary.sigh.median_amplitude_ratio_diaph = ...
        finite_median(selected_sigh_ratios(sigh.diaph));
    summary.sigh.maximum_amplitude_ratio_lungs = ...
        finite_max(selected_sigh_ratios(sigh.lungs));
    summary.sigh.maximum_amplitude_ratio_diaph = ...
        finite_max(selected_sigh_ratios(sigh.diaph));
    summary.sigh.supporting_belts = belt_support( ...
        sigh.lungs.available, sigh.diaph.available);

    periodic = detector_diagnostics.periodic;
    summary.periodic.primary_method = periodic.primary_method;
    summary.periodic.eami_available = periodic.eami.available;
    summary.periodic.eami_supporting_belts = belt_support( ...
        periodic.eami.lungs.available, periodic.eami.diaph.available);
    summary.periodic.eami_event_count = periodic.eami.event_count;
    summary.periodic.eami_event_duration_sec = periodic.eami.event_duration_sec;
    eami_values = [periodic.eami.lungs.index(:); ...
        periodic.eami.diaph.index(:)];
    summary.periodic.eami_max = finite_max(eami_values);
    summary.periodic.eami_median = finite_median(eami_values);

    summary.periodic.guyot_available = periodic.guyot.available;
    summary.periodic.guyot_supporting_belts = belt_support( ...
        periodic.guyot.lungs.available, periodic.guyot.diaph.available);
    summary.periodic.guyot_event_count = periodic.guyot.event_count;
    summary.periodic.guyot_event_duration_sec = periodic.guyot.event_duration_sec;
    guyot_h = [periodic.guyot.lungs.h(:); periodic.guyot.diaph.h(:)];
    guyot_fm = 1000 * [periodic.guyot.lungs.fm_hz(:); ...
        periodic.guyot.diaph.fm_hz(:)];
    summary.periodic.guyot_max_h = finite_max(guyot_h);
    summary.periodic.guyot_median_h = finite_median(guyot_h);
    summary.periodic.guyot_median_fm_hz = finite_median(guyot_fm / 1000);
    summary.periodic.guyot_median_fm_mhz = finite_median(guyot_fm);
end

function values = evaluable_values(values, evaluable_mask)
% EVALUABLE_VALUES Select values whose saved evaluability mask is true.

    values = values(:);
    evaluable_mask = logical(evaluable_mask(:));
    if numel(values) ~= numel(evaluable_mask)
        values = zeros(0, 1);
        return;
    end
    values = values(evaluable_mask & isfinite(values));
end

function values = selected_sigh_ratios(belt)
% SELECTED_SIGH_RATIOS Return ratios for detected, evaluable sigh breaths only.

    values = zeros(0, 1);
    required = {'sigh_ratio', 'sigh_flags', 'evaluable_mask'};
    if ~isstruct(belt) || ~all(isfield(belt, required))
        return;
    end
    ratio = belt.sigh_ratio(:);
    selected = logical(belt.sigh_flags(:));
    evaluable = logical(belt.evaluable_mask(:));
    if numel(ratio) ~= numel(selected) || numel(ratio) ~= numel(evaluable)
        return;
    end
    values = ratio(selected & evaluable & isfinite(ratio));
end

function summary = add_desaturation_metric_summary(summary, metrics)
% ADD_DESATURATION_METRIC_SUMMARY Aggregate event descriptors for the recording.
% The event-level authoritative copy remains in detector diagnostics.

    summary.event_metric_count = numel(metrics);
    summary.minimum_event_nadir_spo2_percent = NaN;
    summary.median_event_session_drop_pp = NaN;
    summary.median_event_local_drop_pp = NaN;
    summary.recovery_observed_count = 0;
    summary.absolute_supported_event_count = 0;
    summary.relative_supported_event_count = 0;
    if isempty(metrics)
        return;
    end

    summary.minimum_event_nadir_spo2_percent = ...
        finite_min([metrics.nadir_spo2_percent]);
    summary.median_event_session_drop_pp = ...
        finite_median([metrics.session_drop_pp]);
    summary.median_event_local_drop_pp = ...
        finite_median([metrics.local_drop_pp]);
    summary.recovery_observed_count = nnz([metrics.recovery_observed]);
    summary.absolute_supported_event_count = nnz( ...
        [metrics.absolute_support_fraction] > 0);
    relative_support = [metrics.relative_support_fraction];
    summary.relative_supported_event_count = nnz( ...
        isfinite(relative_support) & relative_support > 0);
end

function value = optional_field(source, name, default_value)
% OPTIONAL_FIELD Return a diagnostic field when present.

    value = default_value;
    if isstruct(source) && isfield(source, name)
        value = source.(name);
    end
end

function spo2 = recording_spo2(data, config)
% RECORDING_SPO2 Read the authoritative recording signal without persisting it.

    spo2 = [];
    if ~isfield(config, 'channels')
        config = resolve_signal_channels(config);
    end
    index = config.channels.spo2_idx;
    if ~isempty(index) && index <= size(data, 2)
        spo2 = data(:, index);
    end
end

function value = finite_median(x)
% FINITE_MEDIAN Return the median of finite values, or NaN when none exist.

    x = x(isfinite(x));
    if isempty(x), value = NaN; else, value = median(x, 'omitnan'); end
end
function value = finite_mean(x)
% FINITE_MEAN Return the mean of finite values, or NaN when none exist.

    x = double(x(:)); x = x(isfinite(x));
    if isempty(x), value = NaN; else, value = mean(x, 'omitnan'); end
end
function value = finite_min(x)
% FINITE_MIN Return the minimum finite value, or NaN when none exist.

    x = x(isfinite(x));
    if isempty(x), value = NaN; else, value = min(x); end
end
function value = finite_max(x)
% FINITE_MAX Return the maximum finite value, or NaN when none exist.

    x = x(isfinite(x));
    if isempty(x), value = NaN; else, value = max(x); end
end
function tf = any_finite(x)
% ANY_FINITE Test whether an array contains at least one finite value.

    tf = any(isfinite(x(:)));
end
function belt = belt_support(lungs, diaph)
% BELT_SUPPORT Encode two evidence flags as 'both', one belt name, or ''.

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
