function [b_l, b_d] = manual_edit_respiration_features(data, b_l, b_d, config)
    fs = config.fs;
    N = size(data, 1);
    t_raw = (0:N-1) / fs;

    window_sec = 300;
    if isfield(config.resp, 'manual_window_sec')
        window_sec = config.resp.manual_window_sec;
    end
    window_sec = max(30, window_sec);

    fh = figure('Units','pixels','Position', near_fullscreen_figure_position(), 'Visible', 'on');

    ax1 = subplot(2,1,1); hold(ax1, 'on');
    pL = plot(ax1, t_raw(1:numel(b_l.x0)), b_l.x0, 'k');
    pkL = plot(ax1, b_l.peak_t, b_l.peak_val, 'ro', 'MarkerFaceColor','r', 'MarkerSize', 7);
    trL = plot(ax1, b_l.trough_t, b_l.trough_val, 'bo', 'MarkerFaceColor','b', 'MarkerSize', 6);
    title(ax1, 'GUI breath peak editing (lungs): edit red peaks only; blue troughs update automatically');
    ylabel(ax1, 'Resp-Lungs');
    if ~isempty(b_l.peak_t)
        legend(ax1, 'signal', 'peaks', 'troughs', 'Location','eastoutside');
    end
    grid(ax1, 'on');

    ax2 = subplot(2,1,2); hold(ax2, 'on');
    pD = plot(ax2, t_raw(1:numel(b_d.x0)), b_d.x0, 'k');
    pkD = plot(ax2, b_d.peak_t, b_d.peak_val, 'ro', 'MarkerFaceColor','r', 'MarkerSize', 7);
    trD = plot(ax2, b_d.trough_t, b_d.trough_val, 'bo', 'MarkerFaceColor','b', 'MarkerSize', 6);
    title(ax2, 'GUI breath peak editing (diaphragm): edit red peaks only; blue troughs update automatically');
    ylabel(ax2, 'Resp-Diaphragm');
    legend(ax2, 'signal', 'peaks', 'troughs', 'Location','eastoutside');
    grid(ax2, 'on');

    sgtitle(['GUI BREATH PEAK EDITING' newline ...
        'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)]);

    xlabel(ax2, 'Time (s)');

    linkaxes([ax1 ax2], 'x');
    xlim(ax1, [0 min(window_sec, t_raw(end))]);

    uicontrol(fh, 'Style','slider', 'Units','normalized', 'Position',[0.1 0.01 0.8 0.03], ...
        'Min',0, 'Max',max(0,t_raw(end)-window_sec), 'Value',0, ...
        'SliderStep',[min(1/max(1,t_raw(end)-window_sec),0.05) 0.2], ...
        'Callback', @(src,~) set_xlim(src.Value));

    set(pL, 'HitTest','on', 'PickableParts','visible', ...
        'ButtonDownFcn', @(~,evt) edit_peak(evt, ax1, 'lungs', 'trace'));
    set(pD, 'HitTest','on', 'PickableParts','visible', ...
        'ButtonDownFcn', @(~,evt) edit_peak(evt, ax2, 'diaph', 'trace'));
    set(pkL, 'HitTest','on', 'PickableParts','visible', ...
        'ButtonDownFcn', @(~,evt) edit_peak(evt, ax1, 'lungs', 'peak'));
    set(pkD, 'HitTest','on', 'PickableParts','visible', ...
        'ButtonDownFcn', @(~,evt) edit_peak(evt, ax2, 'diaph', 'peak'));
    set([trL trD], 'HitTest','off', 'PickableParts','none');

    fprintf('\nManual breath control ON.\n');
    fprintf('  Left-click a trace to add a red peak.\n');
    fprintf('  Left-click a red peak to remove it.\n');
    fprintf('  Blue troughs and amplitudes are recomputed automatically from the edited peaks.\n');
    fprintf('  Close the figure when done.\n\n');
    uiwait(fh);

    function set_xlim(x0)
        xlim(ax1, [x0 min(x0+window_sec, t_raw(end))]);
    end

    function edit_peak(evt, ax, belt, target)
        if ~strcmp(get(fh, 'SelectionType'), 'normal')
            return;
        end

        t_click = get_click_time(evt, ax);
        if ~isfinite(t_click)
            return;
        end

        if strcmp(belt, 'lungs')
            b_l = update_breath_peaks(b_l, t_click, target);
            update_breath_plots(pkL, trL, b_l);
        else
            b_d = update_breath_peaks(b_d, t_click, target);
            update_breath_plots(pkD, trD, b_d);
        end
        drawnow;
    end

    function b = update_breath_peaks(b, t_click, target)
        peak_idx = b.peak_idx(:);
        if strcmp(target, 'peak')
            if isempty(peak_idx)
                return;
            end
            [~, i] = min(abs(b.peak_t(:) - t_click));
            peak_idx(i) = [];
        else
            new_idx = nearest_local_peak_idx(b.x0, t_click);
            if isempty(new_idx)
                return;
            end
            duplicate_tol = max(1, round(0.25 * config.resp.min_peak_dist_sec * fs));
            if any(abs(peak_idx - new_idx) <= duplicate_tol)
                return;
            end
            peak_idx = [peak_idx; new_idx];
        end
        b = recompute_respiration_breath_fields(b, b.x0, peak_idx, config);
    end

    function idx = nearest_local_peak_idx(x, t_click)
        idx = [];
        if isempty(x)
            return;
        end

        search_sec = 1.0;
        if isfield(config.resp, 'manual_peak_search_sec')
            search_sec = config.resp.manual_peak_search_sec;
        end

        idx_click = max(1, min(numel(x), round(t_click * fs) + 1));
        radius = max(1, round(search_sec * fs));
        lo = max(1, idx_click - radius);
        hi = min(numel(x), idx_click + radius);
        [~, j] = max(x(lo:hi));
        idx = lo + j - 1;
    end

    function update_breath_plots(peak_plot, trough_plot, b)
        set(peak_plot, 'XData', b.peak_t, 'YData', b.peak_val);
        set(trough_plot, 'XData', b.trough_t, 'YData', b.trough_val);
    end

    function t_click = get_click_time(evt, ax)
        t_click = NaN;
        if ~isempty(evt)
            if isstruct(evt) && isfield(evt, 'IntersectionPoint') && ~isempty(evt.IntersectionPoint)
                t_click = evt.IntersectionPoint(1);
                return;
            elseif isobject(evt) && isprop(evt, 'IntersectionPoint') && ~isempty(evt.IntersectionPoint)
                t_click = evt.IntersectionPoint(1);
                return;
            end
        end
        cp = get(ax, 'CurrentPoint');
        if ~isempty(cp)
            t_click = cp(1,1);
        end
    end
end
