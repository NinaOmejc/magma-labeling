function [flags_lungs, flags_diaph, review_mask] = manual_edit_sigh_flags( ...
    data, bL, bD, flags_lungs, flags_diaph, spo2_ref, ...
    session_reference, diagnostics_Des, config, window_sec)
% Edit sigh flags using click times on the config.fs master timeline.
    review_mask = false(size(data,1), 1);
    if ~isfield(config, 'channels')
        config = resolve_signal_channels(config);
    end
    idx_lungs = config.channels.lungs_idx;
    idx_diaph = config.channels.diaph_idx;
    if isempty(idx_lungs) || isempty(idx_diaph), return; end

    fs = config.fs;
    N = size(data,1);
    t_raw = (0:N-1)/fs;
    window_sec = max(30, window_sec);

    fh = figure('Units','pixels','Position', near_fullscreen_figure_position(), 'Visible', 'on');
    ax1 = subplot(3,1,1); hold(ax1,'on');
    p1 = plot(ax1, t_raw, data(:,idx_lungs), 'k', 'DisplayName', 'Resp-Lungs');
    m1 = plot(ax1, bL.peak_t(flags_lungs), interp1(t_raw, data(:,idx_lungs), bL.peak_t(flags_lungs), 'linear','extrap'), ...
        'ro', 'MarkerFaceColor','r', 'MarkerSize', 4, 'DisplayName', 'Sigh breaths');
    title(ax1, 'GUI sigh manual editing (lungs)'); ylabel(ax1, 'Resp-Lungs'); grid(ax1,'on');
    update_axis_legend(ax1, [p1; m1], {'Resp-Lungs', 'Sigh breaths'});

    ax2 = subplot(3,1,2); hold(ax2,'on');
    p2 = plot(ax2, t_raw, data(:,idx_diaph), 'k', 'DisplayName', 'Resp-Diaphragm');
    m2 = plot(ax2, bD.peak_t(flags_diaph), interp1(t_raw, data(:,idx_diaph), bD.peak_t(flags_diaph), 'linear','extrap'), ...
        'ro', 'MarkerFaceColor','r', 'MarkerSize', 4, 'DisplayName', 'Sigh breaths');
    title(ax2, 'GUI sigh manual editing (diaphragm)'); ylabel(ax2, 'Resp-Diaphragm'); grid(ax2,'on');
    update_axis_legend(ax2, [p2; m2], {'Resp-Diaphragm', 'Sigh breaths'});
    ylim(ax1, compute_global_ylim(data(:, idx_lungs)));
    ylim(ax2, compute_global_ylim(data(:, idx_diaph)));

    ax3 = subplot(3,1,3);
    plot_spo2_diagnostic_panel(ax3, data, spo2_ref, session_reference, ...
        diagnostics_Des, config, 'SpO2 with desaturation thresholds');

    sgtitle(['GUI SIGH MANUAL EDITING' newline ...
        'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)]);

    linkaxes([ax1 ax2 ax3],'x');
    xlim(ax1, [0 min(window_sec,t_raw(end))]);
    mark_current_view_reviewed();
    align_sigh_axes();

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
        mark_current_view_reviewed();
    end

    function mark_current_view_reviewed()
        if ~isgraphics(ax1), return; end
        limits = xlim(ax1);
        start_idx = max(1, min(N, floor(limits(1) * fs) + 1));
        end_idx = max(start_idx, min(N, ceil(limits(2) * fs)));
        review_mask(start_idx:end_idx) = true;
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
            update_axis_legend(ax1, [p1; m1], {'Resp-Lungs', 'Sigh breaths'});
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
            update_axis_legend(ax2, [p2; m2], {'Resp-Diaphragm', 'Sigh breaths'});
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

    function update_axis_legend(ax, handles, labels)
        keep = false(size(handles));
        for i = 1:numel(handles)
            h = handles(i);
            if ~isgraphics(h)
                continue;
            end
            xdata = get(h, 'XData');
            if ~isempty(xdata)
                keep(i) = true;
            end
        end

        handles = handles(keep);
        labels = labels(keep);
        if isempty(handles)
            legend(ax, 'off');
            align_sigh_axes();
            return;
        end
        legend(ax, handles, labels, 'Location', 'eastoutside');
        align_sigh_axes();
    end

    function align_sigh_axes()
        axes_to_align = gobjects(0);
        if exist('ax1', 'var') && isgraphics(ax1)
            axes_to_align(end+1,1) = ax1;
        end
        if exist('ax2', 'var') && isgraphics(ax2)
            axes_to_align(end+1,1) = ax2;
        end
        if exist('ax3', 'var') && isgraphics(ax3)
            axes_to_align(end+1,1) = ax3;
        end
        align_axes_x_widths(axes_to_align);
    end

    function y_limits = compute_global_ylim(signal)
        signal = signal(isfinite(signal));
        if isempty(signal)
            y_limits = [-1, 1];
            return;
        end

        y_min = min(signal);
        y_max = max(signal);
        if y_min == y_max
            pad = max(1e-3, 0.05 * max(1, abs(y_min)));
        else
            pad = max(1e-3, 0.05 * (y_max - y_min));
        end
        y_limits = [y_min - pad, y_max + pad];
    end
end
