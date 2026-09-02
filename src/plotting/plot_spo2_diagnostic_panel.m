function h = plot_spo2_diagnostic_panel(ax, data, baseline, spo2_feat, config, title_text)
% plot_spo2_diagnostic_panel
% Shared SpO2 panel using config.fs master sample times.

    if nargin < 1 || isempty(ax)
        ax = gca;
    end
    if nargin < 6 || isempty(title_text)
        title_text = 'SpO2';
    end

    h = struct();
    hold(ax, 'on');
    grid(ax, 'on');
    xlabel(ax, 'Time (s)');
    ylabel(ax, 'SpO2 (%)');
    title(ax, title_text);

    [t_spo2, spo2] = get_spo2_trace(data, spo2_feat, config);
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

    set_spo2_limits(ax, spo2, baseline, floor_thr, drop_thr);
    h.baseline_window = shade_static_baseline_on_axis(ax, baseline, 'baseline window');
    h.spo2 = plot(ax, t_spo2, spo2, 'k', 'DisplayName', 'SpO2');

    if isstruct(baseline) && isfield(baseline, 'SpO2_median') && isfinite(baseline.SpO2_median)
        h.baseline = yline(ax, baseline.SpO2_median, 'k--', ...
            'DisplayName', 'baseline median');
        h.baseline_drop = yline(ax, baseline.SpO2_median - drop_thr, 'g--', ...
            'DisplayName', sprintf('baseline - %g', drop_thr));
    else
        h.baseline = gobjects(0);
        h.baseline_drop = gobjects(0);
    end

    h.floor = yline(ax, floor_thr, 'r--', ...
        'DisplayName', sprintf('%g%% floor', floor_thr));

    h.desat_events = gobjects(0);
    if isstruct(spo2_feat) && isfield(spo2_feat, 'desat_events') && ~isempty(spo2_feat.desat_events)
        h.desat_events = shade_events_on_axis(ax, spo2_feat.desat_events, 'desaturation');
    end

    plot(ax, t_spo2, spo2, 'k', 'HandleVisibility', 'off');
    add_spo2_legend(ax, h);
    hold(ax, 'off');
end

function [t_spo2, spo2] = get_spo2_trace(data, spo2_feat, config)
    if nargin >= 2 && ~isempty(spo2_feat) && isstruct(spo2_feat) && ...
            isfield(spo2_feat, 'spo2') && isfield(spo2_feat, 't_spo2') && ...
            ~isempty(spo2_feat.spo2) && ~isempty(spo2_feat.t_spo2)
        spo2 = spo2_feat.spo2(:);
        t_spo2 = spo2_feat.t_spo2(:);
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

    idx_spo2 = [];
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

function set_spo2_limits(ax, spo2, baseline, floor_thr, drop_thr)
    values = spo2(isfinite(spo2));
    values = [values; floor_thr; 89; 100];
    if isstruct(baseline) && isfield(baseline, 'SpO2_median') && isfinite(baseline.SpO2_median)
        values = [values; baseline.SpO2_median; baseline.SpO2_median - drop_thr]; %#ok<AGROW>
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
    handles = gobjects(0);
    if isfield(h, 'spo2'), handles(end+1,1) = h.spo2; end
    if isfield(h, 'baseline'), handles = append_graphics_handle(handles, h.baseline); end
    if isfield(h, 'baseline_drop'), handles = append_graphics_handle(handles, h.baseline_drop); end
    if isfield(h, 'floor'), handles = append_graphics_handle(handles, h.floor); end
    if isfield(h, 'baseline_window'), handles = append_graphics_handle(handles, h.baseline_window); end
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
    if isempty(h)
        return;
    end
    h = h(isgraphics(h));
    if isempty(h)
        return;
    end
    handles(end+1,1) = h(1);
end
