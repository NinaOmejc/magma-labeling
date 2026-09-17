function [events, diagnostics, candidate_events] = detect_periodic_breathing( ...
    data, resp_cycles, config)
% DETECT_PERIODIC_BREATHING Compute MAGMA-adapted eAMI and Guyot methods.
% Both methods are always evaluated independently when their inputs support
% them. config.periodic.primary_method explicitly selects which combined method
% supplies the canonical periodic events; there is no union, vote, or fallback.

    if ~isfield(config, 'periodic') || ~isstruct(config.periodic)
        error('MAGMA:Periodic:MissingConfig', 'config.periodic is required.');
    end
    primary_method = 'eami';
    if isfield(config.periodic, 'primary_method')
        primary_method = lower(char(string(config.periodic.primary_method)));
    end
    if ~ismember(primary_method, {'eami', 'guyot'})
        error('MAGMA:Periodic:InvalidPrimaryMethod', ...
            'config.periodic.primary_method must be ''eami'' or ''guyot'' (received ''%s'').', ...
            primary_method);
    end

    eami = compute_eami_periodic_breathing(data, config);
    guyot = compute_guyot_periodic_breathing(data, resp_cycles, config);
    switch primary_method
        case 'eami'
            selected = eami;
        case 'guyot'
            selected = guyot;
    end
    if selected.available
        events = selected.combined.events;
        unavailable_reason = '';
    else
        events = empty_events();
        unavailable_reason = ['Selected primary method ''' primary_method ...
            ''' is not scientifically evaluable for this recording.'];
    end
    candidate_events = selected.combined.candidate_events;

    diagnostics = struct( ...
        'available', selected.available, ...
        'primary_method', primary_method, ...
        'primary_events', events, ...
        'primary_unavailable_reason', unavailable_reason, ...
        'eami', eami, ...
        'guyot', guyot);

    do_plot = isfield(config.periodic, 'do_plot') && ...
        logical(config.periodic.do_plot);
    if do_plot
        plot_periodic_method_comparison(data, config, diagnostics);
    end
    diagnostics = compact_periodic_diagnostics(diagnostics);
end

function compact = compact_periodic_diagnostics(full)
% COMPACT_PERIODIC_DIAGNOSTICS Retain unique evidence for method comparison.

    compact = struct( ...
        'available', full.available, ...
        'primary_method', full.primary_method, ...
        'primary_unavailable_reason', full.primary_unavailable_reason, ...
        'eami', compact_eami(full.eami), ...
        'guyot', compact_guyot(full.guyot));
end

function compact = compact_eami(full)
% COMPACT_EAMI Drop reproducible filtering stages and copied config values.

    validate_compact_eami_grid(full);
    compact = struct( ...
        'available', full.available, ...
        'time_sec', full.combined.t_sec, ...
        'reference_doi', full.reference_doi, ...
        'implementation', full.implementation, ...
        'lungs', compact_eami_belt(full.lungs), ...
        'diaph', compact_eami_belt(full.diaph), ...
        'combined', struct( ...
            'available', full.combined.available, ...
            'evaluable_mask', full.combined.evaluable_mask, ...
            'threshold_mask', full.combined.threshold_mask), ...
        'event_count', numel(full.combined.events), ...
        'event_duration_sec', event_duration(full.combined.events));
end

function compact = compact_eami_belt(full)
% COMPACT_EAMI_BELT Keep only the scientific index and its evaluability.

    compact = struct( ...
        'available', full.available, ...
        'evaluable_mask', full.evaluable_mask, ...
        'index', full.eami);
end

function validate_compact_eami_grid(full)
% VALIDATE_COMPACT_EAMI_GRID Require one shared authoritative eAMI time grid.

    time_sec = full.combined.t_sec(:);
    grids_match = isequaln(full.lungs.t_sec(:), time_sec) && ...
        isequaln(full.diaph.t_sec(:), time_sec);
    values = {full.combined.evaluable_mask, full.combined.threshold_mask, ...
        full.lungs.evaluable_mask, full.lungs.eami, ...
        full.diaph.evaluable_mask, full.diaph.eami};
    lengths_match = all(cellfun(@(value) numel(value) == numel(time_sec), values));
    if ~grids_match || ~lengths_match
        error('MAGMA:Periodic:EAMIGridMismatch', ...
            'Full eAMI belt and combined evidence must share one time grid.');
    end
end

function compact = compact_guyot(full)
% COMPACT_GUYOT Keep distinct-grid modulation evidence and combined support.

    compact = struct( ...
        'available', full.available, ...
        'method', full.method, ...
        'reference_doi', full.reference_doi, ...
        'implementation', full.implementation, ...
        'front_end_note', full.front_end_note, ...
        'temporal_projection', full.temporal_projection, ...
        'lungs', compact_guyot_belt(full.lungs), ...
        'diaph', compact_guyot_belt(full.diaph), ...
        'combined', struct( ...
            'available', full.combined.available, ...
            'evaluable_mask', full.combined.evaluable_mask, ...
            'pathological_mask', full.combined.pathological_mask), ...
        'event_count', numel(full.combined.events), ...
        'event_duration_sec', event_duration(full.combined.events));
end

function compact = compact_guyot_belt(full)
% COMPACT_GUYOT_BELT Omit breath/envelope copies reproducible from saved inputs.

    compact = struct( ...
        'available', full.available, ...
        'window_center_t', full.window_center_t, ...
        'h', full.h, ...
        'fm_hz', full.fm_hz, ...
        'reconstruction_error', full.reconstruction_error, ...
        'evaluable_window_mask', full.evaluable_window_mask);
end

function seconds = event_duration(events)
% EVENT_DURATION Sum finite event durations.

    if isempty(events)
        seconds = 0;
        return;
    end
    durations = [events.duration];
    seconds = sum(durations(isfinite(durations)));
end

function plot_periodic_method_comparison(data, config, diagnostics)
% PLOT_PERIODIC_METHOD_COMPARISON Show final labels and method-specific evidence.

    N = size(data, 1);
    t_raw = (0:N - 1)' / config.fs;
    recording_end_t = max(0, (N - 1) / config.fs);
    if ~isfield(config, 'channels')
        config = resolve_signal_channels(config);
    end
    idx_lungs = config.channels.lungs_idx;
    idx_diaph = config.channels.diaph_idx;
    if is_lung_belt_ignored(config)
        idx_lungs = [];
    end
    eami = diagnostics.eami;
    guyot = diagnostics.guyot;

    figure('Units', 'pixels', 'Position', near_fullscreen_figure_position(), ...
        'Visible', config.make_figs_visible);
    sgtitle(['PERIODIC BREATHING / CHEYNE-STOKES-LIKE EFFORT PATTERN' newline ...
        'Primary method: ' upper(diagnostics.primary_method) ...
        ' | Subject: ' num2str(config.subject) ...
        ' | Measurement: ' num2str(config.measure)])

    ax1 = subplot(3, 1, 1); hold on
    plot_raw_belts(ax1, t_raw, data, idx_lungs, idx_diaph);
    shade_events_on_axis(ax1, diagnostics.primary_events, ...
        'final primary periodic events');
    title('Raw respiratory effort belts + final periodic label')
    xlabel('Time (s)'); ylabel('Raw belt'); grid on; hold off
    show_legend_if_data(ax1);

    ax2 = subplot(3, 1, 2); hold on
    plot_finite_trace(ax2, eami.lungs.t_sec, eami.lungs.eami, ...
        [0.15 0.15 0.15], 'lungs eAMI');
    plot_finite_trace(ax2, eami.diaph.t_sec, eami.diaph.eami, ...
        [0.10 0.35 0.90], 'diaphragm eAMI');
    yline(ax2, config.periodic.eami.threshold, 'r--', ...
        'DisplayName', 'eAMI threshold');
    shade_events_on_axis(ax2, eami.combined.events, 'combined eAMI events');
    title('eAMI')
    xlabel('Time (s)'); ylabel('eAMI'); grid on
    show_legend_if_data(ax2); hold off

    ax3 = subplot(3, 1, 3); hold on
    plot_finite_trace(ax3, guyot.lungs.envelope_t, guyot.lungs.envelope, ...
        [0.15 0.15 0.15], 'lungs envelope');
    plot_finite_trace(ax3, guyot.diaph.envelope_t, guyot.diaph.envelope, ...
        [0.10 0.35 0.90], 'diaphragm envelope');
    shade_events_on_axis(ax3, guyot.combined.events, ...
        'combined Guyot events');
    title('Guyot canonical breath-amplitude envelope')
    xlabel('Time (s)'); ylabel('Canonical amplitude'); grid on
    show_legend_if_data(ax3); hold off

    axes_handles = [ax1 ax2 ax3];
    linkaxes(axes_handles, 'x');
    if recording_end_t > 0
        xlim(ax1, [0 recording_end_t]);
    end
    align_axes_x_widths(axes_handles);
    save_figure(config, 'periodic_breathing');
end

function plot_raw_belts(ax, t_raw, data, idx_lungs, idx_diaph)
% PLOT_RAW_BELTS Plot each available raw belt without changing its scale.

    plotted = false;
    if valid_plot_channel(idx_lungs, size(data, 2))
        plot(ax, t_raw, data(:, idx_lungs), 'Color', [0.15 0.15 0.15], ...
            'DisplayName', 'Resp-Lungs');
        plotted = true;
    end
    if valid_plot_channel(idx_diaph, size(data, 2))
        plot(ax, t_raw, data(:, idx_diaph), 'Color', [0.10 0.35 0.90], ...
            'DisplayName', 'Resp-Diaphragm');
        plotted = true;
    end
    if plotted
        legend(ax, 'Location', 'eastoutside');
    else
        text(ax, 0.5, 0.5, 'No usable raw respiratory belt', ...
            'Units', 'normalized', 'HorizontalAlignment', 'center');
    end
end

function plot_finite_trace(ax, t_sec, values, color, display_name)
% PLOT_FINITE_TRACE Plot supported samples while retaining gaps as gaps.

    if isempty(t_sec) || isempty(values)
        return;
    end
    values = values(:);
    values(~isfinite(values)) = NaN;
    plot(ax, t_sec(:), values, '-', 'Color', color, ...
        'LineWidth', 1.1, 'DisplayName', display_name);
end

function show_legend_if_data(ax)
% SHOW_LEGEND_IF_DATA Avoid empty legends on unavailable diagnostics.

    objects = findobj(ax, '-property', 'DisplayName');
    if isempty(objects)
        legend(ax, 'off');
        return;
    end
    names = get(objects, 'DisplayName');
    if ischar(names), names = {names}; end
    if any(~cellfun(@isempty, names))
        legend(ax, 'Location', 'eastoutside');
    end
end

function tf = valid_plot_channel(index, n_columns)
% VALID_PLOT_CHANNEL Validate a resolved data-column index.

    tf = ~isempty(index) && isscalar(index) && isfinite(index) && ...
        index == round(index) && index >= 1 && index <= n_columns;
end
