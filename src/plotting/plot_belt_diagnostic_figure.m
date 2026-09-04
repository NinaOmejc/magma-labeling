function plot_belt_diagnostic_figure(data, config, t_grid, mask_lungs, mask_diaph, metric_lungs, metric_diaph, opts)
% PLOT_BELT_DIAGNOSTIC_FIGURE Plot belt diagnostic figure.
%
% Syntax:
%   plot_belt_diagnostic_figure(data, config, t_grid, mask_lungs, mask_diaph, metric_lungs, metric_diaph, opts)
%
% Inputs:
%   data - Input physiological signal data.
%   config - Pipeline configuration structure.
%   t_grid - Time coordinates in seconds.
%   mask_lungs - Logical state or selection mask.
%   mask_diaph - Logical state or selection mask.
%   metric_lungs - Input value `metric_lungs`.
%   metric_diaph - Input value `metric_diaph`.
%   opts - Input value `opts`.

    if ~isfield(config, 'channels')
        config = resolve_signal_channels(config);
    end
    idx_lungs = config.channels.lungs_idx;
    idx_diaph = config.channels.diaph_idx;
    t_raw = (0:size(data,1)-1) / config.fs;

    plot_step_sec = get_opt(opts, 'plot_step_sec', 15);
    metric_lungs_plot = held_median_trace_local(t_grid, metric_lungs, plot_step_sec);
    metric_diaph_plot = held_median_trace_local(t_grid, metric_diaph, plot_step_sec);
    [secondary_lungs, secondary_lungs_plot] = secondary_metric_local(opts, 'lungs', t_grid, plot_step_sec);
    [secondary_diaph, secondary_diaph_plot] = secondary_metric_local(opts, 'diaph', t_grid, plot_step_sec);
    metric_mask_lungs = get_opt(opts, 'metric_mask_lungs', mask_lungs);
    metric_mask_diaph = get_opt(opts, 'metric_mask_diaph', mask_diaph);
    metric_trigger_mask_lungs = get_opt(opts, 'metric_trigger_mask_lungs', []);
    metric_trigger_mask_diaph = get_opt(opts, 'metric_trigger_mask_diaph', []);
    candidate_mask_lungs = get_opt(opts, 'candidate_mask_lungs', []);
    candidate_mask_diaph = get_opt(opts, 'candidate_mask_diaph', []);
    localized_mask_lungs = get_opt(opts, 'localized_mask_lungs', []);
    localized_mask_diaph = get_opt(opts, 'localized_mask_diaph', []);

    figure('Units','pixels','Position', near_fullscreen_figure_position(), 'Visible', config.make_figs_visible);
    tl = tiledlayout(4, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, opts.figure_title)

    ax1 = nexttile(tl); hold on
    plot_resp_trace_or_message(t_raw, data, idx_lungs, 'Resp-Lungs')
    shade_state_support_on_axis(ax1, t_grid, candidate_mask_lungs, ...
        localized_mask_lungs, mask_lungs);
    title(sprintf('%s (lungs) over raw signal', opts.event_name))
    xlabel('Time (s)'); ylabel('Resp-Lungs'); grid on
    hold off

    ax2 = nexttile(tl); hold on
    plot_diagnostic_metric(t_grid, metric_lungs, metric_lungs_plot, ...
        secondary_lungs, secondary_lungs_plot, opts, 'lungs', ...
        candidate_mask_lungs, localized_mask_lungs, metric_mask_lungs, ...
        metric_trigger_mask_lungs);
    hold off

    ax3 = nexttile(tl); hold on
    plot_resp_trace_or_message(t_raw, data, idx_diaph, 'Resp-Diaphragm')
    shade_state_support_on_axis(ax3, t_grid, candidate_mask_diaph, ...
        localized_mask_diaph, mask_diaph);
    title(sprintf('%s (diaphragm) over raw signal', opts.event_name))
    xlabel('Time (s)'); ylabel('Resp-Diaphragm'); grid on
    hold off

    ax4 = nexttile(tl); hold on
    plot_diagnostic_metric(t_grid, metric_diaph, metric_diaph_plot, ...
        secondary_diaph, secondary_diaph_plot, opts, 'diaphragm', ...
        candidate_mask_diaph, localized_mask_diaph, metric_mask_diaph, ...
        metric_trigger_mask_diaph);
    hold off

    ax = [ax1 ax2 ax3 ax4];
    linkaxes(ax,'x');
    xlim(ax1, [0 t_grid(end)]);

    save_figure(config, opts.output_name);
end

function plot_resp_trace_or_message(t_raw, data, idx, label_text)
% PLOT_RESP_TRACE_OR_MESSAGE Plot resp trace or message.
%
% Syntax:
%   plot_resp_trace_or_message(t_raw, data, idx, label_text)
%
% Inputs:
%   t_raw - Time coordinates in seconds.
%   data - Input physiological signal data.
%   idx - Input value `idx`.
%   label_text - Label identifier or label metadata.

    if isempty(idx)
        text(0.5, 0.5, [label_text ' channel not found'], ...
            'Units', 'normalized', 'HorizontalAlignment', 'center')
    else
        plot(t_raw, data(:, idx), 'k')
    end
end

function plot_diagnostic_metric(t_grid, metric_raw, metric_plot, secondary_raw, ...
    secondary_plot, opts, belt_name, candidate_mask, localized_mask, ...
    final_mask, trigger_mask)
% PLOT_DIAGNOSTIC_METRIC Plot diagnostic metric.
%
% Syntax:
%   plot_diagnostic_metric(t_grid, metric_raw, metric_plot, secondary_raw, secondary_plot, opts, belt_name, candidate_mask, localized_mask, final_mask, trigger_mask)
%
% Inputs:
%   t_grid - Time coordinates in seconds.
%   metric_raw - Input value `metric_raw`.
%   metric_plot - Input value `metric_plot`.
%   secondary_raw - Duration or window length in seconds.
%   secondary_plot - Duration or window length in seconds.
%   opts - Input value `opts`.
%   belt_name - Input value `belt_name`.
%   candidate_mask - Logical state or selection mask.
%   localized_mask - Logical state or selection mask.
%   final_mask - Logical state or selection mask.
%   trigger_mask - Logical state or selection mask.

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
    shade_state_support_on_axis(gca, t_grid, candidate_mask, ...
        localized_mask, final_mask);
    if ~isempty(trigger_mask)
        mark_trigger_mask_on_axis(gca, t_grid, trigger_mask);
    end
    title(sprintf('%s (%s, %s)', opts.metric_title, belt_name, opts.metric_detail))
    xlabel('Time (s)')
    ylabel(opts.metric_ylabel)
    grid on
    if has_secondary || ~isempty(candidate_mask) || ...
            ~isempty(localized_mask) || ~isempty(final_mask)
        legend('show', 'Location', 'eastoutside')
    end
end

function mark_trigger_mask_on_axis(ax, t_grid, trigger_mask)
% MARK_TRIGGER_MASK_ON_AXIS Mark trigger mask on axis.
%
% Syntax:
%   mark_trigger_mask_on_axis(ax, t_grid, trigger_mask)
%
% Inputs:
%   ax - Target axes handle.
%   t_grid - Time coordinates in seconds.
%   trigger_mask - Logical state or selection mask.

    trigger_mask = trigger_mask(:) ~= 0;
    t_grid = t_grid(:);
    if isempty(trigger_mask) || ~any(trigger_mask) || numel(trigger_mask) ~= numel(t_grid)
        return;
    end

    grid_step_sec = median(diff(t_grid), 'omitnan');
    if ~isfinite(grid_step_sec) || grid_step_sec <= 0
        grid_step_sec = 0;
    end

    y_limits = ylim(ax);
    y0 = y_limits(1) + 0.88 * diff(y_limits);
    y1 = y_limits(2);
    d = diff([false; trigger_mask; false]);
    starts = find(d == 1);
    ends = find(d == -1) - 1;
    for i = 1:numel(starts)
        x0 = t_grid(starts(i));
        x1 = t_grid(ends(i)) + grid_step_sec;
        patch(ax, [x0 x1 x1 x0], [y0 y0 y1 y1], [0.75 0.00 0.00], ...
            'EdgeColor', 'none', 'FaceAlpha', 0.65, 'HandleVisibility', 'off');
    end
end

function held = held_median_trace_local(t_grid, values, step_sec)
% HELD_MEDIAN_TRACE_LOCAL Perform the held median trace local operation.
%
% Syntax:
%   held = held_median_trace_local(t_grid, values, step_sec)
%
% Inputs:
%   t_grid - Time coordinates in seconds.
%   values - Input value `values`.
%   step_sec - Duration or window length in seconds.
%
% Outputs:
%   held - Computed output value `held`.

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
% SECONDARY_METRIC_LOCAL Perform the secondary metric local operation.
%
% Syntax:
%   [metric_raw, metric_plot] = secondary_metric_local(opts, belt_name, t_grid, plot_step_sec)
%
% Inputs:
%   opts - Input value `opts`.
%   belt_name - Input value `belt_name`.
%   t_grid - Time coordinates in seconds.
%   plot_step_sec - Duration or window length in seconds.
%
% Outputs:
%   metric_raw - Computed output value `metric_raw`.
%   metric_plot - Computed output value `metric_plot`.

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
% SET_METRIC_LIMITS Perform the set metric limits operation.
%
% Syntax:
%   set_metric_limits(values, opts)
%
% Inputs:
%   values - Input value `values`.
%   opts - Input value `opts`.

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
% GET_OPT Return opt.
%
% Syntax:
%   value = get_opt(opts, name, default_value)
%
% Inputs:
%   opts - Input value `opts`.
%   name - Input value `name`.
%   default_value - Input value `default_value`.
%
% Outputs:
%   value - Computed numeric value.

    value = default_value;
    if isfield(opts, name) && ~isempty(opts.(name))
        value = opts.(name);
    end
end
