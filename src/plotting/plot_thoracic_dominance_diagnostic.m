function plot_thoracic_dominance_diagnostic(t_grid, evidence, dominance_mask, events, config)
% plot_thoracic_dominance_diagnostic
% Plot within-record normalized thoracoabdominal excursion balance.

    fig = figure('Units', 'pixels', 'Position', near_fullscreen_figure_position(), ...
        'Visible', config.make_figs_visible, 'Color', 'w');
    tl = tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, ['RELATIVE THORACOABDOMINAL EXCURSION BALANCE' newline ...
        'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure) newline ...
        'Operational weak label; independently session-normalized uncalibrated belts'])

    ax1 = nexttile(tl); hold(ax1, 'on');
    plot(ax1, t_grid, evidence.thoracic_ratio_window_median, 'k', 'LineWidth', 1.2);
    yline(ax1, 1, 'k:');
    shade_mask_on_axis(ax1, t_grid, dominance_mask);
    shade_events_on_axis(ax1, events, 'Thoracic-dominant interval');
    title(ax1, 'Thoracic-belt excursion / thoracic session reference');
    ylabel(ax1, 'Normalized excursion'); grid(ax1, 'on'); hold(ax1, 'off');

    ax2 = nexttile(tl); hold(ax2, 'on');
    plot(ax2, t_grid, evidence.abdominal_ratio_window_median, 'b', 'LineWidth', 1.2);
    yline(ax2, 1, 'k:');
    shade_mask_on_axis(ax2, t_grid, dominance_mask);
    shade_events_on_axis(ax2, events, 'Thoracic-dominant interval');
    title(ax2, 'Abdominal-belt excursion / abdominal session reference');
    ylabel(ax2, 'Normalized excursion'); grid(ax2, 'on'); hold(ax2, 'off');

    ax3 = nexttile(tl); hold(ax3, 'on');
    plot(ax3, t_grid, evidence.thoracic_to_abdominal_ratio, ...
        'Color', [0.85 0.33 0.10], 'LineWidth', 1.4);
    endpoint_idx = evidence.dominance_endpoint_mask & ...
        isfinite(evidence.thoracic_to_abdominal_ratio);
    scatter(ax3, t_grid(endpoint_idx), ...
        evidence.thoracic_to_abdominal_ratio(endpoint_idx), 16, ...
        [0.65 0.05 0.05], 'filled', 'DisplayName', ...
        'Qualifying analysis-window endpoint');
    yline(ax3, evidence.dominance_ratio_threshold, 'r--', ...
        sprintf('Operational threshold = %.2f', evidence.dominance_ratio_threshold), ...
        'LabelHorizontalAlignment', 'left');
    yline(ax3, 1, 'k:');
    shade_mask_on_axis(ax3, t_grid, dominance_mask);
    shade_events_on_axis(ax3, events, 'Thoracic-dominant interval');
    title(ax3, ['Relative thoracic / abdominal normalized excursion ratio' newline ...
        'Dots = evidence endpoints; shading = inferred sustained state']);
    xlabel(ax3, 'Time (s)'); ylabel(ax3, 'Ratio'); grid(ax3, 'on'); hold(ax3, 'off');

    ax = [ax1 ax2 ax3];
    linkaxes(ax, 'x');
    if ~isempty(t_grid)
        xlim(ax1, [0 t_grid(end)]);
    end
    align_axes_x_widths(ax);
    set(fig, 'Visible', config.make_figs_visible);
    save_figure(config, 'thoracic_dominant_breathing');
end
