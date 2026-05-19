function plot_belt_diagnostic_figure(data, config, t_grid, mask_lungs, mask_diaph, metric_lungs, metric_diaph, opts)
% plot_belt_diagnostic_figure
% Shared raw-belt + diagnostic-metric plot for lungs and diaphragm.

    idx_lungs = find(strcmp(config.data_columns, 'Resp-Lungs'), 1);
    idx_diaph = find(strcmp(config.data_columns, 'Resp-Diaphragm'), 1);
    t_raw = (0:size(data,1)-1) / config.new_fs;

    plot_step_sec = get_opt(opts, 'plot_step_sec', 15);
    metric_lungs_plot = held_median_trace_local(t_grid, metric_lungs, plot_step_sec);
    metric_diaph_plot = held_median_trace_local(t_grid, metric_diaph, plot_step_sec);
    [secondary_lungs, secondary_lungs_plot] = secondary_metric_local(opts, 'lungs', t_grid, plot_step_sec);
    [secondary_diaph, secondary_diaph_plot] = secondary_metric_local(opts, 'diaph', t_grid, plot_step_sec);

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
    plot_diagnostic_metric(t_grid, metric_lungs, metric_lungs_plot, secondary_lungs, secondary_lungs_plot, opts, 'lungs');
    hold off

    ax3 = nexttile(tl); hold on
    plot(t_raw, data(:,idx_diaph), 'k')
    shade_mask_on_axis(t_grid, mask_diaph)
    title(sprintf('%s (diaphragm) over raw signal', opts.event_name))
    xlabel('Time (s)'); ylabel('Resp-Diaphragm'); grid on
    hold off

    ax4 = nexttile(tl); hold on
    plot_diagnostic_metric(t_grid, metric_diaph, metric_diaph_plot, secondary_diaph, secondary_diaph_plot, opts, 'diaphragm');
    hold off

    ax = [ax1 ax2 ax3 ax4];
    linkaxes(ax,'x');
    xlim(ax1, [0 t_grid(end)]);

    save_figure(config, opts.output_name);
end

function plot_diagnostic_metric(t_grid, metric_raw, metric_plot, secondary_raw, secondary_plot, opts, belt_name)
    primary_label = get_opt(opts, 'primary_label', 'Metric');
    plot(t_grid, metric_raw, 'Color', [0.70 0.70 0.70], 'LineWidth', 0.8, ...
        'DisplayName', [primary_label ' raw'])
    stairs(t_grid, metric_plot, 'b', 'LineWidth', 1.4, 'DisplayName', [primary_label ' held'])

    has_secondary = ~isempty(secondary_raw) && ~isempty(secondary_plot);
    if has_secondary
        secondary_label = get_opt(opts, 'secondary_label', 'Secondary metric');
        plot(t_grid, secondary_raw, 'Color', [0.90 0.70 0.45], 'LineWidth', 0.8, ...
            'DisplayName', [secondary_label ' raw'])
        stairs(t_grid, secondary_plot, 'Color', [0.85 0.33 0.10], 'LineWidth', 1.4, ...
            'DisplayName', [secondary_label ' held'])
    end

    if isfield(opts, 'threshold') && isfinite(opts.threshold)
        yline(opts.threshold, 'r--', opts.threshold_label, ...
            'LineWidth', 2.2, ...
            'LabelHorizontalAlignment', 'left', ...
            'LabelVerticalAlignment', 'bottom');
    end
    if has_secondary && isfield(opts, 'secondary_threshold') && isfinite(opts.secondary_threshold)
        secondary_threshold_label = get_opt(opts, 'secondary_threshold_label', ...
            sprintf('%s threshold', secondary_label));
        yline(opts.secondary_threshold, '--', secondary_threshold_label, ...
            'Color', [0.85 0.33 0.10], ...
            'LineWidth', 1.8, ...
            'LabelHorizontalAlignment', 'left', ...
            'LabelVerticalAlignment', 'top');
    end

    values = [metric_raw(:); metric_plot(:)];
    if has_secondary
        values = [values; secondary_raw(:); secondary_plot(:)];
    end
    set_metric_limits(values, opts);
    title(sprintf('%s (%s, %s)', opts.metric_title, belt_name, opts.metric_detail))
    xlabel('Time (s)')
    ylabel(opts.metric_ylabel)
    grid on
    if has_secondary
        legend('show', 'Location', 'eastoutside')
    end
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

function [metric_raw, metric_plot] = secondary_metric_local(opts, belt_name, t_grid, plot_step_sec)
    metric_raw = [];
    metric_plot = [];

    field_name = ['secondary_metric_' belt_name];
    if ~isfield(opts, field_name) || isempty(opts.(field_name))
        return;
    end

    metric_raw = opts.(field_name);
    metric_plot = held_median_trace_local(t_grid, metric_raw, plot_step_sec);
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
    if isfield(opts, 'secondary_threshold') && isfinite(opts.secondary_threshold)
        ymax = max(ymax, opts.secondary_threshold);
    end
    ylim([lower_limit, max(min_ymax, ymax + ymax_padding)]);
end

function value = get_opt(opts, name, default_value)
    value = default_value;
    if isfield(opts, name) && ~isempty(opts.(name))
        value = opts.(name);
    end
end
