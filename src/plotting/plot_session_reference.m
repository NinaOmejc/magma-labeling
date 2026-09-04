function fig = plot_session_reference( ...
    data, resp_cycles, resp_ref, spo2_ref, session_reference, config)
% PLOT_SESSION_REFERENCE Plot session reference.
%
% Syntax:
%   fig = plot_session_reference(data, resp_cycles, resp_ref, spo2_ref, session_reference, config)
%
% Inputs:
%   data - Input physiological signal data.
%   resp_cycles - Respiratory-cycle structure.
%   resp_ref - Respiratory-reference structure.
%   spo2_ref - SpO2-reference structure.
%   session_reference - Session-reference metadata.
%   config - Pipeline configuration structure.
%
% Outputs:
%   fig - Figure handle.

    fig = [];
    if ~isfield(config, 'reference') || ...
            ~isfield(config.reference, 'do_plot') || ~config.reference.do_plot
        return;
    end

    fig = figure('Units', 'pixels', 'Position', near_fullscreen_figure_position(), ...
        'Visible', config.make_figs_visible, 'Color', 'w');
    tl = tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, sprintf('SESSION PHYSIOLOGICAL REFERENCE | Subject %d | Measurement %d', ...
        config.subject, config.measure));

    ax1 = nexttile(tl);
    plot_belt_reference(ax1, get_belt(resp_cycles, 'lungs'), ...
        resp_ref.lungs, session_reference, 'Resp-Lungs');
    ax2 = nexttile(tl);
    plot_belt_reference(ax2, get_belt(resp_cycles, 'diaph'), ...
        resp_ref.diaph, session_reference, 'Resp-Diaphragm');
    ax3 = nexttile(tl);
    plot_spo2_reference(ax3, data, spo2_ref, session_reference, config);

    linkaxes([ax1 ax2 ax3], 'x');
    align_axes_x_widths([ax1 ax2 ax3]);
    save_figure(config, 'session_reference');
end

function plot_belt_reference(ax, breaths, belt, session_reference, belt_name)
% PLOT_BELT_REFERENCE Plot belt reference.
%
% Syntax:
%   plot_belt_reference(ax, breaths, belt, session_reference, belt_name)
%
% Inputs:
%   ax - Target axes handle.
%   breaths - Respiratory-cycle or belt-evidence structure.
%   belt - Respiratory-cycle or belt-evidence structure.
%   session_reference - Session-reference metadata.
%   belt_name - Input value `belt_name`.

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
        'DisplayName', 'breath amplitude');
    shade_session_reference_on_axis( ...
        ax, session_reference, 'common session-reference interval');
    shade_edge_regions(ax, peak_t, belt.edge_window_sec_used);

    handles = gobjects(0);
    handles(end+1) = h_amp;
    if belt.session.available
        h_session = yline(ax, belt.session.value, '-', 'Color', [0.45 0.10 0.65], ...
            'LineWidth', 2, 'DisplayName', 'session reference median');
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

function plot_spo2_reference(ax, data, spo2_ref, session_reference, config)
% PLOT_SPO2_REFERENCE Plot spo2 reference.
%
% Syntax:
%   plot_spo2_reference(ax, data, spo2_ref, session_reference, config)
%
% Inputs:
%   ax - Target axes handle.
%   data - Input physiological signal data.
%   spo2_ref - SpO2-reference structure.
%   session_reference - Session-reference metadata.
%   config - Pipeline configuration structure.

    hold(ax, 'on');
    grid(ax, 'on');
    xlabel(ax, 'Time (s)');
    ylabel(ax, 'SpO2 (%)');

    quality = 'not_evaluated';
    if isstruct(spo2_ref) && isfield(spo2_ref, 'quality')
        quality = char(string(spo2_ref.quality));
    end
    title(ax, sprintf('SpO2 | reference quality=%s', quality), ...
        'Interpreter', 'none');

    if ~isfield(config, 'channels')
        config = resolve_signal_channels(config);
    end
    idx_spo2 = config.channels.spo2_idx;
    if isempty(idx_spo2) || isempty(data) || idx_spo2 > size(data, 2)
        text(ax, 0.5, 0.5, 'SpO2 unavailable', 'Units', 'normalized', ...
            'HorizontalAlignment', 'center');
        hold(ax, 'off');
        return;
    end

    spo2 = data(:, idx_spo2);
    if ~any(isfinite(spo2))
        text(ax, 0.5, 0.5, 'SpO2 unavailable', 'Units', 'normalized', ...
            'HorizontalAlignment', 'center');
        hold(ax, 'off');
        return;
    end

    t = (0:numel(spo2)-1)' / config.fs;
    h_spo2 = plot(ax, t, spo2, 'k', 'DisplayName', 'SpO2');
    shade_session_reference_on_axis( ...
        ax, session_reference, 'common session-reference interval');
    handles = h_spo2;
    if isstruct(spo2_ref) && isfield(spo2_ref, 'median_percent') && ...
            isfinite(spo2_ref.median_percent)
        handles(end+1) = yline(ax, spo2_ref.median_percent, 'k--', ...
            'LineWidth', 1.5, 'DisplayName', 'session SpO2 reference median');
    end
    legend(ax, handles, 'Location', 'eastoutside');
    hold(ax, 'off');
end

function shade_edge_regions(ax, peak_t, edge_window_sec)
% SHADE_EDGE_REGIONS Perform the shade edge regions operation.
%
% Syntax:
%   shade_edge_regions(ax, peak_t, edge_window_sec)
%
% Inputs:
%   ax - Target axes handle.
%   peak_t - Input value `peak_t`.
%   edge_window_sec - Duration or window length in seconds.

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
% ROBUST_PLOT_LIMITS Perform the robust plot limits operation.
%
% Syntax:
%   y_limits = robust_plot_limits(ax)
%
% Inputs:
%   ax - Target axes handle.
%
% Outputs:
%   y_limits - Computed output value `y_limits`.

    y_limits = ylim(ax);
    if ~all(isfinite(y_limits)) || y_limits(1) == y_limits(2)
        y_limits = [0 1];
    end
end

function [peak_t, amp] = valid_amplitudes(breaths)
% VALID_AMPLITUDES Perform the valid amplitudes operation.
%
% Syntax:
%   [peak_t, amp] = valid_amplitudes(breaths)
%
% Inputs:
%   breaths - Respiratory-cycle or belt-evidence structure.
%
% Outputs:
%   peak_t - Computed output value `peak_t`.
%   amp - Computed output value `amp`.

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

function breaths = get_belt(resp_cycles, name)
% GET_BELT Return belt.
%
% Syntax:
%   breaths = get_belt(resp_cycles, name)
%
% Inputs:
%   resp_cycles - Respiratory-cycle structure.
%   name - Input value `name`.
%
% Outputs:
%   breaths - Updated respiratory-cycle or belt structure.

    breaths = [];
    if isstruct(resp_cycles) && isfield(resp_cycles, name)
        breaths = resp_cycles.(name);
    end
end

function value = numeric_text(x)
% NUMERIC_TEXT Perform the numeric text operation.
%
% Syntax:
%   value = numeric_text(x)
%
% Inputs:
%   x - Input value `x`.
%
% Outputs:
%   value - Computed numeric value.

    if isfinite(x)
        value = sprintf('%.3f', x);
    else
        value = 'n/a';
    end
end
