function h = plot_spo2_diagnostic_panel( ...
    ax, data, spo2_ref, session_reference, diagnostics_Des, config, title_text)
% PLOT_SPO2_DIAGNOSTIC_PANEL Plot spo2 diagnostic panel.
%
% Syntax:
%   h = plot_spo2_diagnostic_panel(ax, data, spo2_ref, session_reference, diagnostics_Des, config, title_text)
%
% Inputs:
%   ax - Target axes handle.
%   data - Input physiological signal data.
%   spo2_ref - SpO2-reference structure.
%   session_reference - Session-reference metadata.
%   diagnostics_Des - Detector diagnostic data.
%   config - Pipeline configuration structure.
%   title_text - Input value `title_text`.
%
% Outputs:
%   h - Graphics handle or array.

    if nargin < 1 || isempty(ax)
        ax = gca;
    end
    if nargin < 7 || isempty(title_text)
        title_text = 'SpO2';
    end

    h = struct();
    hold(ax, 'on');
    grid(ax, 'on');
    xlabel(ax, 'Time (s)');
    ylabel(ax, 'SpO2 (%)');
    title(ax, title_text);

    [t_spo2, spo2] = get_spo2_trace(data, diagnostics_Des, config);
    if isempty(spo2)
        plot(ax, 0, 0, 'w', 'HandleVisibility', 'off');
        ylim(ax, [-1 1]);
        text(ax, 0.5, 0.5, 'SpO2 unavailable', ...
            'Units', 'normalized', 'HorizontalAlignment', 'center');
        hold(ax, 'off');
        return;
    end

    floor_thr = get_config_value(config, 'spo2', 'spo2_floor', 90);
    drop_thr = get_config_value(config, 'spo2', 'drop_thr', 3);

    set_spo2_limits(ax, spo2, spo2_ref, floor_thr, drop_thr);
    h.reference_window = shade_session_reference_on_axis( ...
        ax, session_reference, 'common session-reference interval');
    h.spo2 = plot(ax, t_spo2, spo2, 'k', 'DisplayName', 'SpO2');

    if isstruct(spo2_ref) && isfield(spo2_ref, 'median_percent') && ...
            isfinite(spo2_ref.median_percent)
        h.reference = yline(ax, spo2_ref.median_percent, 'k--', ...
            'DisplayName', 'session SpO2 reference median');
        h.reference_drop = yline(ax, spo2_ref.median_percent - drop_thr, 'g--', ...
            'DisplayName', sprintf('session reference - %g', drop_thr));
    else
        h.reference = gobjects(0);
        h.reference_drop = gobjects(0);
    end

    h.floor = yline(ax, floor_thr, 'r--', ...
        'DisplayName', sprintf('%g%% floor', floor_thr));

    h.desat_events = gobjects(0);
    if isstruct(diagnostics_Des) && isfield(diagnostics_Des, 'events') && ...
            ~isempty(diagnostics_Des.events)
        h.desat_events = shade_events_on_axis( ...
            ax, diagnostics_Des.events, 'desaturation');
    end

    plot(ax, t_spo2, spo2, 'k', 'HandleVisibility', 'off');
    add_spo2_legend(ax, h);
    hold(ax, 'off');
end

function [t_spo2, spo2] = get_spo2_trace(data, diagnostics_Des, config)
% GET_SPO2_TRACE Return spo2 trace.
%
% Syntax:
%   [t_spo2, spo2] = get_spo2_trace(data, diagnostics_Des, config)
%
% Inputs:
%   data - Input physiological signal data.
%   diagnostics_Des - Detector diagnostic data.
%   config - Pipeline configuration structure.
%
% Outputs:
%   t_spo2 - Computed output value `t_spo2`.
%   spo2 - Computed output value `spo2`.

    if nargin >= 2 && ~isempty(diagnostics_Des) && ...
            isstruct(diagnostics_Des) && ...
            isfield(diagnostics_Des, 'spo2') && ...
            isfield(diagnostics_Des, 'time_sec') && ...
            ~isempty(diagnostics_Des.spo2) && ...
            ~isempty(diagnostics_Des.time_sec)
        spo2 = diagnostics_Des.spo2(:);
        t_spo2 = diagnostics_Des.time_sec(:);
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
% SET_SPO2_LIMITS Perform the set spo2 limits operation.
%
% Syntax:
%   set_spo2_limits(ax, spo2, spo2_ref, floor_thr, drop_thr)
%
% Inputs:
%   ax - Target axes handle.
%   spo2 - Input value `spo2`.
%   spo2_ref - SpO2-reference structure.
%   floor_thr - Selection threshold value.
%   drop_thr - Selection threshold value.

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
% ADD_SPO2_LEGEND Add spo2 legend.
%
% Syntax:
%   add_spo2_legend(ax, h)
%
% Inputs:
%   ax - Target axes handle.
%   h - Input value `h`.

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
% APPEND_GRAPHICS_HANDLE Perform the append graphics handle operation.
%
% Syntax:
%   handles = append_graphics_handle(handles, h)
%
% Inputs:
%   handles - Input value `handles`.
%   h - Input value `h`.
%
% Outputs:
%   handles - Graphics handle or array.

    if isempty(h)
        return;
    end
    h = h(isgraphics(h));
    if isempty(h)
        return;
    end
    handles(end+1,1) = h(1);
end
