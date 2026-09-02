function [events, rea_metrics] = detect_respiratory_asynchrony(data, baseline_or_config, resp_feat, config)
% detect_respiratory_asynchrony
% Label 5 - Respiratory Asynchrony / Dyssynchrony.
%
% Uses the wavelet phase-coherence core from Tomislav's script, reduced to
% the two respiratory belts. The time-localized phase coherence is averaged
% over three frequency bins and compared against the subject baseline.
% low_coherence_mask is evidence at the wavelet-localized time point; it is
% not a complete preceding fixed-duration state window. min_dur_sec is
% therefore applied directly once to its contiguous low-coherence runs.
% Local 20 Hz analysis is mapped back to config.fs master-grid events.

    if nargin == 2
        config = baseline_or_config;
        resp_feat = [];
    end

    events = empty_events();
    rea_metrics = compute_respiratory_asynchrony_metrics(data, resp_feat, config);

    if ~rea_metrics.valid_analysis
        fprintf('Skipping asyncB detection: %s\n', rea_skip_reason(rea_metrics.skip_code, rea_metrics.error_message));
        return;
    end

    do_plot = get_config_value(config, 'ReA', 'do_plot', false);

    N = size(data, 1);
    [events, rea_mask] = sustained_condition_to_events( ...
        rea_metrics.low_coherence_mask, rea_metrics.time_sec, config.fs, N, ...
        rea_metrics.min_dur_sec, 'respiratory_asynchrony');

    if do_plot
        plot_respiratory_asynchrony(data, config, rea_metrics.time_sec, rea_mask, rea_metrics);
    end
end

function msg = rea_skip_reason(skip_code, error_message)
    switch skip_code
        case 1
            msg = 'missing respiratory belt channel(s).';
        case 2
            msg = 'lung belt is marked missing for this recording.';
        case 3
            msg = 'lungs belt breathing features are invalid.';
        case 4
            msg = 'diaphragm belt breathing features are invalid.';
        case 5
            msg = 'at least one respiratory belt signal is unusable (all invalid/flat).';
        case 6
            msg = 'asynchrony frequency range is invalid for the signal sampling rate.';
        case 7
            msg = 'wavelet outputs were empty after alignment.';
        case 8
            if isempty(error_message)
                msg = 'wavelet coherence computation failed.';
            else
                msg = ['wavelet coherence computation failed (' error_message ').'];
            end
        case 9
            msg = 'no finite baseline-relative coherence evidence was available.';
        otherwise
            msg = 'input data do not support asynchrony computation.';
    end
end


function plot_respiratory_asynchrony(data, config, t_grid, rea_mask, rea_metrics)

    if ~isfield(config, 'channels')
        config = resolve_signal_channels(config);
    end
    idx_lungs = config.channels.lungs_idx;
    idx_diaph = config.channels.diaph_idx;
    t_raw = (0:size(data, 1)-1) / config.fs;

    fig = figure('Units','pixels','Position', near_fullscreen_figure_position(), 'Visible', config.make_figs_visible);
    tl = tiledlayout(5, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, ['RESPIRATORY ASYNCHRONY' newline 'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)])

    ax1 = nexttile(tl);
    plot_raw_panel(ax1, t_raw, data, idx_lungs, t_grid, rea_mask, 'Resp-Lungs with low-coherence regions', 'Resp-Lungs');

    ax2 = nexttile(tl);
    plot_raw_panel(ax2, t_raw, data, idx_diaph, t_grid, rea_mask, 'Resp-Diaphragm with low-coherence regions', 'Resp-Diaphragm');

    ax3 = nexttile(tl);
    plot_coherence_panel(ax3, t_grid, rea_metrics.phase_coherence_high, rea_metrics.thresholds.high, ...
        rea_metrics.baselines.high, rea_metrics.baseline_mask, rea_mask, ...
        sprintf('High-frequency phase coherence (> %.3g Hz)', rea_metrics.mid_high_cut_hz), rea_metrics.plot_step_sec);

    ax4 = nexttile(tl);
    plot_coherence_panel(ax4, t_grid, rea_metrics.phase_coherence_mid, rea_metrics.thresholds.mid, ...
        rea_metrics.baselines.mid, rea_metrics.baseline_mask, rea_mask, ...
        sprintf('Respiratory-band phase coherence (%.3g-%.3g Hz)', rea_metrics.low_mid_cut_hz, rea_metrics.mid_high_cut_hz), ...
        rea_metrics.plot_step_sec);

    ax5 = nexttile(tl);
    plot_coherence_panel(ax5, t_grid, rea_metrics.phase_coherence_low, rea_metrics.thresholds.low, ...
        rea_metrics.baselines.low, rea_metrics.baseline_mask, rea_mask, ...
        sprintf('Low-frequency phase coherence (< %.3g Hz)', rea_metrics.low_mid_cut_hz), rea_metrics.plot_step_sec);

    ax = [ax1 ax2 ax3 ax4 ax5];
    linkaxes(ax, 'x');
    if numel(t_grid) > 1
        right_pad = median(diff(t_grid), 'omitnan');
    else
        right_pad = 0;
    end
    xlim(ax1, [0 max(t_raw(end), t_grid(end)) + right_pad]);
    align_axes_x_widths(ax);
    set(fig, 'Visible', config.make_figs_visible);
    save_figure(config, 'respiratory_asynchrony');
end

function plot_raw_panel(ax, t_raw, data, idx, t_grid, rea_mask, title_text, y_text)
    if isempty(idx)
        text(ax, 0.5, 0.5, [y_text ' channel not found'], ...
            'Units', 'normalized', 'HorizontalAlignment', 'center');
        title(ax, title_text);
        xlabel(ax, 'Time (s)');
        ylabel(ax, y_text);
        grid(ax, 'on');
        return;
    end

    signal = data(:, idx);
    plot(ax, t_raw, signal, 'k');
    hold(ax, 'on');
    grid(ax, 'on');
    xlabel(ax, 'Time (s)');
    ylabel(ax, y_text);
    title(ax, title_text);
    shade_mask_on_axis(ax, t_grid, rea_mask);
    plot(ax, t_raw, signal, 'k');
    hold(ax, 'off');
end

function plot_coherence_panel(ax, t_grid, coherence, threshold, baseline_value, baseline_mask, rea_mask, title_text, plot_step_sec)
    held = held_median_trace(t_grid, coherence, plot_step_sec);

    ylim(ax, [0 1]);
    hold(ax, 'on');
    shade_baseline_on_axis(ax, t_grid, baseline_mask);
    shade_mask_on_axis(ax, t_grid, rea_mask);
    h_raw = plot(ax, t_grid, coherence, 'Color', [0.70 0.70 0.70], ...
        'LineWidth', 0.8, 'DisplayName', 'raw coherence');
    h_held = stairs(ax, t_grid, held, 'b', 'LineWidth', 1.4, ...
        'DisplayName', sprintf('%g s held median', plot_step_sec));

    if isfinite(baseline_value)
        h_baseline = yline(ax, baseline_value, 'k--', ...
            'DisplayName', 'baseline median');
    else
        h_baseline = gobjects(0);
    end
    if isfinite(threshold)
        h_threshold = yline(ax, threshold, 'r--', ...
            'DisplayName', 'deviation threshold');
    else
        h_threshold = gobjects(0);
    end

    legend_handles = [h_raw; h_held; h_baseline; h_threshold];
    legend_handles = legend_handles(isgraphics(legend_handles));
    legend_labels = get(legend_handles, 'DisplayName');
    if ischar(legend_labels) || isstring(legend_labels)
        legend_labels = cellstr(legend_labels);
    end
    legend(ax, legend_handles, legend_labels, 'Location', 'eastoutside', 'Box', 'off');
    hold(ax, 'off');
    grid(ax, 'on');
    xlabel(ax, 'Time (s)');
    ylabel(ax, 'WPhCoh');
    title(ax, title_text);
end

function held = held_median_trace(t_grid, values, step_sec)
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

function shade_baseline_on_axis(ax, t_grid, baseline_mask)
    if ~any(baseline_mask)
        return;
    end

    y_limits = ylim(ax);
    d = diff([false; baseline_mask(:); false]);
    starts = find(d == 1);
    ends = find(d == -1) - 1;

    for i = 1:numel(starts)
        x0 = t_grid(starts(i));
        x1 = t_grid(ends(i));
        patch(ax, [x0 x1 x1 x0], ...
              [y_limits(1) y_limits(1) y_limits(2) y_limits(2)], ...
              [0.85 0.88 0.92], ...
              'EdgeColor','none', ...
              'FaceAlpha',0.25);
    end
end
