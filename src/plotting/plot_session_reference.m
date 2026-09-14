function fig = plot_session_reference( ...
    data, resp_cycles, resp_ref, session_reference, config)
% PLOT_SESSION_REFERENCE Visualize belt values used for session baselines.
%
% Inputs:
%   data              - Nsample x Nchannel physiological signal matrix.
%   resp_cycles       - Extracted lung and diaphragm breath structures.
%   resp_ref          - Per-belt session/global amplitude references and QC.
%   session_reference - Common reference interval with boundaries in seconds.
%   config            - Channel, recording identity, and plot-output settings.
%
% Outputs:
%   fig - Figure handle, or empty when plotting is disabled.

    fig = [];
    if ~isfield(config, 'reference') || ...
            ~isfield(config.reference, 'do_plot') || ~config.reference.do_plot
        return;
    end

    fig = figure('Units', 'pixels', 'Position', near_fullscreen_figure_position(), ...
        'Visible', config.make_figs_visible, 'Color', 'w');
    tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, sprintf('SESSION PHYSIOLOGICAL REFERENCE | Subject %d | Measurement %d', ...
        config.subject, config.measure));

    ax1 = nexttile(tl);
    plot_belt_reference(ax1, get_belt(resp_cycles, 'lungs'), ...
        resp_ref.lungs, session_reference, 'Resp-Lungs');
    ax2 = nexttile(tl);
    plot_belt_reference(ax2, get_belt(resp_cycles, 'diaph'), ...
        resp_ref.diaph, session_reference, 'Resp-Diaphragm');

    linkaxes([ax1 ax2], 'x');
    align_axes_x_widths([ax1 ax2]);
    save_figure(config, 'session_reference');
end

function plot_belt_reference(ax, breaths, belt, session_reference, belt_name)
% PLOT_BELT_REFERENCE Compare breath excursion with session and global references.
% breaths supplies breath-level peak_t (seconds) and amp (raw belt units);
% belt supplies reference values, edge QC, and optional change-point evidence.

    hold(ax, 'on');
    grid(ax, 'on');
    xlabel(ax, 'Breath peak time (s)');
    ylabel(ax, 'Belt excursion (raw units)');

    [peak_t, amp] = valid_amplitudes(breaths);
    if isempty(peak_t)
        text(ax, 0.5, 0.5, sprintf('%s unavailable | reference quality: %s', ...
            belt_name, strrep(belt.reference_quality, '_', ' ')), ...
            'Units', 'normalized', 'HorizontalAlignment', 'center');
        title(ax, belt_name);
        hold(ax, 'off');
        return;
    end

    h_amp = plot(ax, peak_t, amp, '.-', 'Color', [0.20 0.35 0.70], ...
        'DisplayName', 'breath amplitude');
    h_reference_window = shade_session_reference_on_axis( ...
        ax, session_reference, 'common session-reference interval');
    [h_early_window, h_late_window] = shade_edge_regions( ...
        ax, peak_t, belt.edge_window_sec_used);

    handles = gobjects(0);
    handles(end+1) = h_amp;
    if ~isempty(h_reference_window) && isgraphics(h_reference_window)
        handles(end+1) = h_reference_window;
    end
    if ~isempty(h_early_window) && isgraphics(h_early_window)
        handles(end+1) = h_early_window;
    end
    if ~isempty(h_late_window) && isgraphics(h_late_window)
        handles(end+1) = h_late_window;
    end
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
% PLOT_SPO2_REFERENCE Plot sample-level SpO2 and its session median.
% data is the physiological signal matrix; config resolves the SpO2 column
% and fs, while session_reference supplies the shaded interval in seconds.

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
        handles(end+1) = yline(ax, spo2_ref.median_percent, 'r--', ...
            'LineWidth', 1.5, 'DisplayName', 'session SpO2 reference median');
    end
    legend(ax, handles, 'Location', 'eastoutside');
    hold(ax, 'off');
end

function [h_early, h_late] = shade_edge_regions(ax, peak_t, edge_window_sec)
% SHADE_EDGE_REGIONS Mark early and late belt-reference QC windows.
% peak_t contains ordered breath-peak times in seconds; edge_window_sec is
% drawn from each end. h_early and h_late are the actual shaded patches.

    h_early = gobjects(0);
    h_late = gobjects(0);
    if ~isfinite(edge_window_sec) || edge_window_sec <= 0
        return;
    end
    y_limits = robust_plot_limits(ax);
    t0 = peak_t(1);
    t1 = peak_t(end);
    h_early = patch(ax, [t0 t0+edge_window_sec t0+edge_window_sec t0], ...
        [y_limits(1) y_limits(1) y_limits(2) y_limits(2)], [0.80 0.92 0.82], ...
        'EdgeColor', 'none', 'FaceAlpha', 0.18, ...
        'DisplayName', 'early edge window');
    h_late = patch(ax, [t1-edge_window_sec t1 t1 t1-edge_window_sec], ...
        [y_limits(1) y_limits(1) y_limits(2) y_limits(2)], [0.98 0.86 0.76], ...
        'EdgeColor', 'none', 'FaceAlpha', 0.18, ...
        'DisplayName', 'late edge window');
end

function y_limits = robust_plot_limits(ax)
% ROBUST_PLOT_LIMITS Return finite two-element limits for patch construction.

    y_limits = ylim(ax);
    if ~all(isfinite(y_limits)) || y_limits(1) == y_limits(2)
        y_limits = [0 1];
    end
end

function [peak_t, amp] = valid_amplitudes(breaths)
% VALID_AMPLITUDES Return sorted finite breath times and positive excursions.
% peak_t is seconds and amp is raw belt units. Missing or unequal trailing
% entries are ignored for this diagnostic plot only.

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
% GET_BELT Read a named belt struct, returning empty when it is absent.

    breaths = [];
    if isstruct(resp_cycles) && isfield(resp_cycles, name)
        breaths = resp_cycles.(name);
    end
end

function value = numeric_text(x)
% NUMERIC_TEXT Format a finite scalar to three decimals or return "n/a".

    if isfinite(x)
        value = sprintf('%.3f', x);
    else
        value = 'n/a';
    end
end
