function h = plot_spo2_diagnostic_panel( ...
    ax, data, session_reference, diagnostics_desat, config, title_text)
% PLOT_SPO2_DIAGNOSTIC_PANEL Plot SpO2, reference thresholds, and desaturation events.
%
% Inputs:
%   ax                - Target axes handle, or empty for the current axes.
%   data              - Nsample x Nchannel physiological signal matrix.
%   session_reference - Common reference interval with boundaries in seconds.
%   diagnostics_desat - Desaturation diagnostics with spo2_ref and optional
%                       time_sec, spo2, and events.
%   config            - Channel, sampling, and desaturation threshold settings.
%   title_text        - Optional panel title.
%
% Outputs:
%   h - Scalar struct of available plot handles: reference_window, spo2,
%       reference, reference_drop, floor, and desat_events.

    if nargin < 1 || isempty(ax)
        ax = gca;
    end
    if nargin < 6 || isempty(title_text)
        title_text = 'SpO2';
    end

    spo2_ref = struct();
    if isstruct(diagnostics_desat) && isfield(diagnostics_desat, 'spo2_ref')
        spo2_ref = diagnostics_desat.spo2_ref;
    end

    h = struct();
    hold(ax, 'on');
    grid(ax, 'on');
    xlabel(ax, 'Time (s)');
    ylabel(ax, 'SpO2 (%)');
    title(ax, title_text);

    [t_spo2, spo2] = get_spo2_trace(data, diagnostics_desat, config);
    if isempty(spo2)
        plot(ax, 0, 0, 'w', 'HandleVisibility', 'off');
        ylim(ax, [-1 1]);
        text(ax, 0.5, 0.5, 'SpO2 unavailable', ...
            'Units', 'normalized', 'HorizontalAlignment', 'center');
        hold(ax, 'off');
        return;
    end

    floor_thr = get_config_value(config, 'desat', 'spo2_floor', 90);
    drop_thr = get_config_value(config, 'desat', 'drop_thr', 3);

    set_spo2_limits(ax, spo2, spo2_ref, floor_thr, drop_thr);
    h.reference_window = shade_session_reference_on_axis( ...
        ax, session_reference, 'common session-reference interval');
    h.spo2 = plot(ax, t_spo2, spo2, ...
            'Color', 'k', ...
            'LineStyle', '-', ...
            'Marker', 'none', ...
            'LineWidth', 1.5, ...
            'DisplayName', 'SpO2');

    if isstruct(spo2_ref) && isfield(spo2_ref, 'median_percent') && ...
            isfinite(spo2_ref.median_percent)
        h.reference = yline(ax, spo2_ref.median_percent, '--', 'Color', [0.45 0.10 0.65], ...
            'DisplayName', 'session SpO2 reference median');
        h.reference_drop = yline(ax, spo2_ref.median_percent - drop_thr, 'r--', ...
            'DisplayName', sprintf('session reference - %g', drop_thr));
    else
        h.reference = gobjects(0);
        h.reference_drop = gobjects(0);
    end

    h.floor = yline(ax, floor_thr, '--', 'Color', [0.75 0.25 0.00],...
        'DisplayName', sprintf('%g%% floor', floor_thr));

    h.desat_events = gobjects(0);
    if isstruct(diagnostics_desat) && isfield(diagnostics_desat, 'events') && ...
            ~isempty(diagnostics_desat.events)
        h.desat_events = shade_events_on_axis( ...
            ax, diagnostics_desat.events, 'desaturation');
    end
    if ~isempty(t_spo2)
        xlim(ax, [0 t_spo2(end)]);
    end
    add_spo2_legend(ax, h);
    hold(ax, 'off');
end

function [t_spo2, spo2] = get_spo2_trace(data, diagnostics_desat, config)
% GET_SPO2_TRACE Resolve aligned sample times and SpO2 percentages for plotting.
% A diagnostic trace takes precedence; otherwise the configured data column
% is sampled at config.fs. Empty vectors indicate unavailable SpO2.

    if nargin >= 2 && ~isempty(diagnostics_desat) && ...
            isstruct(diagnostics_desat) && ...
            isfield(diagnostics_desat, 'spo2') && ...
            isfield(diagnostics_desat, 'time_sec') && ...
            ~isempty(diagnostics_desat.spo2) && ...
            ~isempty(diagnostics_desat.time_sec)
        spo2 = diagnostics_desat.spo2(:);
        t_spo2 = diagnostics_desat.time_sec(:);
        n = min(numel(spo2), numel(t_spo2));
        spo2 = spo2(1:n);
        t_spo2 = t_spo2(1:n);
        return;
    end

    if nargin < 1 || isempty(data) || nargin < 3 || isempty(config) || ~isfield(config, 'data_columns')
        t_spo2 = [];
        spo2 = [];
        return;
    end

    if isfield(config, 'channels') && isfield(config.channels, 'spo2_idx')
        idx_spo2 = config.channels.spo2_idx;
    else
        try
            [config, ~] = resolve_signal_channels(config);
            idx_spo2 = config.channels.spo2_idx;
        catch
            idx_spo2 = [];
        end
    end

    if isempty(idx_spo2)
        t_spo2 = [];
        spo2 = [];
        return;
    end

    spo2 = data(:, idx_spo2);
    t_spo2 = (0:numel(spo2)-1)' / config.fs;
end

function set_spo2_limits(ax, spo2, spo2_ref, floor_thr, drop_thr)
% SET_SPO2_LIMITS Include observed percentages and all detection thresholds.
% floor_thr is an absolute percent; drop_thr is subtracted from the optional
% session reference median before padded y-limits are assigned to ax.

    values = spo2(isfinite(spo2));
    values = [values; floor_thr; 89; 100];
    if isstruct(spo2_ref) && isfield(spo2_ref, 'median_percent') && ...
            isfinite(spo2_ref.median_percent)
        values = [values; spo2_ref.median_percent; ...
            spo2_ref.median_percent - drop_thr];
    end

    y0 = min(values, [], 'omitnan');
    y1 = max(values, [], 'omitnan');
    if ~isfinite(y0) || ~isfinite(y1)
        ylim(ax, [89 100]);
        return;
    end

    pad = max(0.5, 0.05 * max(1, y1 - y0));
    ylim(ax, [y0 - pad, y1 + pad]);
end

function add_spo2_legend(ax, h)
% ADD_SPO2_LEGEND Build a legend from valid named handles in the panel struct.

    handles = gobjects(0);
    if isfield(h, 'spo2'), handles(end+1,1) = h.spo2; end
    if isfield(h, 'reference'), handles = append_graphics_handle(handles, h.reference); end
    if isfield(h, 'reference_drop'), handles = append_graphics_handle(handles, h.reference_drop); end
    if isfield(h, 'floor'), handles = append_graphics_handle(handles, h.floor); end
    if isfield(h, 'reference_window'), handles = append_graphics_handle(handles, h.reference_window); end
    if isfield(h, 'desat_events'), handles = append_graphics_handle(handles, h.desat_events); end

    handles = handles(isgraphics(handles));
    if isempty(handles)
        return;
    end

    labels = get(handles, 'DisplayName');
    if ischar(labels) || isstring(labels)
        labels = cellstr(labels);
    end
    legend(ax, handles, labels, 'Location', 'eastoutside');
end

function handles = append_graphics_handle(handles, h)
% APPEND_GRAPHICS_HANDLE Append the first valid handle from h to a handle vector.

    if isempty(h)
        return;
    end
    h = h(isgraphics(h));
    if isempty(h)
        return;
    end
    handles(end+1,1) = h(1);
end
