function [flags_lungs, flags_diaph] = manual_edit_sigh_flags(data, bL, bD, flags_lungs, flags_diaph, spo2_feat, config, window_sec)
    idx_lungs = find(strcmp(config.data_columns, 'Resp-Lungs'), 1);
    idx_diaph = find(strcmp(config.data_columns, 'Resp-Diaphragm'), 1);
    if isempty(idx_lungs) || isempty(idx_diaph), return; end

    fs = config.fs;
    N = size(data,1);
    t_raw = (0:N-1)/fs;
    window_sec = max(30, window_sec);

    fh = figure('Units','pixels','Position', near_fullscreen_figure_position(), 'Visible', 'on');
    ax1 = subplot(3,1,1); hold(ax1,'on');
    p1 = plot(ax1, t_raw, data(:,idx_lungs), 'k');
    m1 = plot(ax1, bL.peak_t(flags_lungs), interp1(t_raw, data(:,idx_lungs), bL.peak_t(flags_lungs), 'linear','extrap'), ...
        'ro', 'MarkerFaceColor','r', 'MarkerSize', 7);
    title(ax1, 'GUI sigh manual editing (lungs)'); ylabel(ax1, 'Resp-Lungs'); grid(ax1,'on');

    ax2 = subplot(3,1,2); hold(ax2,'on');
    p2 = plot(ax2, t_raw, data(:,idx_diaph), 'k');
    m2 = plot(ax2, bD.peak_t(flags_diaph), interp1(t_raw, data(:,idx_diaph), bD.peak_t(flags_diaph), 'linear','extrap'), ...
        'ro', 'MarkerFaceColor','r', 'MarkerSize', 7);
    title(ax2, 'GUI sigh manual editing (diaphragm)'); ylabel(ax2, 'Resp-Diaphragm'); grid(ax2,'on');

    ax3 = subplot(3,1,3); hold(ax3,'on');
    [t_spo2, spo2] = get_spo2_trace(data, spo2_feat, config);
    if isempty(spo2)
        plot(ax3, t_raw, zeros(size(t_raw)), 'w');
        ylim(ax3, [-1 1]);
        title(ax3, 'GUI SpO2 unavailable. Left-click trace to add. Left-click red marker to remove.');
    else
        plot(ax3, t_spo2, spo2, 'k');
        yline(ax3, 90, 'r--', 'LineWidth', 1.6);
        finite_spo2 = spo2(isfinite(spo2));
        if ~isempty(finite_spo2)
            y0 = min(finite_spo2);
            y1 = max(finite_spo2);
            if y0 == y1
                ylim(ax3, [y0-1 y1+1]);
            else
                ylim(ax3, [y0-0.05*(y1-y0) y1+0.05*(y1-y0)]);
            end
        end
        if isfield(spo2_feat, 'desat_events') && ~isempty(spo2_feat.desat_events)
            axes(ax3);
            shade_events_on_axis(spo2_feat.desat_events);
            plot(ax3, t_spo2, spo2, 'k');
            yline(ax3, 90, 'r--', 'LineWidth', 1.6);
        end
        title(ax3, 'GUI SpO2. Left-click trace to add. Left-click red marker to remove.');
    end
    xlabel(ax3, 'Time (s)');
    ylabel(ax3, 'SpO2 (%)');
    grid(ax3,'on');

    sgtitle(['GUI SIGH MANUAL EDITING' newline ...
        'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)]);

    linkaxes([ax1 ax2 ax3],'x');
    xlim(ax1, [0 min(window_sec,t_raw(end))]);

    uicontrol(fh, 'Style','slider', 'Units','normalized', 'Position',[0.1 0.01 0.8 0.03], ...
        'Min',0, 'Max',max(0,t_raw(end)-window_sec), 'Value',0, ...
        'SliderStep',[min(1/max(1,t_raw(end)-window_sec),0.05) 0.2], ...
        'Callback', @(src,~) set_xlim(src.Value));

    set(p1, 'HitTest','on', 'PickableParts','visible', ...
        'ButtonDownFcn', @(~,evt) edit_flag(evt, ax1, 'lungs', 'trace'));
    set(p2, 'HitTest','on', 'PickableParts','visible', ...
        'ButtonDownFcn', @(~,evt) edit_flag(evt, ax2, 'diaph', 'trace'));
    set(m1, 'HitTest','on', 'PickableParts','visible', ...
        'ButtonDownFcn', @(~,evt) edit_flag(evt, ax1, 'lungs', 'marker'));
    set(m2, 'HitTest','on', 'PickableParts','visible', ...
        'ButtonDownFcn', @(~,evt) edit_flag(evt, ax2, 'diaph', 'marker'));
    fprintf('\nManual sigh control ON.\n');
    fprintf('  Left-click a trace to add a marker.\n');
    fprintf('  Left-click a red marker to remove it.\n');
    fprintf('  Close the figure when done.\n\n');
    uiwait(fh);

    function set_xlim(x0)
        xlim(ax1, [x0 min(x0+window_sec, t_raw(end))]);
    end

    function edit_flag(evt, ax, belt, target)
        if ~strcmp(get(fh, 'SelectionType'), 'normal')
            return;
        end

        t_click = get_click_time(evt, ax);
        if ~isfinite(t_click)
            return;
        end

        remove_marker = strcmp(target, 'marker');

        if strcmp(belt,'lungs')
            if remove_marker
                i = nearest_flagged_index(bL.peak_t, flags_lungs, t_click);
                if isempty(i), return; end
                flags_lungs(i) = false;
            else
                [~,i] = min(abs(bL.peak_t - t_click));
                flags_lungs(i) = true;
            end
            update_marker_plot(m1, bL, flags_lungs, idx_lungs);
        else
            if remove_marker
                i = nearest_flagged_index(bD.peak_t, flags_diaph, t_click);
                if isempty(i), return; end
                flags_diaph(i) = false;
            else
                [~,i] = min(abs(bD.peak_t - t_click));
                flags_diaph(i) = true;
            end
            update_marker_plot(m2, bD, flags_diaph, idx_diaph);
        end
        drawnow;
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

    function i = nearest_flagged_index(peak_t, flags, t_click)
        flagged_idx = find(flags(:));
        if isempty(flagged_idx)
            i = [];
            return;
        end

        [~, pos] = min(abs(peak_t(flagged_idx) - t_click));
        i = flagged_idx(pos);
    end

    function update_marker_plot(marker_plot, breaths, flags, signal_idx)
        marker_t = breaths.peak_t(flags);
        set(marker_plot, ...
            'XData', marker_t, ...
            'YData', interp1(t_raw, data(:,signal_idx), marker_t, 'linear','extrap'));
    end

    function [t_spo2, spo2] = get_spo2_trace(data, spo2_feat, config)
        if isfield(spo2_feat, 'spo2') && isfield(spo2_feat, 't_spo2') && ~isempty(spo2_feat.spo2)
            spo2 = spo2_feat.spo2(:);
            t_spo2 = spo2_feat.t_spo2(:);
            return;
        end

        idx_spo2 = find(strcmp(config.data_columns, 'SpO2'), 1);
        if isempty(idx_spo2)
            idx_spo2 = find(contains(config.data_columns, 'SpO'), 1);
        end

        if isempty(idx_spo2)
            t_spo2 = [];
            spo2 = [];
            return;
        end

        spo2 = data(:, idx_spo2);
        t_spo2 = (0:numel(spo2)-1)' / config.fs;
    end
end
