function plot_amplitude_state_diagnostic(phys_feat, events_lungs, events_diaph, config, opts)
% plot_amplitude_state_diagnostic
% Show raw and session-normalized reviewed breath excursions per belt.

    lungs = phys_feat.resp.lungs;
    diaph = phys_feat.resp.diaph;

    fig = figure('Units', 'pixels', 'Position', near_fullscreen_figure_position(), ...
        'Visible', config.make_figs_visible, 'Color', 'w');
    tl = tiledlayout(fig, 4, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, [opts.figure_title newline ...
        'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)])

    ax1 = nexttile(tl);
    plot_belt_amplitude(ax1, lungs, events_lungs, opts, false, 'Lungs');
    ax2 = nexttile(tl);
    plot_belt_amplitude(ax2, lungs, events_lungs, opts, true, 'Lungs');
    ax3 = nexttile(tl);
    plot_belt_amplitude(ax3, diaph, events_diaph, opts, false, 'Diaphragm');
    ax4 = nexttile(tl);
    plot_belt_amplitude(ax4, diaph, events_diaph, opts, true, 'Diaphragm');

    ax = [ax1 ax2 ax3 ax4];
    linkaxes(ax, 'x');
    if ~isempty(phys_feat.resp.time_sec)
        xlim(ax1, [0 phys_feat.resp.time_sec(end)]);
    end
    align_axes_x_widths(ax);
    set(fig, 'Visible', config.make_figs_visible);
    save_figure(config, opts.output_name);
end

function plot_belt_amplitude(ax, belt, events, opts, normalized, belt_name)
    hold(ax, 'on');
    if normalized
        values = belt.amp_ratio_session;
        ylabel_text = 'Session ratio';
        title_suffix = 'session-normalized breath excursion';
        lower = opts.lower_ratio;
        upper = get_option(opts, 'upper_ratio', NaN);
    else
        values = belt.amp;
        ylabel_text = 'Raw belt units';
        title_suffix = 'raw breath excursion';
        lower = opts.lower_ratio * belt.session_reference_value;
        upper_ratio = get_option(opts, 'upper_ratio', NaN);
        upper = upper_ratio * belt.session_reference_value;
    end

    n = min(numel(belt.peak_t), numel(values));
    if belt.session_amplitude_available && n > 0 && any(isfinite(values(1:n)))
        scatter(ax, belt.peak_t(1:n), values(1:n), 10, 'k', 'filled', ...
            'DisplayName', 'Reviewed breaths');
        add_threshold_line(ax, lower, 'Lower threshold');
        add_threshold_line(ax, upper, 'Upper threshold');
    else
        text(ax, 0.5, 0.5, 'No usable session-normalized belt amplitude evidence', ...
            'Units', 'normalized', 'HorizontalAlignment', 'center');
    end
    shade_events_on_axis(ax, events, opts.event_name);
    hold(ax, 'off');
    title(ax, sprintf('%s: %s', belt_name, title_suffix));
    xlabel(ax, 'Time (s)');
    ylabel(ax, ylabel_text);
    grid(ax, 'on');
end

function add_threshold_line(ax, value, label_text)
    if isscalar(value) && isfinite(value)
        yline(ax, value, 'r--', label_text, ...
            'LabelHorizontalAlignment', 'left', 'HandleVisibility', 'off');
    end
end

function value = get_option(opts, name, default_value)
    value = default_value;
    if isfield(opts, name) && ~isempty(opts.(name))
        value = opts.(name);
    end
end
