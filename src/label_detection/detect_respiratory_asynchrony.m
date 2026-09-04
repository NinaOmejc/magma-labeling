function [events, rea_metrics] = detect_respiratory_asynchrony( ...
    data, session_reference, resp_cycles, config)
% DETECT_RESPIRATORY_ASYNCHRONY Detect respiratory asynchrony.
%
% Syntax:
%   [events, rea_metrics] = detect_respiratory_asynchrony(data, session_reference, resp_cycles, config)
%
% Inputs:
%   data - Input physiological signal data.
%   session_reference - Session-reference metadata.
%   resp_cycles - Respiratory-cycle structure.
%   config - Pipeline configuration structure.
%
% Outputs:
%   events - Event structure array.
%   rea_metrics - Computed output value `rea_metrics`.

    events = empty_events();
    rea_metrics = compute_respiratory_asynchrony_metrics( ...
        data, resp_cycles, session_reference, config);

    if ~rea_metrics.valid_analysis
        fprintf('Skipping async detection: %s\n', rea_skip_reason(rea_metrics.skip_code, rea_metrics.error_message));
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
% REA_SKIP_REASON Perform the rea skip reason operation.
%
% Syntax:
%   msg = rea_skip_reason(skip_code, error_message)
%
% Inputs:
%   skip_code - Input value `skip_code`.
%   error_message - Input value `error_message`.
%
% Outputs:
%   msg - Computed output value `msg`.

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
            msg = 'no finite session-reference-relative coherence evidence was available.';
        otherwise
            msg = 'input data do not support asynchrony computation.';
    end
end


function plot_respiratory_asynchrony(data, config, t_grid, rea_mask, rea_metrics)
% PLOT_RESPIRATORY_ASYNCHRONY Plot respiratory asynchrony.
%
% Syntax:
%   plot_respiratory_asynchrony(data, config, t_grid, rea_mask, rea_metrics)
%
% Inputs:
%   data - Input physiological signal data.
%   config - Pipeline configuration structure.
%   t_grid - Time coordinates in seconds.
%   rea_mask - Logical state or selection mask.
%   rea_metrics - Input value `rea_metrics`.

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
        rea_metrics.references.high, rea_metrics.reference_mask, rea_mask, ...
        sprintf('High-frequency phase coherence (> %.3g Hz)', rea_metrics.mid_high_cut_hz), rea_metrics.plot_step_sec);

    ax4 = nexttile(tl);
    plot_coherence_panel(ax4, t_grid, rea_metrics.phase_coherence_mid, rea_metrics.thresholds.mid, ...
        rea_metrics.references.mid, rea_metrics.reference_mask, rea_mask, ...
        sprintf('Respiratory-band phase coherence (%.3g-%.3g Hz)', rea_metrics.low_mid_cut_hz, rea_metrics.mid_high_cut_hz), ...
        rea_metrics.plot_step_sec);

    ax5 = nexttile(tl);
    plot_coherence_panel(ax5, t_grid, rea_metrics.phase_coherence_low, rea_metrics.thresholds.low, ...
        rea_metrics.references.low, rea_metrics.reference_mask, rea_mask, ...
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
% PLOT_RAW_PANEL Plot raw panel.
%
% Syntax:
%   plot_raw_panel(ax, t_raw, data, idx, t_grid, rea_mask, title_text, y_text)
%
% Inputs:
%   ax - Target axes handle.
%   t_raw - Time coordinates in seconds.
%   data - Input physiological signal data.
%   idx - Input value `idx`.
%   t_grid - Time coordinates in seconds.
%   rea_mask - Logical state or selection mask.
%   title_text - Input value `title_text`.
%   y_text - Input value `y_text`.

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

function plot_coherence_panel(ax, t_grid, coherence, threshold, reference_value, reference_mask, rea_mask, title_text, plot_step_sec)
% PLOT_COHERENCE_PANEL Plot coherence panel.
%
% Syntax:
%   plot_coherence_panel(ax, t_grid, coherence, threshold, reference_value, reference_mask, rea_mask, title_text, plot_step_sec)
%
% Inputs:
%   ax - Target axes handle.
%   t_grid - Time coordinates in seconds.
%   coherence - Input value `coherence`.
%   threshold - Selection threshold value.
%   reference_value - Session-reference metadata.
%   reference_mask - Logical state or selection mask.
%   rea_mask - Logical state or selection mask.
%   title_text - Input value `title_text`.
%   plot_step_sec - Duration or window length in seconds.

    held = held_median_trace(t_grid, coherence, plot_step_sec);

    ylim(ax, [0 1]);
    hold(ax, 'on');
    shade_reference_on_axis(ax, t_grid, reference_mask);
    shade_mask_on_axis(ax, t_grid, rea_mask);
    h_raw = plot(ax, t_grid, coherence, 'Color', [0.70 0.70 0.70], ...
        'LineWidth', 0.8, 'DisplayName', 'raw coherence');
    h_held = stairs(ax, t_grid, held, 'b', 'LineWidth', 1.4, ...
        'DisplayName', sprintf('%g s held median', plot_step_sec));

    if isfinite(reference_value)
        h_reference = yline(ax, reference_value, 'k--', ...
            'DisplayName', 'session reference median');
    else
        h_reference = gobjects(0);
    end
    if isfinite(threshold)
        h_threshold = yline(ax, threshold, 'r--', ...
            'DisplayName', 'deviation threshold');
    else
        h_threshold = gobjects(0);
    end

    legend_handles = [h_raw; h_held; h_reference; h_threshold];
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
% HELD_MEDIAN_TRACE Perform the held median trace operation.
%
% Syntax:
%   held = held_median_trace(t_grid, values, step_sec)
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

function shade_reference_on_axis(ax, t_grid, reference_mask)
% SHADE_REFERENCE_ON_AXIS Perform the shade reference on axis operation.
%
% Syntax:
%   shade_reference_on_axis(ax, t_grid, reference_mask)
%
% Inputs:
%   ax - Target axes handle.
%   t_grid - Time coordinates in seconds.
%   reference_mask - Logical state or selection mask.

    if ~any(reference_mask)
        return;
    end

    y_limits = ylim(ax);
    d = diff([false; reference_mask(:); false]);
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
