function plot_belt_diagnostic_figure(data, config, t_grid, mask_lungs, mask_diaph, metric_lungs, metric_diaph, opts)
% plot_belt_diagnostic_figure
% Shared raw-belt + diagnostic-metric plot for lungs and diaphragm.

    idx_lungs = find(strcmp(config.data_columns, 'Resp-Lungs'), 1);
    idx_diaph = find(strcmp(config.data_columns, 'Resp-Diaphragm'), 1);
    t_raw = (0:size(data,1)-1) / config.fs;

    plot_step_sec = get_opt(opts, 'plot_step_sec', 15);
    metric_lungs_plot = held_median_trace_local(t_grid, metric_lungs, plot_step_sec);
    metric_diaph_plot = held_median_trace_local(t_grid, metric_diaph, plot_step_sec);

    figure('Units','pixels','Position', near_fullscreen_figure_position(), 'Visible', config.make_figs_visible);
    tl = tiledlayout(4, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, opts.figure_title)

    ax1 = nexttile(tl); hold on
    plot(t_raw, data(:,idx_lungs), 'k')
    shade_mask_on_axis(t_grid, mask_lungs)
    title(sprintf('%s (lungs) over raw signal', opts.event_name))
    xlabel('Time (s)'); ylabel('Resp-Lungs'); grid on
    hold off

    ax2 = nexttile(tl); hold on
    plot_diagnostic_metric(t_grid, metric_lungs, metric_lungs_plot, opts, 'lungs');
    hold off

    ax3 = nexttile(tl); hold on
    plot(t_raw, data(:,idx_diaph), 'k')
    shade_mask_on_axis(t_grid, mask_diaph)
    title(sprintf('%s (diaphragm) over raw signal', opts.event_name))
    xlabel('Time (s)'); ylabel('Resp-Diaphragm'); grid on
    hold off

    ax4 = nexttile(tl); hold on
    plot_diagnostic_metric(t_grid, metric_diaph, metric_diaph_plot, opts, 'diaphragm');
    hold off

    ax = [ax1 ax2 ax3 ax4];
    linkaxes(ax,'x');
    xlim(ax1, [0 t_grid(end)]);

    save_figure(config, opts.output_name);
end

function plot_diagnostic_metric(t_grid, metric_raw, metric_plot, opts, belt_name)
    plot(t_grid, metric_raw, 'Color', [0.70 0.70 0.70], 'LineWidth', 0.8)
    stairs(t_grid, metric_plot, 'b', 'LineWidth', 1.4)

    if isfield(opts, 'threshold') && isfinite(opts.threshold)
        yline(opts.threshold, 'r--', opts.threshold_label, ...
            'LineWidth', 2.2, ...
            'LabelHorizontalAlignment', 'left', ...
            'LabelVerticalAlignment', 'bottom');
    end

    set_metric_limits([metric_raw(:); metric_plot(:)], opts);
    title(sprintf('%s (%s, %s)', opts.metric_title, belt_name, opts.metric_detail))
    xlabel('Time (s)')
    ylabel(opts.metric_ylabel)
    grid on
end

function held = held_median_trace_local(t_grid, values, step_sec)
    held = nan(size(values));
    if isempty(t_grid) || isempty(values) || step_sec <= 0
        return;
    end

    block_start = floor(t_grid(1) / step_sec) * step_sec;
    block_edges = block_start:step_sec:(t_grid(end) + step_sec);
    for k = 1:numel(block_edges)-1
        idx = t_grid >= block_edges(k) & t_grid < block_edges(k+1);
        block_values = values(idx);
        block_values = block_values(isfinite(block_values));
        if ~isempty(block_values)
            held(idx) = median(block_values, 'omitnan');
        end
    end
end

function set_metric_limits(values, opts)
    lower_limit = get_opt(opts, 'axis_lower', 0);
    ymax_padding = get_opt(opts, 'ymax_padding', 0.1);
    min_ymax = get_opt(opts, 'min_ymax', lower_limit + 1);

    finite_values = values(isfinite(values));
    if isempty(finite_values)
        ylim([lower_limit, min_ymax]);
        return;
    end

    ymax = max(finite_values);
    if isfield(opts, 'threshold') && isfinite(opts.threshold)
        ymax = max(ymax, opts.threshold);
    end
    ylim([lower_limit, max(min_ymax, ymax + ymax_padding)]);
end

function value = get_opt(opts, name, default_value)
    value = default_value;
    if isfield(opts, name) && ~isempty(opts.(name))
        value = opts.(name);
    end
end
