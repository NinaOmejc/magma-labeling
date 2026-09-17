function [events_desat, diagnostics_desat, spo2_ref] = detect_desaturation( ...
    data, session_reference, config)
% DETECT_DESATURATION Detect sustained absolute or session-relative low SpO2.
% The absolute branch remains evaluable without a session reference. The
% relative branch is evaluated only from the authoritative session reference.
% Event descriptors are calculated after detection and never alter event
% onset, offset, acceptance, or the combined minimum-duration algorithm.

    if ~isfield(config, 'channels')
        config = resolve_signal_channels(config);
    end

    spo2_ref = compute_spo2_reference(data, session_reference, config);
    events_desat = empty_events();
    diagnostics_desat = empty_desaturation_diagnostics();
    diagnostics_desat.reference_available = valid_spo2_reference(spo2_ref);
    if isstruct(spo2_ref) && isfield(spo2_ref, 'quality')
        diagnostics_desat.reference_quality = char(string(spo2_ref.quality));
    end

    idx_spo2 = config.channels.spo2_idx;
    if isempty(idx_spo2)
        diagnostics_desat.detection_mode = 'unavailable';
        diagnostics_desat.availability_reason = 'missing_spo2_channel';
        fprintf('Skipping desat detection: SpO2 signal is unavailable.\n');
        return;
    end

    spo2 = data(:, idx_spo2);
    valid_sample_mask = isfinite(spo2);
    diagnostics_desat.signal_available = nnz(valid_sample_mask) >= 2;
    diagnostics_desat.absolute_available = diagnostics_desat.signal_available;
    diagnostics_desat.relative_available = ...
        diagnostics_desat.signal_available && ...
        diagnostics_desat.reference_available;
    diagnostics_desat.detection_available = ...
        diagnostics_desat.absolute_available || ...
        diagnostics_desat.relative_available;
    diagnostics_desat.detection_mode = desaturation_detection_mode( ...
        diagnostics_desat.absolute_available, ...
        diagnostics_desat.relative_available);
    if diagnostics_desat.detection_available
        diagnostics_desat.availability_reason = 'available';
    else
        diagnostics_desat.availability_reason = 'insufficient_finite_spo2';
        fprintf('Skipping desat detection: usable SpO2 samples are unavailable.\n');
        return;
    end

    floor_thr = get_config_value(config, 'desat', 'spo2_floor', 90);
    drop_thr = get_config_value(config, 'desat', 'drop_thr', 3);
    min_dur_sec = get_config_value(config, 'desat', 'min_dur_sec', 10);
    diagnostics_desat.thresholds = struct( ...
        'spo2_floor_percent', floor_thr, ...
        'session_drop_pp', drop_thr, ...
        'minimum_duration_sec', min_dur_sec, ...
        'absolute_inequality', '<', ...
        'relative_inequality', '>=');

    reference_value = NaN;
    if diagnostics_desat.relative_available
        reference_value = spo2_ref.median_percent;
    end
    [events_desat, absolute_mask, relative_mask] = ...
        detect_desaturation_events(spo2, reference_value, config.fs, ...
            floor_thr, drop_thr, min_dur_sec);

    metric_config = desaturation_metric_config(config);
    diagnostics_desat.metrics_settings = metric_config;
    diagnostics_desat.event_metrics_automatic = ...
        describe_desaturation_events(events_desat, spo2, config.fs, ...
            reference_value, diagnostics_desat.absolute_available, ...
            diagnostics_desat.relative_available, absolute_mask, ...
            relative_mask, metric_config);
    diagnostics_desat.provenance = struct( ...
        'branch_combination', ...
            'sample_level_absolute_or_relative_then_existing_duration_filter', ...
        'partial_ascertainment', ...
            strcmp(diagnostics_desat.detection_mode, 'absolute_only'), ...
        'relative_reference_source', 'common_session_reference_interval', ...
        'event_metrics_role', ...
            'descriptive_only_not_used_for_event_detection');

    do_plot = get_config_value(config, 'desat', 'do_plot', false);
    if ~do_plot
        return;
    end
    pos = near_fullscreen_figure_position();
    pos(4) = 0.55 * pos(4);
    fig = figure('Units', 'pixels', 'Position', pos, ...
        'Visible', config.make_figs_visible);
    sgtitle(sprintf(['Subject: %g | Measurement: %g | ' ...
        'Desaturation (%s)'], config.subject, config.measure, ...
        diagnostics_desat.detection_mode), 'Interpreter', 'none');
    ax = gca;
    plot_spo2_diagnostic_panel(ax, data, session_reference, ...
        spo2_ref, events_desat, config, ...
        ['SpO2 desaturation | ' diagnostics_desat.detection_mode]);
    for k = 1:numel(events_desat)
        xline(ax, events_desat(k).start_t, ':', 'HandleVisibility', 'off');
        xline(ax, events_desat(k).end_t, ':', 'HandleVisibility', 'off');
    end
    set(fig, 'Visible', config.make_figs_visible);
    save_figure(config, 'desaturation');
end

function diagnostics = empty_desaturation_diagnostics()
% EMPTY_DESATURATION_DIAGNOSTICS Initialize branch availability/provenance.

    diagnostics = struct( ...
        'schema_version', 'desaturation_diagnostics_v2', ...
        'signal_available', false, ...
        'absolute_available', false, ...
        'relative_available', false, ...
        'detection_available', false, ...
        'reference_available', false, ...
        'reference_quality', 'not_evaluated', ...
        'detection_mode', 'unavailable', ...
        'availability_reason', 'not_evaluated', ...
        'thresholds', struct(), ...
        'metrics_settings', struct(), ...
        'event_metrics_automatic', empty_desaturation_event_metrics(), ...
        'provenance', struct());
end

function tf = valid_spo2_reference(spo2_ref)
% VALID_SPO2_REFERENCE Require an explicitly available finite session median.

    tf = isstruct(spo2_ref) && isfield(spo2_ref, 'available') && ...
        isscalar(spo2_ref.available) && logical(spo2_ref.available) && ...
        isfield(spo2_ref, 'median_percent') && ...
        isscalar(spo2_ref.median_percent) && ...
        isfinite(spo2_ref.median_percent);
end

function mode = desaturation_detection_mode(absolute_available, relative_available)
% DESATURATION_DETECTION_MODE Encode full, partial, or unavailable ascertainment.

    if absolute_available && relative_available
        mode = 'absolute_and_relative';
    elseif absolute_available
        mode = 'absolute_only';
    else
        mode = 'unavailable';
    end
end

function [desat_events, absolute_mask, relative_mask] = ...
    detect_desaturation_events( ...
        spo2, spo2_base, fs, spo2_floor, drop_thr, min_dur_sec)
% DETECT_DESATURATION_EVENTS Apply independent branches before run filtering.
% Absolute support is strictly below spo2_floor. Relative support is greater
% than or equal to drop_thr only when spo2_base is finite. NaNs remain false
% and therefore break combined runs exactly as in the prior implementation.

    spo2 = spo2(:);
    absolute_mask = false(size(spo2));
    relative_mask = false(size(spo2));
    desat_events = empty_events();
    if isempty(spo2) || ~isfinite(fs) || fs <= 0
        return;
    end
    valid = isfinite(spo2);
    absolute_mask(valid) = spo2(valid) < spo2_floor;
    if isfinite(spo2_base)
        relative_mask(valid) = ...
            (spo2_base - spo2(valid)) >= drop_thr;
    end
    desat_events = runs_to_events(absolute_mask | relative_mask, ...
        fs, min_dur_sec, 'desaturation');
end

function settings = desaturation_metric_config(config)
% DESATURATION_METRIC_CONFIG Resolve and validate descriptive settings.

    defaults = struct( ...
        'pre_event_lookback_sec', 30, ...
        'min_pre_event_valid_sec', 10, ...
        'recovery_tolerance_pp', 1, ...
        'recovery_hold_sec', 5, ...
        'max_recovery_search_sec', 120);
    settings = defaults;
    if isfield(config, 'desat') && isfield(config.desat, 'metrics')
        names = fieldnames(defaults);
        for i = 1:numel(names)
            if isfield(config.desat.metrics, names{i})
                settings.(names{i}) = config.desat.metrics.(names{i});
            end
        end
    end
    names = fieldnames(settings);
    for i = 1:numel(names)
        value = settings.(names{i});
        if ~isscalar(value) || ~isfinite(value) || value < 0
            error('MAGMA:Desaturation:InvalidMetricSetting', ...
                'config.desat.metrics.%s must be a finite nonnegative scalar.', ...
                names{i});
        end
    end
    if settings.pre_event_lookback_sec <= 0 || ...
            settings.recovery_hold_sec <= 0 || ...
            settings.max_recovery_search_sec <= 0
        error('MAGMA:Desaturation:InvalidMetricSetting', ...
            'Lookback, recovery hold, and maximum search durations must be positive.');
    end
end

function metrics = describe_desaturation_events( ...
    events, spo2, fs, reference_value, absolute_available, ...
    relative_available, absolute_mask, relative_mask, settings)
% DESCRIBE_DESATURATION_EVENTS Compute post-detection event descriptors.

    metrics = empty_desaturation_event_metrics();
    if isempty(events)
        return;
    end
    template = desaturation_metric_template();
    metrics = repmat(template, numel(events), 1);
    all_event_mask = false(size(spo2));
    for i = 1:numel(events)
        all_event_mask(events(i).start_idx:events(i).end_idx) = true;
    end

    for i = 1:numel(events)
        event = events(i);
        metric = template;
        metric.start_idx = event.start_idx;
        metric.end_idx = event.end_idx;
        [metric.nadir_spo2_percent, metric.nadir_idx, metric.nadir_t] = ...
            event_nadir(spo2, event, fs);
        if isfinite(reference_value) && isfinite(metric.nadir_spo2_percent)
            metric.session_drop_pp = ...
                reference_value - metric.nadir_spo2_percent;
        end

        [metric.pre_event_baseline_spo2, ...
            metric.pre_event_baseline_available, ...
            metric.pre_event_support_sec, ...
            metric.pre_event_baseline_status] = pre_event_baseline( ...
                spo2, event.start_idx, all_event_mask, fs, settings);
        if metric.pre_event_baseline_available && ...
                isfinite(metric.nadir_spo2_percent)
            metric.local_drop_pp = metric.pre_event_baseline_spo2 - ...
                metric.nadir_spo2_percent;
        end

        finite_event = isfinite(spo2(event.start_idx:event.end_idx));
        denominator = nnz(finite_event);
        if absolute_available && denominator > 0
            metric.absolute_support_fraction = nnz( ...
                absolute_mask(event.start_idx:event.end_idx)) / denominator;
            metric.absolute_supported = double( ...
                metric.absolute_support_fraction > 0);
        end
        if relative_available && denominator > 0
            metric.relative_support_fraction = nnz( ...
                relative_mask(event.start_idx:event.end_idx)) / denominator;
            metric.relative_supported = double( ...
                metric.relative_support_fraction > 0);
        end
        metric.detection_support_mode = event_support_mode( ...
            metric.absolute_supported, metric.relative_supported);

        [metric.recovery_observed, metric.recovery_idx, ...
            metric.recovery_t, metric.nadir_to_recovery_sec, ...
            metric.recovery_status] = event_recovery( ...
                spo2, metric, events, i, fs, settings);
        metrics(i) = metric;
    end
end

function metrics = empty_desaturation_event_metrics()
% EMPTY_DESATURATION_EVENT_METRICS Return an empty stable descriptor schema.

    template = desaturation_metric_template();
    metrics = repmat(template, 0, 1);
end

function metric = desaturation_metric_template()
% DESATURATION_METRIC_TEMPLATE Define one event-linked descriptor record.

    metric = struct( ...
        'start_idx', NaN, ...
        'end_idx', NaN, ...
        'nadir_spo2_percent', NaN, ...
        'nadir_idx', NaN, ...
        'nadir_t', NaN, ...
        'session_drop_pp', NaN, ...
        'pre_event_baseline_spo2', NaN, ...
        'pre_event_baseline_available', false, ...
        'pre_event_support_sec', 0, ...
        'pre_event_baseline_status', 'not_evaluated', ...
        'local_drop_pp', NaN, ...
        'recovery_observed', false, ...
        'recovery_idx', NaN, ...
        'recovery_t', NaN, ...
        'nadir_to_recovery_sec', NaN, ...
        'recovery_status', 'not_evaluated', ...
        'absolute_support_fraction', NaN, ...
        'relative_support_fraction', NaN, ...
        'absolute_supported', NaN, ...
        'relative_supported', NaN, ...
        'detection_support_mode', 'unavailable');
end

function [nadir, nadir_idx, nadir_t] = event_nadir(spo2, event, fs)
% EVENT_NADIR Return the first occurrence of the finite event minimum.

    nadir = NaN;
    nadir_idx = NaN;
    nadir_t = NaN;
    values = spo2(event.start_idx:event.end_idx);
    finite_local = find(isfinite(values));
    if isempty(finite_local)
        return;
    end
    finite_values = values(finite_local);
    [nadir, first_minimum] = min(finite_values);
    nadir_idx = event.start_idx - 1 + finite_local(first_minimum);
    nadir_t = (nadir_idx - 1) / fs;
end

function [baseline, available, support_sec, status] = pre_event_baseline( ...
    spo2, event_start, event_mask, fs, settings)
% PRE_EVENT_BASELINE Use only the immediately preceding contiguous clean segment.

    baseline = NaN;
    available = false;
    support_sec = 0;
    status = 'insufficient_contiguous_support';
    if event_start <= 1
        status = 'recording_start';
        return;
    end
    max_samples = floor(settings.pre_event_lookback_sec * fs);
    indices = zeros(max_samples, 1);
    count = 0;
    j = event_start - 1;
    while j >= 1 && count < max_samples
        if event_mask(j)
            status = 'previous_event_boundary';
            break;
        end
        if ~isfinite(spo2(j))
            status = 'invalid_data_before_event';
            break;
        end
        count = count + 1;
        indices(count) = j;
        j = j - 1;
    end
    indices = indices(1:count);
    support_sec = count / fs;
    if support_sec < settings.min_pre_event_valid_sec
        return;
    end
    baseline = median(spo2(indices), 'omitnan');
    available = isfinite(baseline);
    if available
        status = 'available';
    end
end

function mode = event_support_mode(absolute_supported, relative_supported)
% EVENT_SUPPORT_MODE Describe which evaluable criteria contributed.

    abs_yes = isfinite(absolute_supported) && absolute_supported ~= 0;
    rel_yes = isfinite(relative_supported) && relative_supported ~= 0;
    if abs_yes && rel_yes
        mode = 'absolute_and_relative';
    elseif abs_yes
        mode = 'absolute_only';
    elseif rel_yes
        mode = 'relative_only';
    else
        mode = 'unavailable';
    end
end

function [observed, recovery_idx, recovery_t, recovery_sec, status] = ...
    event_recovery(spo2, metric, events, event_index, fs, settings)
% EVENT_RECOVERY Search for sustained return to the local baseline target.

    observed = false;
    recovery_idx = NaN;
    recovery_t = NaN;
    recovery_sec = NaN;
    status = 'no_pre_event_baseline';
    if ~metric.pre_event_baseline_available || ~isfinite(metric.nadir_idx)
        return;
    end

    target = metric.pre_event_baseline_spo2 - settings.recovery_tolerance_pp;
    hold_samples = max(1, ceil(settings.recovery_hold_sec * fs));
    max_search_samples = floor(settings.max_recovery_search_sec * fs);
    search_end = min(numel(spo2), metric.nadir_idx + max_search_samples);
    next_event_start = Inf;
    if event_index < numel(events)
        next_event_start = events(event_index + 1).start_idx;
    end
    run_length = 0;
    for j = metric.nadir_idx:search_end
        if j >= next_event_start
            status = 'next_event_before_recovery';
            return;
        end
        if ~isfinite(spo2(j))
            status = 'invalid_data_before_recovery';
            return;
        end
        if spo2(j) >= target
            run_length = run_length + 1;
        else
            run_length = 0;
        end
        if run_length >= hold_samples
            recovery_idx = j - hold_samples + 1;
            recovery_t = (recovery_idx - 1) / fs;
            recovery_sec = (recovery_idx - metric.nadir_idx) / fs;
            observed = true;
            status = 'observed';
            return;
        end
    end
    if search_end < numel(spo2) && search_end < next_event_start
        status = 'search_window_censored';
    elseif next_event_start <= numel(spo2) && next_event_start <= search_end + 1
        status = 'next_event_before_recovery';
    else
        status = 'recording_end_censored';
    end
end
