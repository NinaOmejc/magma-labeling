function summary = build_label_evidence_summary( ...
    label_names, label_available, reasons, data, resp_features, spo2_ref, ...
    detector_diagnostics, label_burden, config, annotation_mask, annotation_events)
% BUILD_LABEL_EVIDENCE_SUMMARY Reduce detector traces to descriptive recording metrics.
% Availability/reasons align with label_names; respiratory and specialized
% diagnostics supply trace summaries; label_burden and annotation_mask/events
% identify the automatic or reviewed annotation layer being summarized.
% summary has version/kind plus one struct per canonical label. Entries retain
% relevant windows/thresholds, finite medians or extrema, threshold margins,
% reference quality, supporting belts/signals, event burden, and detector-
% specific counts; unavailable statistics remain NaN.

    label_names = cellstr(string(label_names));
    validate_annotation_layer(annotation_mask, annotation_events, ...
        size(data, 1), label_names);
    summary = struct('version', 'detector_specific_evidence_summary_v5', ...
        'kind', 'descriptive_detector_evidence');
    for i = 1:numel(label_names)
        summary.(label_names{i}) = struct( ...
            'available', logical(label_available(i)), ...
            'availability_reason', reasons{i});
    end

    lungs = resp_features.lungs;
    diaph = resp_features.diaph;
    shallow_mask = label_column(annotation_mask, label_names, 'shallow');
    deep_mask = label_column(annotation_mask, label_names, 'deep');
    slow_mask = label_column(annotation_mask, label_names, 'slow');
    rapid_mask = label_column(annotation_mask, label_names, 'rapid');
    irregular_mask = label_column(annotation_mask, label_names, 'irregular');
    apnea_mask = label_column(annotation_mask, label_names, 'apnea');
    sigh_mask = label_column(annotation_mask, label_names, 'sigh');
    thoracic_mask = label_column(annotation_mask, label_names, 'thoracic');
    async_mask = label_column(annotation_mask, label_names, 'async');
    desat_mask = label_column(annotation_mask, label_names, 'desat');

    shallow_lungs = breath_values_in_label( ...
        lungs.amp_ratio_session, lungs.peak_t, shallow_mask, config.fs);
    shallow_diaph = breath_values_in_label( ...
        diaph.amp_ratio_session, diaph.peak_t, shallow_mask, config.fs);
    summary.shallow.ratio_band = resp_features.shallow_band_ratio;
    summary.shallow.median_ratio_lungs = finite_median(shallow_lungs);
    summary.shallow.median_ratio_diaph = finite_median(shallow_diaph);
    summary.shallow.minimum_ratio_lungs = finite_min(shallow_lungs);
    summary.shallow.minimum_ratio_diaph = finite_min(shallow_diaph);
    summary.shallow.reference_quality_lungs = lungs.reference_quality;
    summary.shallow.reference_quality_diaph = diaph.reference_quality;
    summary.shallow.supporting_belts = belt_support( ...
        lungs.session_amplitude_available, diaph.session_amplitude_available);

    deep_lungs = breath_values_in_label( ...
        lungs.amp_ratio_session, lungs.peak_t, deep_mask, config.fs);
    deep_diaph = breath_values_in_label( ...
        diaph.amp_ratio_session, diaph.peak_t, deep_mask, config.fs);
    summary.deep.ratio_threshold = resp_features.deep_ratio_threshold;
    summary.deep.median_ratio_lungs = finite_median(deep_lungs);
    summary.deep.median_ratio_diaph = finite_median(deep_diaph);
    summary.deep.maximum_ratio_lungs = finite_max(deep_lungs);
    summary.deep.maximum_ratio_diaph = finite_max(deep_diaph);
    summary.deep.median_margin_lungs = finite_median( ...
        deep_lungs - resp_features.deep_ratio_threshold);
    summary.deep.median_margin_diaph = finite_median( ...
        deep_diaph - resp_features.deep_ratio_threshold);
    summary.deep.reference_quality_lungs = lungs.reference_quality;
    summary.deep.reference_quality_diaph = diaph.reference_quality;
    summary.deep.supporting_belts = belt_support( ...
        lungs.session_amplitude_available, diaph.session_amplitude_available);

    slow_lungs = grid_values_in_label(lungs.rate_slow_window_bpm, ...
        resp_features.time_sec, slow_mask, config.fs);
    slow_diaph = grid_values_in_label(diaph.rate_slow_window_bpm, ...
        resp_features.time_sec, slow_mask, config.fs);
    summary.slow.analysis_window_sec = resp_features.rate_windows_sec.slow;
    summary.slow.median_rr_lungs = finite_median(slow_lungs);
    summary.slow.median_rr_diaph = finite_median(slow_diaph);
    summary.slow.minimum_rr_lungs = finite_min(slow_lungs);
    summary.slow.minimum_rr_diaph = finite_min(slow_diaph);
    summary.slow.rr_threshold_bpm = config.slow.rr_thr_bpm;
    summary.slow.median_margin_lungs = finite_median( ...
        config.slow.rr_thr_bpm - slow_lungs);
    summary.slow.median_margin_diaph = finite_median( ...
        config.slow.rr_thr_bpm - slow_diaph);
    summary.slow.supporting_belts = belt_support( ...
        any_finite(lungs.rate_slow_window_bpm), any_finite(diaph.rate_slow_window_bpm));

    rapid_lungs = grid_values_in_label(lungs.rate_rapid_window_bpm, ...
        resp_features.time_sec, rapid_mask, config.fs);
    rapid_diaph = grid_values_in_label(diaph.rate_rapid_window_bpm, ...
        resp_features.time_sec, rapid_mask, config.fs);
    summary.rapid.analysis_window_sec = resp_features.rate_windows_sec.rapid;
    summary.rapid.median_rr_lungs = finite_median(rapid_lungs);
    summary.rapid.median_rr_diaph = finite_median(rapid_diaph);
    summary.rapid.maximum_rr_lungs = finite_max(rapid_lungs);
    summary.rapid.maximum_rr_diaph = finite_max(rapid_diaph);
    summary.rapid.rr_threshold_bpm = config.rapid.rr_thr_bpm;
    summary.rapid.median_margin_lungs = finite_median( ...
        rapid_lungs - config.rapid.rr_thr_bpm);
    summary.rapid.median_margin_diaph = finite_median( ...
        rapid_diaph - config.rapid.rr_thr_bpm);
    summary.rapid.supporting_belts = belt_support( ...
        any_finite(lungs.rate_rapid_window_bpm), any_finite(diaph.rate_rapid_window_bpm));

    irregular_cov_lungs = grid_values_in_label(lungs.irregularity.cov, ...
        resp_features.time_sec, irregular_mask, config.fs);
    irregular_cov_diaph = grid_values_in_label(diaph.irregularity.cov, ...
        resp_features.time_sec, irregular_mask, config.fs);
    irregular_robust_lungs = grid_values_in_label( ...
        lungs.irregularity.robust_cov, resp_features.time_sec, ...
        irregular_mask, config.fs);
    irregular_robust_diaph = grid_values_in_label( ...
        diaph.irregularity.robust_cov, resp_features.time_sec, ...
        irregular_mask, config.fs);
    summary.irregular.cov_threshold = config.irregular.cov_thr;
    summary.irregular.median_cov_lungs = finite_median(irregular_cov_lungs);
    summary.irregular.median_cov_diaph = finite_median(irregular_cov_diaph);
    summary.irregular.median_robust_cov_lungs = finite_median(irregular_robust_lungs);
    summary.irregular.median_robust_cov_diaph = finite_median(irregular_robust_diaph);
    summary.irregular.median_cov_margin_lungs = finite_median( ...
        irregular_cov_lungs - config.irregular.cov_thr);
    summary.irregular.median_cov_margin_diaph = finite_median( ...
        irregular_cov_diaph - config.irregular.cov_thr);
    summary.irregular.supporting_belts = belt_support( ...
        any_finite(lungs.irregularity.cov), any_finite(diaph.irregularity.cov));

    balance = resp_features.thoracoabdominal_balance;
    thoracic_T = grid_values_in_label( ...
        balance.thoracic_ratio_window_median, resp_features.time_sec, ...
        thoracic_mask, config.fs);
    thoracic_A = grid_values_in_label( ...
        balance.abdominal_ratio_window_median, resp_features.time_sec, ...
        thoracic_mask, config.fs);
    thoracic_ratio = grid_values_in_label( ...
        balance.thoracic_to_abdominal_ratio, resp_features.time_sec, ...
        thoracic_mask, config.fs);
    thoracic_log_ratio = grid_values_in_label( ...
        balance.thoracic_dominance_log_ratio, resp_features.time_sec, ...
        thoracic_mask, config.fs);
    thoracic_fraction = grid_values_in_label( ...
        balance.thoracic_relative_fraction, resp_features.time_sec, ...
        thoracic_mask, config.fs);
    summary.thoracic.analysis_window_sec = balance.analysis_window_sec;
    summary.thoracic.ratio_threshold = balance.dominance_ratio_threshold;
    summary.thoracic.median_T = finite_median(thoracic_T);
    summary.thoracic.median_A = finite_median(thoracic_A);
    summary.thoracic.median_ratio = finite_median(thoracic_ratio);
    summary.thoracic.median_log_ratio = finite_median(thoracic_log_ratio);
    summary.thoracic.median_relative_fraction = finite_median(thoracic_fraction);
    summary.thoracic.median_ratio_margin = finite_median( ...
        thoracic_ratio - balance.dominance_ratio_threshold);
    summary.thoracic.supporting_belts = 'both';

    rea = detector_diagnostics.async;
    summary.async.analysis_valid = logical(rea.valid_analysis);
    summary.async.reference_available = optional_field( ...
        rea, 'reference_available', false);
    summary.async.reference_quality = optional_field( ...
        rea, 'reference_quality', struct());
    summary.async.skip_code = optional_field(rea, 'skip_code', NaN);
    summary.async.error_message = optional_field(rea, 'error_message', '');
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
        phase_time = optional_field(phase, 'time_sec', resp_features.time_sec);
        absolute_phase = grid_values_in_label( ...
            phase.absolute_mean_phase_deg, phase_time, async_mask, config.fs);
        resultant_length = grid_values_in_label( ...
            phase.resultant_length, phase_time, async_mask, config.fs);
        selected_frequency = grid_values_in_label( ...
            phase.selected_resp_frequency_hz, phase_time, async_mask, config.fs);
        expected_frequency = grid_values_in_label(optional_field( ...
            phase, 'expected_resp_frequency_hz', []), phase_time, ...
            async_mask, config.fs);
        frequency_ratio = grid_values_in_label(optional_field( ...
            phase, 'selected_to_expected_frequency_ratio', []), ...
            phase_time, async_mask, config.fs);
        summary.async.phase_offset_available = phase.available;
        summary.async.median_absolute_phase_deg = ...
            finite_median(absolute_phase);
        summary.async.maximum_absolute_phase_deg = ...
            finite_max(absolute_phase);
        summary.async.median_resultant_length = ...
            finite_median(resultant_length);
        summary.async.median_selected_resp_frequency_hz = ...
            finite_median(selected_frequency);
        summary.async.median_expected_resp_frequency_hz = ...
            finite_median(expected_frequency);
        summary.async.median_selected_to_expected_frequency_ratio = ...
            finite_median(frequency_ratio);
        summary.async.lungs_polarity_multiplier = ...
            optional_field(phase, 'lungs_polarity_multiplier', NaN);
        summary.async.diaph_polarity_multiplier = ...
            optional_field(phase, 'diaph_polarity_multiplier', NaN);
        summary.async.phase_offset_qc = optional_field( ...
            phase, 'cohort_qc', struct());
    end

    spo2 = recording_spo2(data, config);
    spo2_in_desat = values_in_sample_mask(spo2, desat_mask);
    summary.desat.median_spo2_percent = finite_median(spo2_in_desat);
    summary.desat.minimum_spo2_percent = finite_min(spo2_in_desat);
    if isstruct(spo2_ref) && isfield(spo2_ref, 'median_percent') && ...
            isfinite(spo2_ref.median_percent)
        summary.desat.maximum_drop_from_reference_percent = ...
            finite_max(spo2_ref.median_percent - spo2_in_desat);
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
        layer_metrics = matching_desaturation_metrics(optional_field( ...
            desat, 'event_metrics_automatic', struct([])), ...
            annotation_events);
        summary.desat = add_desaturation_metric_summary( ...
            summary.desat, layer_metrics);
    end

    apnea = detector_diagnostics.apnea;
    summary.apnea.amplitude_path_available = apnea.amplitude_path_available;
    summary.apnea.raw_excursion_path_available = apnea.raw_excursion_path_available;
    summary.apnea.amplitude_support_belts = apnea.amplitude_support_belts;
    summary.apnea.raw_excursion_support_belts = apnea.raw_excursion_support_belts;
    summary.apnea.amp_ratio_threshold = config.apnea.amp_ratio_thr;
    summary.apnea.raw_excursion_ratio_threshold = ...
        config.apnea.raw_excursion_ratio_thr;
    apnea_grid_mask = sample_mask_at_times( ...
        apnea_mask, resp_features.time_sec, config.fs);
    summary.apnea.amplitude_supported_fraction = ...
        finite_mean(logical_values_in_mask( ...
            apnea.amplitude_state_mask, apnea_grid_mask));
    summary.apnea.raw_fallback_supported_fraction = ...
        finite_mean(logical_values_in_mask( ...
            apnea.raw_fallback_state_mask, apnea_grid_mask));
    summary.apnea.combined_supported_fraction = ...
        finite_mean(logical_values_in_mask( ...
            apnea.combined_endpoint_mask, apnea_grid_mask));
    apnea_lungs = breath_values_in_label( ...
        lungs.amp_ratio_session, lungs.peak_t, apnea_mask, config.fs);
    apnea_diaph = breath_values_in_label( ...
        diaph.amp_ratio_session, diaph.peak_t, apnea_mask, config.fs);
    summary.apnea.median_amplitude_ratio_lungs = ...
        finite_median(apnea_lungs);
    summary.apnea.median_amplitude_ratio_diaph = ...
        finite_median(apnea_diaph);
    summary.apnea.minimum_amplitude_ratio_lungs = ...
        finite_min(apnea_lungs);
    summary.apnea.minimum_amplitude_ratio_diaph = ...
        finite_min(apnea_diaph);
    summary.apnea.median_raw_excursion_ratio_lungs = finite_median( ...
        evaluable_values_in_label(apnea.raw_excursion.lungs.excursion_ratio, ...
            apnea.raw_excursion.lungs.evaluable_endpoint_mask, apnea_grid_mask));
    summary.apnea.median_raw_excursion_ratio_diaph = finite_median( ...
        evaluable_values_in_label(apnea.raw_excursion.diaph.excursion_ratio, ...
            apnea.raw_excursion.diaph.evaluable_endpoint_mask, apnea_grid_mask));
    summary.apnea.minimum_raw_excursion_ratio_lungs = finite_min( ...
        evaluable_values_in_label(apnea.raw_excursion.lungs.excursion_ratio, ...
            apnea.raw_excursion.lungs.evaluable_endpoint_mask, apnea_grid_mask));
    summary.apnea.minimum_raw_excursion_ratio_diaph = finite_min( ...
        evaluable_values_in_label(apnea.raw_excursion.diaph.excursion_ratio, ...
            apnea.raw_excursion.diaph.evaluable_endpoint_mask, apnea_grid_mask));

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
        finite_median(selected_sigh_ratios( ...
            sigh.lungs, lungs.peak_t, sigh_mask, config.fs));
    summary.sigh.median_amplitude_ratio_diaph = ...
        finite_median(selected_sigh_ratios( ...
            sigh.diaph, diaph.peak_t, sigh_mask, config.fs));
    summary.sigh.maximum_amplitude_ratio_lungs = ...
        finite_max(selected_sigh_ratios( ...
            sigh.lungs, lungs.peak_t, sigh_mask, config.fs));
    summary.sigh.maximum_amplitude_ratio_diaph = ...
        finite_max(selected_sigh_ratios( ...
            sigh.diaph, diaph.peak_t, sigh_mask, config.fs));
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

function values = evaluable_values_in_label(values, evaluable_mask, label_mask)
% EVALUABLE_VALUES_IN_LABEL Select evaluable grid values inside a label.

    values = values(:);
    evaluable_mask = logical(evaluable_mask(:));
    label_mask = logical(label_mask(:));
    if numel(values) ~= numel(evaluable_mask) || ...
            numel(values) ~= numel(label_mask)
        values = zeros(0, 1);
        return;
    end
    values = values(evaluable_mask & label_mask & isfinite(values));
end

function values = selected_sigh_ratios(belt, peak_t, label_mask, fs)
% SELECTED_SIGH_RATIOS Return ratios for annotated, evaluable sigh breaths.

    values = zeros(0, 1);
    required = {'sigh_ratio', 'evaluable_mask'};
    if ~isstruct(belt) || ~all(isfield(belt, required))
        return;
    end
    ratio = belt.sigh_ratio(:);
    evaluable = logical(belt.evaluable_mask(:));
    peak_t = peak_t(:);
    if numel(ratio) ~= numel(evaluable) || numel(ratio) ~= numel(peak_t)
        return;
    end
    annotated = sample_mask_at_times(label_mask, peak_t, fs);
    values = ratio(annotated & evaluable & isfinite(ratio));
end

function validate_annotation_layer(mask, events, n_samples, label_names)
% VALIDATE_ANNOTATION_LAYER Require one mask column per canonical label.

    if ~islogical(mask) && ~isnumeric(mask)
        error('MAGMA:Evidence:InvalidAnnotationMask', ...
            'annotation_mask must be logical or numeric.');
    end
    if ~isequal(size(mask), [n_samples numel(label_names)])
        error('MAGMA:Evidence:AnnotationMaskSize', ...
            'annotation_mask must be Nsample-by-Nlabel.');
    end
    if ~isstruct(events)
        error('MAGMA:Evidence:InvalidAnnotationEvents', ...
            'annotation_events must be a struct array.');
    end
end

function mask = label_column(annotation_mask, label_names, label)
% LABEL_COLUMN Read one canonical label column without reordering it.

    index = find(strcmp(label_names, label), 1);
    if isempty(index)
        error('MAGMA:Evidence:MissingLabel', ...
            'Canonical label %s is missing.', label);
    end
    mask = logical(annotation_mask(:, index));
end

function selected = sample_mask_at_times(sample_mask, time_sec, fs)
% SAMPLE_MASK_AT_TIMES Sample a master-timeline mask at time coordinates.

    time_sec = time_sec(:);
    selected = false(size(time_sec));
    if isempty(time_sec) || isempty(sample_mask)
        return;
    end
    sample_index = round(time_sec * fs) + 1;
    valid = isfinite(time_sec) & sample_index >= 1 & ...
        sample_index <= numel(sample_mask);
    selected(valid) = logical(sample_mask(sample_index(valid)));
end

function values = breath_values_in_label(values, peak_t, label_mask, fs)
% BREATH_VALUES_IN_LABEL Select aligned breath values in labeled periods.

    values = values(:);
    peak_t = peak_t(:);
    if numel(values) ~= numel(peak_t)
        values = zeros(0, 1);
        return;
    end
    selected = sample_mask_at_times(label_mask, peak_t, fs);
    values = values(selected & isfinite(values));
end

function values = grid_values_in_label(values, time_sec, label_mask, fs)
% GRID_VALUES_IN_LABEL Select aligned diagnostic values in labeled periods.

    values = values(:);
    time_sec = time_sec(:);
    if numel(values) ~= numel(time_sec)
        values = zeros(0, 1);
        return;
    end
    selected = sample_mask_at_times(label_mask, time_sec, fs);
    values = values(selected & isfinite(values));
end

function values = values_in_sample_mask(values, sample_mask)
% VALUES_IN_SAMPLE_MASK Select sample-aligned values in a labeled period.

    values = values(:);
    sample_mask = logical(sample_mask(:));
    if numel(values) ~= numel(sample_mask)
        values = zeros(0, 1);
        return;
    end
    values = values(sample_mask & isfinite(values));
end

function values = logical_values_in_mask(values, mask)
% LOGICAL_VALUES_IN_MASK Return logical trace values inside a grid mask.

    values = logical(values(:));
    mask = logical(mask(:));
    if numel(values) ~= numel(mask)
        values = zeros(0, 1);
        return;
    end
    values = values(mask);
end

function selected = matching_desaturation_metrics(metrics, annotation_events)
% MATCHING_DESATURATION_METRICS Keep descriptors for unchanged layer events.
% Manually changed or added events have no detector-derived event descriptor;
% they are intentionally left without an automatic-event severity value.

    selected = metrics([]);
    if isempty(metrics) || isempty(annotation_events) || ...
            ~isfield(annotation_events, 'type')
        return;
    end
    event_types = canonicalize_label_names({annotation_events.type});
    desat_events = annotation_events(strcmp(event_types, 'desat'));
    for i = 1:numel(metrics)
        if ~isfield(metrics, 'start_idx') || ~isfield(metrics, 'end_idx')
            return;
        end
        matches = arrayfun(@(event) ...
            round(event.start_idx) == round(metrics(i).start_idx) && ...
            round(event.end_idx) == round(metrics(i).end_idx), desat_events);
        if any(matches)
            selected(end + 1) = metrics(i); %#ok<AGROW>
        end
    end
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
