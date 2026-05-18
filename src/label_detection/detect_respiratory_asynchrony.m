function [events, rea_metrics] = detect_respiratory_asynchrony(data, baseline_or_config, breaths_lungs, breaths_diaph, config)
% detect_respiratory_asynchrony
% Label 5 - Respiratory Asynchrony / Dyssynchrony.
%
% Uses the wavelet phase-coherence core from Tomislav's script, reduced to
% the two respiratory belts. The time-localized phase coherence is averaged
% over three frequency bins and compared against the subject baseline.

    if nargin == 2
        config = baseline_or_config;
        breaths_lungs = [];
        breaths_diaph = [];
    end

    events = empty_events();
    rea_metrics = compute_respiratory_asynchrony_metrics(data, breaths_lungs, breaths_diaph, config);

    if ~rea_metrics.valid_analysis
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


function plot_respiratory_asynchrony(data, config, t_grid, rea_mask, rea_metrics)

    idx_lungs = find(strcmp(config.data_columns, 'Resp-Lungs'), 1);
    idx_diaph = find(strcmp(config.data_columns, 'Resp-Diaphragm'), 1);
    t_raw = (0:size(data, 1)-1) / config.fs;

    figure('Units','pixels','Position', near_fullscreen_figure_position(), 'Visible', config.make_figs_visible);
    sgtitle(['RESPIRATORY ASYNCHRONY' newline 'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)])

    ax1 = subplot(5,1,1);
    plot_raw_panel(t_raw, data(:, idx_lungs), t_grid, rea_mask, 'Resp-Lungs with low-coherence regions', 'Resp-Lungs');

    ax2 = subplot(5,1,2);
    plot_raw_panel(t_raw, data(:, idx_diaph), t_grid, rea_mask, 'Resp-Diaphragm with low-coherence regions', 'Resp-Diaphragm');

    ax3 = subplot(5,1,3);
    plot_coherence_panel(t_grid, rea_metrics.phase_coherence_high, rea_metrics.thresholds.high, ...
        rea_metrics.baselines.high, rea_metrics.baseline_mask, rea_mask, ...
        sprintf('High-frequency phase coherence (> %.3g Hz)', rea_metrics.mid_high_cut_hz), rea_metrics.plot_step_sec);

    ax4 = subplot(5,1,4);
    plot_coherence_panel(t_grid, rea_metrics.phase_coherence_mid, rea_metrics.thresholds.mid, ...
        rea_metrics.baselines.mid, rea_metrics.baseline_mask, rea_mask, ...
        sprintf('Respiratory-band phase coherence (%.3g-%.3g Hz)', rea_metrics.low_mid_cut_hz, rea_metrics.mid_high_cut_hz), ...
        rea_metrics.plot_step_sec);

    ax5 = subplot(5,1,5);
    plot_coherence_panel(t_grid, rea_metrics.phase_coherence_low, rea_metrics.thresholds.low, ...
        rea_metrics.baselines.low, rea_metrics.baseline_mask, rea_mask, ...
        sprintf('Low-frequency phase coherence (< %.3g Hz)', rea_metrics.low_mid_cut_hz), rea_metrics.plot_step_sec);

    ax = [ax1 ax2 ax3 ax4 ax5];
    linkaxes(ax, 'x');
    xlim(ax1, [0 t_grid(end)]);
    save_figure(config, 'respiratory_asynchrony');
end

function plot_raw_panel(t_raw, signal, t_grid, rea_mask, title_text, y_text)
    plot(t_raw, signal, 'k');
    hold on;
    grid on;
    xlabel('Time (s)');
    ylabel(y_text);
    title(title_text);
    shade_mask_on_axis(t_grid, rea_mask);
    plot(t_raw, signal, 'k');
    hold off;
end

function plot_coherence_panel(t_grid, coherence, threshold, baseline_value, baseline_mask, rea_mask, title_text, plot_step_sec)
    held = held_median_trace(t_grid, coherence, plot_step_sec);

    ylim([0 1]);
    hold on;
    shade_baseline_on_axis(t_grid, baseline_mask);
    shade_mask_on_axis(t_grid, rea_mask);
    plot(t_grid, coherence, 'Color', [0.70 0.70 0.70], 'LineWidth', 0.8);
    stairs(t_grid, held, 'b', 'LineWidth', 1.4);

    if isfinite(baseline_value)
        yline(baseline_value, 'k--', 'Baseline median', ...
            'LabelHorizontalAlignment', 'left', 'LabelVerticalAlignment', 'bottom');
    end
    if isfinite(threshold)
        yline(threshold, 'r--', 'Deviation threshold', ...
            'LabelHorizontalAlignment', 'left', 'LabelVerticalAlignment', 'top');
    end

    hold off;
    grid on;
    xlabel('Time (s)');
    ylabel('WPhCoh');
    title(title_text);
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

function shade_baseline_on_axis(t_grid, baseline_mask)
    if ~any(baseline_mask)
        return;
    end

    ax = gca;
    y_limits = ylim;
    d = diff([false; baseline_mask(:); false]);
    starts = find(d == 1);
    ends = find(d == -1) - 1;

    for i = 1:numel(starts)
        x0 = t_grid(starts(i));
        x1 = t_grid(ends(i));
        patch([x0 x1 x1 x0], ...
              [y_limits(1) y_limits(1) y_limits(2) y_limits(2)], ...
              [0.85 0.88 0.92], ...
              'EdgeColor','none', ...
              'FaceAlpha',0.25);
    end

    axes(ax);
end
