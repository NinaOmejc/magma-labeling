function [b_l, b_d, review_confirmed] = manual_edit_respiration_features(data, b_l, b_d, config)
% MANUAL_EDIT_RESPIRATION_FEATURES Edit respiratory cycles and explicitly confirm review.
%
% Syntax:
%   [b_l, b_d, review_confirmed] = manual_edit_respiration_features(data, b_l, b_d, config)
%
% Inputs:
%   data - Input physiological signal data.
%   b_l - Respiratory-cycle or belt-evidence structure.
%   b_d - Respiratory-cycle or belt-evidence structure.
%   config - Pipeline configuration structure.
%
% Outputs:
%   b_l - Updated respiratory-cycle or belt structure.
%   b_d - Updated respiratory-cycle or belt structure.
%   review_confirmed - True when the user confirms the respiratory-cycle review.

    fs = config.fs;
    N = size(data, 1);
    t_raw = (0:N-1) / fs;
    automatic_lungs = b_l;
    automatic_diaph = b_d;
    review_confirmed = false;

    window_sec = 300;
    if isfield(config.resp, 'manual_window_sec')
        window_sec = config.resp.manual_window_sec;
    end
    window_sec = max(30, window_sec);

    edit_lungs = is_editable_resp_signal(b_l) && ~is_lung_belt_ignored(config);
    edit_diaph = is_editable_resp_signal(b_d);
    if ~edit_lungs && ~edit_diaph
        return;
    end

    fh = figure('Units','pixels','Position', near_fullscreen_figure_position(), ...
        'Visible', 'on', 'CloseRequestFcn', @(~,~) cancel_review());

    ax1 = subplot(2,1,1); hold(ax1, 'on');
    [pL, pkL, trL] = plot_belt_panel(ax1, t_raw, b_l, ...
        'GUI breath peak editing (lungs)', 'Resp-Lungs', edit_lungs, lungs_unavailable_message(config));

    ax2 = subplot(2,1,2); hold(ax2, 'on');
    [pD, pkD, trD] = plot_belt_panel(ax2, t_raw, b_d, ...
        'GUI breath peak editing (diaphragm)', 'Resp-Diaphragm', edit_diaph, ...
        'No editable Resp-Diaphragm signal');

    sgtitle(['GUI BREATH PEAK EDITING' newline ...
        'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)]);

    xlabel(ax2, 'Time (s)');
    set_panel_global_ylim(ax1, b_l, edit_lungs);
    set_panel_global_ylim(ax2, b_d, edit_diaph);

    linkaxes([ax1 ax2], 'x');
    xlim(ax1, [0 min(window_sec, t_raw(end))]);

    uicontrol(fh, 'Style','slider', 'Units','normalized', 'Position',[0.1 0.01 0.62 0.03], ...
        'Min',0, 'Max',max(0,t_raw(end)-window_sec), 'Value',0, ...
        'SliderStep',[min(1/max(1,t_raw(end)-window_sec),0.05) 0.2], ...
        'Callback', @(src,~) set_xlim(src.Value));
    uicontrol(fh, 'Style', 'pushbutton', 'String', 'Reviewed', ...
        'Units', 'normalized', 'Position', [0.76 0.008 0.18 0.038], ...
        'Callback', @(~,~) confirm_review());

    if edit_lungs
        set(pL, 'HitTest','on', 'PickableParts','visible', ...
            'ButtonDownFcn', @(~,evt) edit_peak(evt, ax1, 'lungs', 'trace'));
        set(pkL, 'HitTest','on', 'PickableParts','visible', ...
            'ButtonDownFcn', @(~,evt) edit_peak(evt, ax1, 'lungs', 'peak'));
    end
    if edit_diaph
        set(pD, 'HitTest','on', 'PickableParts','visible', ...
            'ButtonDownFcn', @(~,evt) edit_peak(evt, ax2, 'diaph', 'trace'));
        set(pkD, 'HitTest','on', 'PickableParts','visible', ...
            'ButtonDownFcn', @(~,evt) edit_peak(evt, ax2, 'diaph', 'peak'));
    end
    trough_plots = [trL; trD];
    trough_plots = trough_plots(isgraphics(trough_plots));
    if ~isempty(trough_plots)
        set(trough_plots, 'HitTest','off', 'PickableParts','none');
    end

    fprintf('\nManual breath control ON.\n');
    if edit_lungs && edit_diaph
        fprintf('  Editing lungs and diaphragm belts.\n');
    elseif edit_lungs
        fprintf('  Editing lungs belt only.\n');
    else
        fprintf('  Editing diaphragm belt only.\n');
    end
    fprintf('  Left-click a trace to add a red peak.\n');
    fprintf('  Left-click a red peak to remove it.\n');
    fprintf('  Blue troughs and amplitudes are recomputed automatically from the edited peaks.\n');
    fprintf('  Press Reviewed to accept the current respiratory cycles.\n');
    fprintf('  Closing the window cancels the review and discards this session''s edits.\n\n');
    uiwait(fh);
    if isgraphics(fh)
        delete(fh);
    end
    if ~review_confirmed
        b_l = automatic_lungs;
        b_d = automatic_diaph;
    end

    function confirm_review()
    % CONFIRM_REVIEW Perform the confirm review operation.
    %
    % Syntax:
    %   confirm_review()

        review_confirmed = true;
        if isgraphics(fh)
            uiresume(fh);
        end
    end

    function cancel_review()
    % CANCEL_REVIEW Perform the cancel review operation.
    %
    % Syntax:
    %   cancel_review()

        review_confirmed = false;
        if isgraphics(fh)
            uiresume(fh);
            delete(fh);
        end
    end

    function set_xlim(x0)
    % SET_XLIM Perform the set xlim operation.
    %
    % Syntax:
    %   set_xlim(x0)
    %
    % Inputs:
    %   x0 - Input value `x0`.

        xlim(ax1, [x0 min(x0+window_sec, t_raw(end))]);
    end

    function edit_peak(evt, ax, belt, target)
    % EDIT_PEAK Perform the edit peak operation.
    %
    % Syntax:
    %   edit_peak(evt, ax, belt, target)
    %
    % Inputs:
    %   evt - Input value `evt`.
    %   ax - Target axes handle.
    %   belt - Respiratory-cycle or belt-evidence structure.
    %   target - Input value `target`.

        if ~strcmp(get(fh, 'SelectionType'), 'normal')
            return;
        end

        t_click = get_click_time(evt, ax);
        if ~isfinite(t_click)
            return;
        end

        if strcmp(belt, 'lungs')
            if ~edit_lungs
                return;
            end
            b_l = update_breath_peaks(b_l, t_click, target);
            update_breath_plots(pkL, trL, b_l);
        else
            if ~edit_diaph
                return;
            end
            b_d = update_breath_peaks(b_d, t_click, target);
            update_breath_plots(pkD, trD, b_d);
        end
        drawnow;
    end

    function b = update_breath_peaks(b, t_click, target)
    % UPDATE_BREATH_PEAKS Update breath peaks.
    %
    % Syntax:
    %   b = update_breath_peaks(b, t_click, target)
    %
    % Inputs:
    %   b - Respiratory-cycle or belt-evidence structure.
    %   t_click - Input value `t_click`.
    %   target - Input value `target`.
    %
    % Outputs:
    %   b - Updated respiratory-cycle or belt structure.

        peak_idx = [];
        if isfield(b, 'peak_idx')
            peak_idx = b.peak_idx(:);
        end
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
    % NEAREST_LOCAL_PEAK_IDX Perform the nearest local peak idx operation.
    %
    % Syntax:
    %   idx = nearest_local_peak_idx(x, t_click)
    %
    % Inputs:
    %   x - Input value `x`.
    %   t_click - Input value `t_click`.
    %
    % Outputs:
    %   idx - Computed index or count value.

        idx = [];
        if isempty(x)
            return;
        end

        search_sec = 1.0;  % add peak at local maximum within this window around the click

        idx_click = max(1, min(numel(x), round(t_click * fs) + 1));
        radius = max(1, round(search_sec * fs));
        lo = max(1, idx_click - radius);
        hi = min(numel(x), idx_click + radius);
        [~, j] = max(x(lo:hi));
        idx = lo + j - 1;
    end

    function update_breath_plots(peak_plot, trough_plot, b)
    % UPDATE_BREATH_PLOTS Update breath plots.
    %
    % Syntax:
    %   update_breath_plots(peak_plot, trough_plot, b)
    %
    % Inputs:
    %   peak_plot - Input value `peak_plot`.
    %   trough_plot - Input value `trough_plot`.
    %   b - Respiratory-cycle or belt-evidence structure.

        set(peak_plot, 'XData', b.peak_t, 'YData', b.peak_val);
        set(trough_plot, 'XData', b.trough_t, 'YData', b.trough_val);
    end

    function t_click = get_click_time(evt, ax)
    % GET_CLICK_TIME Return click time.
    %
    % Syntax:
    %   t_click = get_click_time(evt, ax)
    %
    % Inputs:
    %   evt - Input value `evt`.
    %   ax - Target axes handle.
    %
    % Outputs:
    %   t_click - Computed output value `t_click`.

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

    function [signal_plot, peak_plot, trough_plot] = plot_belt_panel(ax, t, b, title_text, label_text, can_edit, unavailable_message)
    % PLOT_BELT_PANEL Plot belt panel.
    %
    % Syntax:
    %   [signal_plot, peak_plot, trough_plot] = plot_belt_panel(ax, t, b, title_text, label_text, can_edit, unavailable_message)
    %
    % Inputs:
    %   ax - Target axes handle.
    %   t - Time coordinates in seconds.
    %   b - Respiratory-cycle or belt-evidence structure.
    %   title_text - Input value `title_text`.
    %   label_text - Label identifier or label metadata.
    %   can_edit - Input value `can_edit`.
    %   unavailable_message - Input value `unavailable_message`.
    %
    % Outputs:
    %   signal_plot - Computed output value `signal_plot`.
    %   peak_plot - Computed output value `peak_plot`.
    %   trough_plot - Computed output value `trough_plot`.

        signal_plot = gobjects(0);
        peak_plot = gobjects(0);
        trough_plot = gobjects(0);

        if ~can_edit
            text(ax, 0.5, 0.5, unavailable_message, ...
                'Units', 'normalized', 'HorizontalAlignment', 'center');
            title(ax, [title_text ': unavailable']);
            ylabel(ax, label_text);
            grid(ax, 'on');
            return;
        end

        x = b.x0(:);
        n = min(numel(t), numel(x));
        signal_plot = plot(ax, t(1:n), x(1:n), 'k');
        [peak_t, peak_val] = paired_marker_fields(b, 'peak_t', 'peak_val');
        [trough_t, trough_val] = paired_marker_fields(b, 'trough_t', 'trough_val');
        peak_plot = plot(ax, peak_t, peak_val, 'ro', 'MarkerFaceColor','r', 'MarkerSize', 4);
        trough_plot = plot(ax, trough_t, trough_val, 'bo', 'MarkerFaceColor','b', 'MarkerSize', 4);
        title(ax, [title_text ': edit red peaks only; blue troughs update automatically']);
        ylabel(ax, label_text);
        legend(ax, [signal_plot; peak_plot; trough_plot], {'signal', 'peaks', 'troughs'}, 'Location','eastoutside');
        grid(ax, 'on');
    end

    function [marker_t, marker_val] = paired_marker_fields(b, t_field, val_field)
    % PAIRED_MARKER_FIELDS Perform the paired marker fields operation.
    %
    % Syntax:
    %   [marker_t, marker_val] = paired_marker_fields(b, t_field, val_field)
    %
    % Inputs:
    %   b - Respiratory-cycle or belt-evidence structure.
    %   t_field - Input value `t_field`.
    %   val_field - Input value `val_field`.
    %
    % Outputs:
    %   marker_t - Computed output value `marker_t`.
    %   marker_val - Computed output value `marker_val`.

        marker_t = [];
        marker_val = [];
        if ~isfield(b, t_field) || ~isfield(b, val_field)
            return;
        end

        marker_t = b.(t_field)(:);
        marker_val = b.(val_field)(:);
        n = min(numel(marker_t), numel(marker_val));
        marker_t = marker_t(1:n);
        marker_val = marker_val(1:n);
    end

    function msg = lungs_unavailable_message(cfg)
    % LUNGS_UNAVAILABLE_MESSAGE Perform the lungs unavailable message operation.
    %
    % Syntax:
    %   msg = lungs_unavailable_message(cfg)
    %
    % Inputs:
    %   cfg - Pipeline configuration structure.
    %
    % Outputs:
    %   msg - Computed output value `msg`.

        if is_lung_belt_ignored(cfg)
            msg = 'Resp-Lungs ignored for this recording';
        else
            msg = 'No editable Resp-Lungs signal';
        end
    end

    function set_panel_global_ylim(target_ax, b, can_edit)
    % SET_PANEL_GLOBAL_YLIM Perform the set panel global ylim operation.
    %
    % Syntax:
    %   set_panel_global_ylim(target_ax, b, can_edit)
    %
    % Inputs:
    %   target_ax - Target axes handle.
    %   b - Respiratory-cycle or belt-evidence structure.
    %   can_edit - Input value `can_edit`.

        if ~can_edit || ~isgraphics(target_ax) || ~isfield(b, 'x0') || isempty(b.x0)
            return;
        end
        ylim(target_ax, compute_global_ylim(b.x0(:)));
    end

    function y_limits = compute_global_ylim(signal)
    % COMPUTE_GLOBAL_YLIM Compute global ylim.
    %
    % Syntax:
    %   y_limits = compute_global_ylim(signal)
    %
    % Inputs:
    %   signal - Input value `signal`.
    %
    % Outputs:
    %   y_limits - Computed output value `y_limits`.

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
