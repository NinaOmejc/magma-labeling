function [b_l, b_d, review_confirmed] = manual_edit_respiration_features(data, b_l, b_d, config)
% MANUAL_EDIT_RESPIRATION_FEATURES Edit respiratory cycles and explicitly confirm review.
%
% Inputs:
%   data   - Nsample x Nchannel preprocessed signal matrix.
%   b_l    - Lung-belt breath struct containing x0 and editable peak indices/times.
%   b_d    - Diaphragm-belt breath struct with the same required fields.
%   config - Sampling, peak-distance, belt-availability, and display settings.
%
% Outputs:
%   b_l, b_d         - Breath structs with peaks, automatic or manually moved
%                      troughs, amplitudes, IBIs, and rates recomputed after edits.
%   review_confirmed - True only when the reviewer accepts the displayed cycles;
%                      cancellation restores both complete pre-session structs.

    fs = config.fs;
    N = size(data, 1);
    t_raw = (0:N-1) / fs;
    pre_session_lungs = b_l;
    pre_session_diaph = b_d;
    review_confirmed = false;
    edit_mode = 'peaks';
    selected_belt = '';
    selected_left_peak = NaN;
    selected_right_peak = NaN;

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
        'GUI breath landmark review (lungs)', 'Resp-Lungs', edit_lungs, lungs_unavailable_message(config));

    ax2 = subplot(2,1,2); hold(ax2, 'on');
    [pD, pkD, trD] = plot_belt_panel(ax2, t_raw, b_d, ...
        'GUI breath landmark review (diaphragm)', 'Resp-Diaphragm', edit_diaph, ...
        'No editable Resp-Diaphragm signal');

    sgtitle(['GUI RESPIRATORY LANDMARK REVIEW' newline ...
        'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)]);

    xlabel(ax2, 'Time (s)');
    set_panel_global_ylim(ax1, b_l, edit_lungs);
    set_panel_global_ylim(ax2, b_d, edit_diaph);

    linkaxes([ax1 ax2], 'x');
    xlim(ax1, [0 min(window_sec, t_raw(end))]);

    status_text = uicontrol(fh, 'Style', 'text', 'Units', 'normalized', ...
        'Position', [0.05 0.046 0.91 0.025], ...
        'HorizontalAlignment', 'left', ...
        'String', 'Peak editing: click the trace to add or a red peak to remove.');
    uicontrol(fh, 'Style','slider', 'Units','normalized', 'Position',[0.05 0.01 0.42 0.03], ...
        'Min',0, 'Max',max(0,t_raw(end)-window_sec), 'Value',0, ...
        'SliderStep',[min(1/max(1,t_raw(end)-window_sec),0.05) 0.2], ...
        'Callback', @(src,~) set_xlim(src.Value));
    uicontrol(fh, 'Style', 'popupmenu', ...
        'String', {'Edit peaks', 'Move trough'}, ...
        'Units', 'normalized', 'Position', [0.50 0.008 0.20 0.038], ...
        'Callback', @(src,~) change_edit_mode(src));
    uicontrol(fh, 'Style', 'pushbutton', 'String', 'Reviewed', ...
        'Units', 'normalized', 'Position', [0.72 0.008 0.24 0.038], ...
        'Callback', @(~,~) confirm_review());

    selectedL = plot(ax1, NaN, NaN, 'o', 'MarkerSize', 10, ...
        'LineWidth', 1.5, 'MarkerEdgeColor', [0 0.7 0.9], ...
        'HitTest', 'off', 'PickableParts', 'none', 'HandleVisibility', 'off');
    selectedD = plot(ax2, NaN, NaN, 'o', 'MarkerSize', 10, ...
        'LineWidth', 1.5, 'MarkerEdgeColor', [0 0.7 0.9], ...
        'HitTest', 'off', 'PickableParts', 'none', 'HandleVisibility', 'off');

    if edit_lungs
        set(pL, 'HitTest','on', 'PickableParts','visible', ...
            'ButtonDownFcn', @(~,evt) edit_peak(evt, ax1, 'lungs', 'trace'));
        set(pkL, 'HitTest','on', 'PickableParts','visible', ...
            'ButtonDownFcn', @(~,evt) edit_peak(evt, ax1, 'lungs', 'peak'));
        set(trL, 'HitTest','on', 'PickableParts','visible', ...
            'ButtonDownFcn', @(~,evt) select_trough(evt, ax1, 'lungs'));
    end
    if edit_diaph
        set(pD, 'HitTest','on', 'PickableParts','visible', ...
            'ButtonDownFcn', @(~,evt) edit_peak(evt, ax2, 'diaph', 'trace'));
        set(pkD, 'HitTest','on', 'PickableParts','visible', ...
            'ButtonDownFcn', @(~,evt) edit_peak(evt, ax2, 'diaph', 'peak'));
        set(trD, 'HitTest','on', 'PickableParts','visible', ...
            'ButtonDownFcn', @(~,evt) select_trough(evt, ax2, 'diaph'));
    end
    set_trough_pickability(false);

    if edit_lungs && edit_diaph
        belt_description = 'lungs + diaphragm';
        detailed_belt_message = '  Editing lungs and diaphragm belts.';
    elseif edit_lungs
        belt_description = 'lungs';
        detailed_belt_message = '  Editing lungs belt only.';
    else
        belt_description = 'diaphragm';
        detailed_belt_message = '  Editing diaphragm belt only.';
    end
    log_message(config, 1, ...
        ['Manual breath review ON (%s): edit peaks or move existing ' ...
         'troughs; press Reviewed to accept.'], belt_description);
    log_message(config, 2, '\nManual breath control ON.');
    log_message(config, 2, detailed_belt_message);
    log_message(config, 2, '  Left-click a trace to add a red peak.');
    log_message(config, 2, '  Left-click a red peak to remove it.');
    log_message(config, 2, ...
        ['  Select Move trough, click a blue dot, then click its corrected ' ...
         'sample on the same signal.']);
    log_message(config, 2, ...
        ['  Blue dots are editable trough landmarks, not explicit hold ' ...
         'boundaries.']);
    log_message(config, 2, ...
        '  Press Reviewed to accept the current respiratory cycles.');
    log_message(config, 2, ...
        ['  Closing the window cancels the review and discards this ' ...
         'session''s edits.\n']);
    uiwait(fh);
    if isgraphics(fh)
        delete(fh);
    end
    if ~review_confirmed
        b_l = pre_session_lungs;
        b_d = pre_session_diaph;
    end

    function confirm_review()
    % CONFIRM_REVIEW Accept the edited breath cycles and resume execution.

        review_confirmed = true;
        if isgraphics(fh)
            uiresume(fh);
        end
    end

    function cancel_review()
    % CANCEL_REVIEW Reject this editing session and close the review figure.

        review_confirmed = false;
        if isgraphics(fh)
            uiresume(fh);
            delete(fh);
        end
    end

    function set_xlim(x0)
    % SET_XLIM Move the linked review viewport to start time x0 in seconds.

        xlim(ax1, [x0 min(x0+window_sec, t_raw(end))]);
    end

    function change_edit_mode(src)
    % CHANGE_EDIT_MODE Switch between the existing peak workflow and trough movement.

        clear_trough_selection();
        if get(src, 'Value') == 2
            edit_mode = 'trough';
            set_trough_pickability(true);
            show_status('Move trough: select a blue dot, then click its corrected location.', false);
        else
            edit_mode = 'peaks';
            set_trough_pickability(false);
            show_status('Peak editing: click the trace to add or a red peak to remove.', false);
        end
    end

    function set_trough_pickability(can_pick)
    % SET_TROUGH_PICKABILITY Let trough dots receive clicks only in trough mode.

        trough_plots = [trL; trD];
        trough_plots = trough_plots(isgraphics(trough_plots));
        if isempty(trough_plots)
            return;
        end
        if can_pick
            set(trough_plots, 'HitTest', 'on', 'PickableParts', 'visible');
        else
            set(trough_plots, 'HitTest', 'off', 'PickableParts', 'none');
        end
    end

    function edit_peak(evt, ax, belt, target)
    % EDIT_PEAK Add a nearby local maximum or remove a selected breath peak.
    % belt selects lungs/diaphragm and target distinguishes trace from peak clicks.

        if ~strcmp(get(fh, 'SelectionType'), 'normal')
            return;
        end

        t_click = get_click_time(evt, ax);
        if ~isfinite(t_click)
            return;
        end

        if strcmp(edit_mode, 'trough')
            if strcmp(target, 'trace')
                move_selected_trough(t_click, belt);
            end
            return;
        end

        clear_trough_selection();
        if strcmp(belt, 'lungs')
            if ~edit_lungs
                return;
            end
            [b_l, invalidated] = update_breath_peaks(b_l, t_click, target);
            update_breath_plots(pkL, trL, b_l);
        else
            if ~edit_diaph
                return;
            end
            [b_d, invalidated] = update_breath_peaks(b_d, t_click, target);
            update_breath_plots(pkD, trD, b_d);
        end
        if invalidated > 0
            show_status(sprintf(['Peak edit accepted; %d trough override(s) ' ...
                'whose surrounding peak pair changed were removed.'], invalidated), false);
        else
            show_status('Peak edit accepted.', false);
        end
        drawnow;
    end

    function [b, invalidated] = update_breath_peaks(b, t_click, target)
    % UPDATE_BREATH_PEAKS Modify peak indices and recompute dependent breath fields.
    % t_click is seconds; a peak target removes the closest existing peak,
    % while a trace target adds a local maximum unless it is a near duplicate.

        peak_idx = [];
        override_count_before = size(valid_override_rows(b), 1);
        invalidated = 0;
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
        invalidated = override_count_before - size(valid_override_rows(b), 1);
    end

    function select_trough(evt, ax, belt)
    % SELECT_TROUGH Select the existing trough and its surrounding peak samples.

        if ~strcmp(edit_mode, 'trough') || ...
                ~strcmp(get(fh, 'SelectionType'), 'normal')
            return;
        end
        t_click = get_click_time(evt, ax);
        if strcmp(belt, 'lungs')
            b = b_l;
        else
            b = b_d;
        end
        if ~isfinite(t_click) || isempty(b.trough_t)
            return;
        end
        [~, interval_idx] = min(abs(b.trough_t(:) - t_click));
        if interval_idx > numel(b.peak_idx) - 1
            show_status('The selected blue dot is not aligned to an interpeak interval.', true);
            return;
        end
        selected_belt = belt;
        selected_left_peak = b.peak_idx(interval_idx);
        selected_right_peak = b.peak_idx(interval_idx + 1);
        update_selection_marker(b, interval_idx);
        show_status(sprintf(['Selected %s trough between samples %d and %d. ' ...
            'Click the corrected location on the same signal.'], ...
            belt, selected_left_peak, selected_right_peak), false);
    end

    function move_selected_trough(t_click, clicked_belt)
    % MOVE_SELECTED_TROUGH Place the selected trough at the nearest clicked sample.

        if isempty(selected_belt)
            show_status('Select a blue trough dot before choosing its corrected location.', true);
            return;
        end
        if ~strcmp(clicked_belt, selected_belt)
            show_status('Place the trough on the same signal from which it was selected.', true);
            return;
        end
        new_idx = round(t_click * fs) + 1;
        try
            if strcmp(selected_belt, 'lungs')
                b_l = set_respiration_trough_override(b_l, ...
                    selected_left_peak, selected_right_peak, new_idx, config);
                update_breath_plots(pkL, trL, b_l);
                refresh_selection_marker(b_l);
            else
                b_d = set_respiration_trough_override(b_d, ...
                    selected_left_peak, selected_right_peak, new_idx, config);
                update_breath_plots(pkD, trD, b_d);
                refresh_selection_marker(b_d);
            end
            show_status(sprintf('Trough moved to sample %d (%.3f s).', ...
                new_idx, (new_idx - 1) / fs), false);
        catch err
            if startsWith(err.identifier, 'MAGMA:Respiration:')
                show_status(err.message, true);
            else
                rethrow(err);
            end
        end
        drawnow;
    end

    function refresh_selection_marker(b)
    % REFRESH_SELECTION_MARKER Follow the selected pair after recomputation.

        interval_idx = find(b.peak_idx(1:end-1) == selected_left_peak & ...
            b.peak_idx(2:end) == selected_right_peak, 1);
        if isempty(interval_idx)
            clear_trough_selection();
            return;
        end
        update_selection_marker(b, interval_idx);
    end

    function update_selection_marker(b, interval_idx)
    % UPDATE_SELECTION_MARKER Draw a cyan ring around the selected blue dot.

        if strcmp(selected_belt, 'lungs')
            set(selectedL, 'XData', b.trough_t(interval_idx), ...
                'YData', b.trough_val(interval_idx));
            set(selectedD, 'XData', NaN, 'YData', NaN);
        else
            set(selectedD, 'XData', b.trough_t(interval_idx), ...
                'YData', b.trough_val(interval_idx));
            set(selectedL, 'XData', NaN, 'YData', NaN);
        end
    end

    function clear_trough_selection()
    % CLEAR_TROUGH_SELECTION Clear the selected pair and highlight.

        selected_belt = '';
        selected_left_peak = NaN;
        selected_right_peak = NaN;
        if isgraphics(selectedL)
            set(selectedL, 'XData', NaN, 'YData', NaN);
        end
        if isgraphics(selectedD)
            set(selectedD, 'XData', NaN, 'YData', NaN);
        end
    end

    function rows = valid_override_rows(b)
    % VALID_OVERRIDE_ROWS Return well-formed persistent override rows for GUI counts.

        rows = zeros(0, 3);
        if isfield(b, 'trough_overrides') && ...
                isnumeric(b.trough_overrides) && ...
                size(b.trough_overrides, 2) == 3
            candidate = double(b.trough_overrides);
            keep = all(isfinite(candidate), 2) & ...
                all(candidate == round(candidate), 2) & all(candidate >= 1, 2);
            rows = candidate(keep, :);
        end
    end

    function show_status(message, is_error)
    % SHOW_STATUS Present clear, non-modal interaction feedback.

        if ~isgraphics(status_text)
            return;
        end
        if is_error
            color = [0.75 0 0];
        else
            color = [0 0.35 0];
        end
        set(status_text, 'String', message, 'ForegroundColor', color);
    end

    function idx = nearest_local_peak_idx(x, t_click)
    % NEAREST_LOCAL_PEAK_IDX Find the maximum within one second of a click.
    % x is a sample vector, t_click is seconds, and idx is a one-based sample index.

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
    % UPDATE_BREATH_PLOTS Refresh peak and derived-trough marker coordinates.

        set(peak_plot, 'XData', b.peak_t, 'YData', b.peak_val);
        set(trough_plot, 'XData', b.trough_t, 'YData', b.trough_val);
    end

    function t_click = get_click_time(evt, ax)
    % GET_CLICK_TIME Resolve event intersection or axes cursor time in seconds.

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
    % PLOT_BELT_PANEL Draw one belt trace with editable peaks and derived troughs.
    % t is the sample-time vector in seconds and b provides x0 plus marker
    % fields. Outputs are graphics handles or empty handles when unavailable.

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
        title(ax, [title_text ': red peaks and blue trough landmarks are editable']);
        ylabel(ax, label_text);
        legend(ax, [signal_plot; peak_plot; trough_plot], {'signal', 'peaks', 'troughs'}, 'Location','eastoutside');
        grid(ax, 'on');
    end

    function [marker_t, marker_val] = paired_marker_fields(b, t_field, val_field)
    % PAIRED_MARKER_FIELDS Extract aligned marker times and signal values for display.
    % The named breath fields are columnized; unmatched trailing display values
    % are omitted without modifying the underlying breath struct.

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
    % LUNGS_UNAVAILABLE_MESSAGE Explain ignored versus non-editable lung data.

        if is_lung_belt_ignored(cfg)
            msg = 'Resp-Lungs ignored for this recording';
        else
            msg = 'No editable Resp-Lungs signal';
        end
    end

    function set_panel_global_ylim(target_ax, b, can_edit)
    % SET_PANEL_GLOBAL_YLIM Keep belt scaling fixed while the viewport scrolls.

        if ~can_edit || ~isgraphics(target_ax) || ~isfield(b, 'x0') || isempty(b.x0)
            return;
        end
        ylim(target_ax, compute_global_ylim(b.x0(:)));
    end

    function y_limits = compute_global_ylim(signal)
    % COMPUTE_GLOBAL_YLIM Bound a full sample trace with five-percent padding.

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
