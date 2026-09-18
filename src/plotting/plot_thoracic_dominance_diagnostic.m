function plot_thoracic_dominance_diagnostic( ...
    data, t_grid, evidence, dominance_mask, events, config)
% PLOT_THORACIC_DOMINANCE_DIAGNOSTIC Show raw belts, balance, and events.
%
% Inputs:
%   data          - Nsample x Nchannel raw physiological signals.
%   t_grid        - Ngrid analysis times in seconds.
%   evidence      - Thoracic-balance traces and endpoint mask on t_grid,
%                   plus the unitless dominance ratio threshold.
%   dominance_mask - Ngrid logical back-projected state support.
%   events        - Retained thoracic-dominance event intervals in seconds.
%   config        - Recording identity and plot-output settings.

    if ~isfield(config, 'channels')
        config = resolve_signal_channels(config);
    end
    idx_lungs = config.channels.lungs_idx;
    idx_diaph = config.channels.diaph_idx;
    t_raw = (0:size(data, 1) - 1) / config.fs;

    fig = figure('Units', 'pixels', 'Position', near_fullscreen_figure_position(), ...
        'Visible', config.make_figs_visible, 'Color', 'w');
    tl = tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, ['RELATIVE THORACOABDOMINAL EXCURSION BALANCE' newline ...
        'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure) newline ...
        'Operational automatic label; independently session-normalized uncalibrated belts'])

    ax1 = nexttile(tl); hold(ax1, 'on');
    has_raw = false;
    if valid_raw_channel(idx_lungs, size(data, 2))
        plot(ax1, t_raw, data(:, idx_lungs), 'k', ...
            'DisplayName', 'thoracic / lungs belt');
        has_raw = true;
    end
    if valid_raw_channel(idx_diaph, size(data, 2))
        plot(ax1, t_raw, data(:, idx_diaph), 'Color', [0.10 0.35 0.90], ...
            'DisplayName', 'abdominal / diaphragm belt');
        has_raw = true;
    end
    if ~has_raw
        text(ax1, 0.5, 0.5, 'No usable raw respiratory belts', ...
            'Units', 'normalized', 'HorizontalAlignment', 'center');
    end
    event_handles = shade_events_on_axis( ...
        ax1, events, 'final thoracic-dominance event');
    title(ax1, 'Raw respiratory belts + final thoracic-dominance events');
    ylabel(ax1, 'Raw effort'); grid(ax1, 'on');
    if has_raw || ~isempty(event_handles)
        legend(ax1, 'show', 'Location', 'eastoutside', 'Box', 'off');
    end
    hold(ax1, 'off');

    ax2 = nexttile(tl); hold(ax2, 'on');
    plot(ax2, t_grid, evidence.thoracic_ratio_window_median, 'k', ...
        'LineWidth', 2, 'DisplayName', 'thoracic normalized excursion');
    plot(ax2, t_grid, evidence.abdominal_ratio_window_median, ...
        'Color', [0.10 0.35 0.90], 'LineWidth', 2, ...
        'DisplayName', 'abdominal normalized excursion');
    yline(ax2, 1, 'k:', 'DisplayName', 'session reference');
    shade_mask_on_axis(ax2, t_grid, dominance_mask);
    shade_events_on_axis(ax2, events, 'final thoracic-dominance event');
    title(ax2, 'Session-normalized thoracic and abdominal excursion');
    ylabel(ax2, 'Normalized excursion'); grid(ax2, 'on');
    legend(ax2, 'show', 'Location', 'eastoutside', 'Box', 'off');
    hold(ax2, 'off');

    ax3 = nexttile(tl); hold(ax3, 'on');
    plot(ax3, t_grid, evidence.thoracic_to_abdominal_ratio, ...
        'Color', [0.85 0.33 0.10], 'LineWidth', 2, ...
        'DisplayName', 'thoracic / abdominal excursion ratio');
    endpoint_idx = evidence.dominance_endpoint_mask & ...
        isfinite(evidence.thoracic_to_abdominal_ratio);
    scatter(ax3, t_grid(endpoint_idx), ...
        evidence.thoracic_to_abdominal_ratio(endpoint_idx), 16, ...
        [0.65 0.05 0.05], 'filled', 'DisplayName', ...
        'Qualifying analysis-window endpoint');
    yline(ax3, evidence.dominance_ratio_threshold, 'r--', ...
        sprintf('Operational threshold = %.2f', evidence.dominance_ratio_threshold), ...
        'LineWidth', 2, 'LabelHorizontalAlignment', 'left', ...
        'DisplayName', 'dominance threshold');
    yline(ax3, 1, 'k:', 'DisplayName', 'equal normalized excursion');
    shade_mask_on_axis(ax3, t_grid, dominance_mask);
    shade_events_on_axis(ax3, events, 'final thoracic-dominance event');
    title(ax3, ['Relative thoracic / abdominal normalized excursion ratio' newline ...
        'Dots = evidence endpoints; shading = inferred sustained state']);
    xlabel(ax3, 'Time (s)'); ylabel(ax3, 'Ratio'); grid(ax3, 'on');
    legend(ax3, 'show', 'Location', 'eastoutside', 'Box', 'off');
    hold(ax3, 'off');

    ax = [ax1 ax2 ax3];
    linkaxes(ax, 'x');
    if ~isempty(t_raw)
        xlim(ax1, [0 t_raw(end)]);
    end
    align_axes_x_widths(ax);
    set(fig, 'Visible', config.make_figs_visible);
    save_figure(config, 'thoracic_dominant_breathing');
end

function valid = valid_raw_channel(index, n_channels)
% VALID_RAW_CHANNEL Check one resolved channel index for plotting.

    valid = isscalar(index) && isfinite(index) && ...
        index >= 1 && index <= n_channels;
end
