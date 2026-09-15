function [events, diagnostics] = detect_periodic_breathing( ...
    data, resp_cycles, config)
% DETECT_PERIODIC_BREATHING Compute eAMI and Guyot literature methods.
% Both methods are always evaluated independently when their inputs support
% them. config.csr.primary_method explicitly selects which combined method
% supplies the canonical csr events; there is no union, vote, or fallback.

    if ~isfield(config, 'csr') || ~isstruct(config.csr)
        error('MAGMA:CSR:MissingConfig', 'config.csr is required.');
    end
    primary_method = 'eami';
    if isfield(config.csr, 'primary_method')
        primary_method = lower(char(string(config.csr.primary_method)));
    end
    if ~ismember(primary_method, {'eami', 'guyot'})
        error('MAGMA:CSR:InvalidPrimaryMethod', ...
            'config.csr.primary_method must be ''eami'' or ''guyot'' (received ''%s'').', ...
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

    diagnostics = struct( ...
        'available', selected.available, ...
        'primary_method', primary_method, ...
        'primary_events', events, ...
        'primary_unavailable_reason', unavailable_reason, ...
        'eami', eami, ...
        'guyot', guyot);

    do_plot = isfield(config.csr, 'do_plot') && logical(config.csr.do_plot);
    if do_plot
        plot_periodic_method_comparison(data, config, diagnostics);
    end
end

function plot_periodic_method_comparison(data, config, diagnostics)
% PLOT_PERIODIC_METHOD_COMPARISON Compare raw, eAMI, and Guyot evidence.

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

    ax1 = subplot(6, 1, 1); hold on
    plot_raw_belts(ax1, t_raw, data, idx_lungs, idx_diaph);
    title('Raw respiratory effort belts')
    xlabel('Time (s)'); ylabel('Raw belt'); grid on; hold off

    ax2 = subplot(6, 1, 2); hold on
    plot_finite_trace(ax2, eami.lungs.t_sec, eami.lungs.eami, ...
        [0.15 0.15 0.15], 'lungs eAMI');
    plot_finite_trace(ax2, eami.diaph.t_sec, eami.diaph.eami, ...
        [0.10 0.35 0.90], 'diaphragm eAMI');
    yline(ax2, config.csr.eami.threshold, 'r--', ...
        'DisplayName', 'eAMI threshold');
    shade_events_on_axis(ax2, eami.combined.events, 'combined eAMI events');
    title('eAMI literature method')
    xlabel('Time (s)'); ylabel('eAMI'); grid on
    show_legend_if_data(ax2); hold off

    ax3 = subplot(6, 1, 3); hold on
    plot_finite_trace(ax3, guyot.lungs.envelope_t, guyot.lungs.envelope, ...
        [0.15 0.15 0.15], 'lungs envelope');
    plot_finite_trace(ax3, guyot.diaph.envelope_t, guyot.diaph.envelope, ...
        [0.10 0.35 0.90], 'diaphragm envelope');
    title('Guyot reconstructed ventilation envelope')
    xlabel('Time (s)'); ylabel('Canonical amplitude'); grid on
    show_legend_if_data(ax3); hold off

    ax4 = subplot(6, 1, 4); hold on
    plot_window_points(ax4, guyot.lungs.window_center_t, guyot.lungs.h, ...
        [0.15 0.15 0.15], 'lungs h');
    plot_window_points(ax4, guyot.diaph.window_center_t, guyot.diaph.h, ...
        [0.10 0.35 0.90], 'diaphragm h');
    yline(ax4, config.csr.guyot.h_threshold, 'r--', ...
        'DisplayName', 'h threshold');
    shade_events_on_axis(ax4, guyot.combined.events, 'combined Guyot events');
    title('Guyot modulation depth')
    xlabel('Time (s)'); ylabel('h'); grid on
    show_legend_if_data(ax4); hold off

    ax5 = subplot(6, 1, 5); hold on
    plot_window_points(ax5, guyot.lungs.window_center_t, guyot.lungs.fm_mhz, ...
        [0.15 0.15 0.15], 'lungs f_m');
    plot_window_points(ax5, guyot.diaph.window_center_t, guyot.diaph.fm_mhz, ...
        [0.10 0.35 0.90], 'diaphragm f_m');
    yline(ax5, 1000 * config.csr.guyot.fm_band_hz(1), 'r--', ...
        'DisplayName', 'accepted f_m band');
    yline(ax5, 1000 * config.csr.guyot.fm_band_hz(2), 'r--', ...
        'HandleVisibility', 'off');
    shade_events_on_axis(ax5, guyot.combined.events, 'combined Guyot events');
    title('Guyot modulation frequency')
    xlabel('Time (s)'); ylabel('f_m (mHz)'); grid on
    show_legend_if_data(ax5); hold off

    ax6 = subplot(6, 1, 6); hold on
    plot_method_timeline(ax6, eami.combined.t_sec, ...
        eami.combined.candidate_mask, 2, [0.75 0.10 0.10]);
    plot_method_timeline(ax6, guyot.combined.t_sec, ...
        guyot.combined.candidate_mask, 1, [0.10 0.35 0.90]);
    yticks(ax6, [1 2]); yticklabels(ax6, {'Guyot', 'eAMI'});
    ylim(ax6, [0.5 2.5]);
    title(['Final method timelines | primary = ' diagnostics.primary_method])
    xlabel('Time (s)'); ylabel('Method'); grid on; hold off

    axes_handles = [ax1 ax2 ax3 ax4 ax5 ax6];
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

function plot_window_points(ax, t_sec, values, color, display_name)
% PLOT_WINDOW_POINTS Plot center-associated Guyot estimates without joining.

    if isempty(t_sec) || isempty(values)
        return;
    end
    valid = isfinite(t_sec) & isfinite(values);
    plot(ax, t_sec(valid), values(valid), 'o', 'LineStyle', 'none', ...
        'Color', color, 'MarkerSize', 4, 'DisplayName', display_name);
end

function plot_method_timeline(ax, t_sec, candidate_mask, row, color)
% PLOT_METHOD_TIMELINE Draw retained method support on a compact fixed row.

    plot(ax, [0 max([0; t_sec(:)])], [row row], '-', ...
        'Color', [0.8 0.8 0.8], 'HandleVisibility', 'off');
    candidate_mask = logical(candidate_mask(:));
    state = nan(size(t_sec));
    state(candidate_mask) = row;
    plot(ax, t_sec, state, '-', 'Color', color, 'LineWidth', 4, ...
        'HandleVisibility', 'off');
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
