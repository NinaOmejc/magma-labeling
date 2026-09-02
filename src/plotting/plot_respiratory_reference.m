function fig = plot_respiratory_reference(resp_feat, resp_ref, config)
% plot_respiratory_reference
% Plot the fixed protocol/session reference, whole-record context, and
% descriptive stability QC. Warnings retain data and do not request correction.

    fig = [];
    if ~isfield(config, 'resp_ref') || ~isfield(config.resp_ref, 'do_plot') || ...
            ~config.resp_ref.do_plot
        return;
    end

    fig = figure('Units', 'pixels', 'Position', near_fullscreen_figure_position(), ...
        'Visible', config.make_figs_visible, 'Color', 'w');
    tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, sprintf('RESPIRATORY AMPLITUDE REFERENCE | Subject %d | Measurement %d', ...
        config.subject, config.measure));

    ax1 = nexttile(tl);
    plot_belt_reference(ax1, get_belt(resp_feat, 'lungs'), resp_ref.lungs, 'Resp-Lungs');
    ax2 = nexttile(tl);
    plot_belt_reference(ax2, get_belt(resp_feat, 'diaph'), resp_ref.diaph, 'Resp-Diaphragm');

    linkaxes([ax1 ax2], 'x');
    align_axes_x_widths([ax1 ax2]);
    save_figure(config, 'respiratory_reference');
end

function plot_belt_reference(ax, breaths, belt, belt_name)
    hold(ax, 'on');
    grid(ax, 'on');
    xlabel(ax, 'Breath peak time (s)');
    ylabel(ax, 'Belt excursion (raw units)');

    [peak_t, amp] = valid_amplitudes(breaths);
    if isempty(peak_t)
        text(ax, 0.5, 0.5, sprintf('%s unavailable | reference quality: %s', ...
            belt_name, belt.reference_quality), ...
            'Units', 'normalized', 'HorizontalAlignment', 'center');
        title(ax, belt_name);
        hold(ax, 'off');
        return;
    end

    h_amp = plot(ax, peak_t, amp, '.-', 'Color', [0.20 0.35 0.70], ...
        'DisplayName', 'reviewed breath amplitude');
    shade_session_region(ax, belt.session.start_t, belt.session.end_t);
    shade_edge_regions(ax, peak_t, belt.edge_window_sec_used);

    handles = gobjects(0);
    handles(end+1) = h_amp;
    if belt.session.available
        h_session = yline(ax, belt.session.value, '-', 'Color', [0.45 0.10 0.65], ...
            'LineWidth', 2, 'DisplayName', 'fixed session median');
        handles(end+1) = h_session;
    end
    if belt.global.available
        h_global = yline(ax, belt.global.value, ':', 'Color', [0.15 0.15 0.15], ...
            'LineWidth', 1.5, 'DisplayName', 'whole-record median');
        handles(end+1) = h_global;
    end
    if isfinite(belt.start_ref)
        h_start = yline(ax, belt.start_ref, '--', 'Color', [0.10 0.55 0.25], ...
            'DisplayName', 'early median');
        handles(end+1) = h_start;
    end
    if isfinite(belt.end_ref)
        h_end = yline(ax, belt.end_ref, '--', 'Color', [0.80 0.35 0.10], ...
            'DisplayName', 'late median');
        handles(end+1) = h_end;
    end

    if belt.change_detected
        h_change = xline(ax, belt.change_t, 'k--', 'LineWidth', 1.5, ...
            'DisplayName', 'change candidate');
        h_before = plot(ax, [peak_t(1) belt.change_t], [belt.ref_before belt.ref_before], ...
            'Color', [0.35 0.35 0.35], 'LineWidth', 1.2, 'DisplayName', 'candidate level before');
        h_after = plot(ax, [belt.change_t peak_t(end)], [belt.ref_after belt.ref_after], ...
            'Color', [0.60 0.30 0.30], 'LineWidth', 1.2, 'DisplayName', 'candidate level after');
        handles = [handles h_change h_before h_after];
    end

    change_text = 'no';
    if belt.change_detected
        change_text = 'yes';
    end
    title(ax, sprintf(['%s | session=%s | global/session=%s | reference quality=%s' ...
        ' | change candidate=%s | action=retain data, no correction'], ...
        belt_name, numeric_text(belt.session.value), ...
        numeric_text(belt.global_to_session_ratio), belt.reference_quality, change_text), ...
        'Interpreter', 'none');
    legend(ax, handles(isgraphics(handles)), 'Location', 'eastoutside');
    hold(ax, 'off');

end

function shade_session_region(ax, start_t, end_t)
    if ~isfinite(start_t) || ~isfinite(end_t) || end_t <= start_t
        return;
    end
    y_limits = robust_plot_limits(ax);
    patch(ax, [start_t end_t end_t start_t], ...
        [y_limits(1) y_limits(1) y_limits(2) y_limits(2)], [0.82 0.78 0.96], ...
        'EdgeColor', 'none', 'FaceAlpha', 0.16, 'HandleVisibility', 'off');
end

function shade_edge_regions(ax, peak_t, edge_window_sec)
    if ~isfinite(edge_window_sec) || edge_window_sec <= 0
        return;
    end
    y_limits = robust_plot_limits(ax);
    t0 = peak_t(1);
    t1 = peak_t(end);
    patch(ax, [t0 t0+edge_window_sec t0+edge_window_sec t0], ...
        [y_limits(1) y_limits(1) y_limits(2) y_limits(2)], [0.80 0.92 0.82], ...
        'EdgeColor', 'none', 'FaceAlpha', 0.18, 'HandleVisibility', 'off');
    patch(ax, [t1-edge_window_sec t1 t1 t1-edge_window_sec], ...
        [y_limits(1) y_limits(1) y_limits(2) y_limits(2)], [0.98 0.86 0.76], ...
        'EdgeColor', 'none', 'FaceAlpha', 0.18, 'HandleVisibility', 'off');
end

function y_limits = robust_plot_limits(ax)
    y_limits = ylim(ax);
    if ~all(isfinite(y_limits)) || y_limits(1) == y_limits(2)
        y_limits = [0 1];
    end
end

function [peak_t, amp] = valid_amplitudes(breaths)
    peak_t = [];
    amp = [];
    if isempty(breaths) || ~isstruct(breaths) || ...
            ~isfield(breaths, 'peak_t') || ~isfield(breaths, 'amp')
        return;
    end
    n = min(numel(breaths.peak_t), numel(breaths.amp));
    peak_t = breaths.peak_t(1:n);
    amp = breaths.amp(1:n);
    peak_t = peak_t(:);
    amp = amp(:);
    valid = isfinite(peak_t) & isfinite(amp) & amp > 0;
    peak_t = peak_t(valid);
    amp = amp(valid);
    [peak_t, order] = sort(peak_t, 'ascend');
    amp = amp(order);
end

function breaths = get_belt(resp_feat, name)
    breaths = [];
    if isstruct(resp_feat) && isfield(resp_feat, name)
        breaths = resp_feat.(name);
    end
end

function value = numeric_text(x)
    if isfinite(x)
        value = sprintf('%.3f', x);
    else
        value = 'n/a';
    end
end
