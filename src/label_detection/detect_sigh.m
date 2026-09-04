function [events, diagnostics, review_info] = detect_sigh( ...
    data, resp_features, resp_cycles, spo2_ref, session_reference, ...
    diagnostics_Des, config)
% DETECT_SIGH Detect sigh.
%
% Syntax:
%   [events, diagnostics, review_info] = detect_sigh(data, resp_features, resp_cycles, spo2_ref, session_reference, diagnostics_Des, config)
%
% Inputs:
%   data - Input physiological signal data.
%   resp_features - Respiratory-feature structure.
%   resp_cycles - Respiratory-cycle structure.
%   spo2_ref - SpO2-reference structure.
%   session_reference - Session-reference metadata.
%   diagnostics_Des - Detector diagnostic data.
%   config - Pipeline configuration structure.
%
% Outputs:
%   events - Event structure array.
%   diagnostics - Detector diagnostic structure.
%   review_info - Computed summary or metadata structure.

    events = empty_events();

    N = size(data,1);
    fs = config.fs;
    t_grid = (0:config.grid_step_sec:(N-1)/config.fs)';

    lungs = resp_features.resp.lungs;
    diaph = resp_features.resp.diaph;
    lungs_valid = lungs.global_amplitude_available;
    diaph_valid = diaph.global_amplitude_available;
    diagnostics = struct( ...
        'available', lungs_valid || diaph_valid, ...
        'method', '', ...
        'ratio_percentile', NaN, ...
        'minimum_absolute_ratio', NaN, ...
        'iqr_multiplier', NaN, ...
        'lungs', empty_sigh_belt_diagnostics(lungs), ...
        'diaph', empty_sigh_belt_diagnostics(diaph));
    review_info = struct( ...
        'reviewed', false, ...
        'review_scope', 'unreviewed', ...
        'review_mask', false(N,1), ...
        'status', 'unreviewed', ...
        'weak_events', empty_events(), ...
        'reviewed_events', empty_events(), ...
        'weak_flags_lungs', false(size(lungs.peak_t(:))), ...
        'weak_flags_diaph', false(size(diaph.peak_t(:))), ...
        'reviewed_flags_lungs', false(size(lungs.peak_t(:))), ...
        'reviewed_flags_diaph', false(size(diaph.peak_t(:))));

    if ~lungs_valid && ~diaph_valid
        fprintf('Skipping sigh detection: no valid respiratory belt with usable breath amplitudes.\n');
        return;
    end
    
    method = 'global_ratio_outlier';
    ratio_prctile = 98;
    
    % New robust sigh criteria
    min_abs_ratio = 1.8;      % sigh must be at least 1.8x the whole-record amplitude reference
    iqr_k = 3.5;              % robust outlier threshold: median + iqr_k*IQR
    min_gap_sec = 20;         % avoid multiple nearby detections
    
    do_plot = false;
    manual_control = true;
    manual_window_sec = 1000;

    % legacy
    legacy_prev_win_sec = 60;
    legacy_amp_ratio_thr = 1.5;
    legacy_min_prev_breaths = 3;

    if isfield(config,'Sig')
        if isfield(config.Sig,'method'), method = config.Sig.method; end
        if isfield(config.Sig,'ratio_prctile'), ratio_prctile = config.Sig.ratio_prctile; end
        if isfield(config.Sig,'do_plot'), do_plot = config.Sig.do_plot; end
        if isfield(config.Sig,'manual_control'), manual_control = logical(config.Sig.manual_control); end
        if isfield(config.Sig,'manual_window_sec'), manual_window_sec = config.Sig.manual_window_sec; end
        if isfield(config.Sig,'min_abs_ratio'), min_abs_ratio = config.Sig.min_abs_ratio; end
        if isfield(config.Sig,'iqr_k'), iqr_k = config.Sig.iqr_k; end
        if isfield(config.Sig,'min_gap_sec'), min_gap_sec = config.Sig.min_gap_sec; end

        if isfield(config.Sig,'legacy_prev_win_sec'), legacy_prev_win_sec = config.Sig.legacy_prev_win_sec; end
        if isfield(config.Sig,'legacy_amp_ratio_thr'), legacy_amp_ratio_thr = config.Sig.legacy_amp_ratio_thr; end
        if isfield(config.Sig,'legacy_min_prev_breaths'), legacy_min_prev_breaths = config.Sig.legacy_min_prev_breaths; end
    end

    switch lower(method)
        case 'legacy_60s'
            sigh_lungs = false(size(lungs.peak_t(:)));
            if lungs_valid
                sigh_lungs = sigh_flags_legacy_60s(lungs, legacy_prev_win_sec, legacy_amp_ratio_thr, legacy_min_prev_breaths);
                diagnostics.lungs.decision_threshold = legacy_amp_ratio_thr;
            end
            sigh_diaph = false(size(diaph.peak_t(:)));
            if diaph_valid
                sigh_diaph = sigh_flags_legacy_60s(diaph, legacy_prev_win_sec, legacy_amp_ratio_thr, legacy_min_prev_breaths);
                diagnostics.diaph.decision_threshold = legacy_amp_ratio_thr;
            end
        otherwise
            sigh_lungs = false(size(lungs.peak_t(:)));
            if lungs_valid
                [sigh_lungs, ~, diagnostics.lungs.amp_ratio_global, ...
                    diagnostics.lungs.decision_threshold] = sigh_flags_global_ratio_outlier( ...
                    lungs, ratio_prctile, ...
                    min_abs_ratio, iqr_k, min_gap_sec);
            end
            
            sigh_diaph = false(size(diaph.peak_t(:)));
            if diaph_valid
                [sigh_diaph, ~, diagnostics.diaph.amp_ratio_global, ...
                    diagnostics.diaph.decision_threshold] = sigh_flags_global_ratio_outlier( ...
                    diaph, ratio_prctile, ...
                    min_abs_ratio, iqr_k, min_gap_sec);
            end
    end
    diagnostics.method = char(string(method));
    diagnostics.ratio_percentile = ratio_prctile;
    diagnostics.minimum_absolute_ratio = min_abs_ratio;
    diagnostics.iqr_multiplier = iqr_k;

    weak_sigh_lungs = sigh_lungs;
    weak_sigh_diaph = sigh_diaph;
    weak_events_L = sigh_flags_to_events(lungs.peak_t, weak_sigh_lungs, N, fs, 'lungs');
    weak_events_D = sigh_flags_to_events(diaph.peak_t, weak_sigh_diaph, N, fs, 'diaph');
    weak_events = merge_events({weak_events_L, weak_events_D});
    review_info.weak_events = weak_events;
    review_info.weak_flags_lungs = weak_sigh_lungs;
    review_info.weak_flags_diaph = weak_sigh_diaph;

    if manual_control && lungs_valid && diaph_valid
        [sigh_lungs, sigh_diaph, sigh_review_mask] = manual_edit_sigh_flags( ...
            data, resp_cycles.lungs, resp_cycles.diaph, sigh_lungs, sigh_diaph, ...
            spo2_ref, session_reference, diagnostics_Des, config, manual_window_sec);
        review_info.reviewed = true;
        review_info.review_scope = 'explicitly_viewed_regions_sigh_breaths_both_belts';
        review_info.review_mask = sigh_review_mask;
    elseif manual_control
        warning('MAGMA:Sigh:ManualSkipped', ...
            'Manual sigh editing requires two valid respiratory belts and was skipped for this input configuration.');
    end

    events_L = sigh_flags_to_events(lungs.peak_t, sigh_lungs, N, fs, 'lungs');
    events_D = sigh_flags_to_events(diaph.peak_t, sigh_diaph, N, fs, 'diaph');
    diagnostics.lungs.selected_breath_mask = weak_sigh_lungs;
    diagnostics.diaph.selected_breath_mask = weak_sigh_diaph;
    diagnostics.lungs.reviewed_selected_breath_mask = sigh_lungs;
    diagnostics.diaph.reviewed_selected_breath_mask = sigh_diaph;
    events = merge_events({events_L, events_D});
    review_info.reviewed_events = events;
    review_info.reviewed_flags_lungs = sigh_lungs;
    review_info.reviewed_flags_diaph = sigh_diaph;
    if review_info.reviewed
        if event_sets_equal(weak_events, events)
            review_info.status = 'reviewed_accepted';
        elseif ~isempty(weak_events) && isempty(events)
            review_info.status = 'reviewed_rejected';
        else
            review_info.status = 'reviewed_edited';
        end
    end

    if do_plot
        if ~isfield(config, 'channels')
            config = resolve_signal_channels(config);
        end
        idx_lungs = config.channels.lungs_idx;
        idx_diaph = config.channels.diaph_idx;

        t_raw = (0:N-1)/fs;

        figure('Units','pixels','Position', near_fullscreen_figure_position(), 'Visible', config.make_figs_visible);
        sgtitle(['SIGH | Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)])

        ax1 = subplot(3,1,1); hold on
        h_lungs_trace = gobjects(0);
        if ~isempty(idx_lungs), h_lungs_trace = plot(t_raw, data(:,idx_lungs), 'k', 'DisplayName', 'Resp-Lungs'); end
        shade_events_on_axis(gca, events_L, 'sigh lungs');
        if ~isempty(idx_lungs)
            y_lungs_mark = interp1(t_raw, data(:,idx_lungs), lungs.peak_t(sigh_lungs), 'linear', 'extrap');
        else
            y_lungs_mark = nan(sum(sigh_lungs),1);
        end
        h_lungs_sigh = plot(lungs.peak_t(sigh_lungs), y_lungs_mark, 'ro', 'MarkerFaceColor','r', ...
            'DisplayName', 'Sigh breaths');
        title('Sigh detection (lungs): red dots = sigh breaths')
        add_axis_legend(gca, [h_lungs_trace; h_lungs_sigh], {'Resp-Lungs', 'Sigh breaths'});
        xlabel('Time (s)'); ylabel('Resp-Lungs'); grid on; hold off

        ax2 = subplot(3,1,2); hold on
        h_diaph_trace = gobjects(0);
        if ~isempty(idx_diaph), h_diaph_trace = plot(t_raw, data(:,idx_diaph), 'k', 'DisplayName', 'Resp-Diaphragm'); end
        shade_events_on_axis(gca, events_D, 'sigh diaphragm');
        if ~isempty(idx_diaph)
            y_diaph_mark = interp1(t_raw, data(:,idx_diaph), diaph.peak_t(sigh_diaph), 'linear', 'extrap');
        else
            y_diaph_mark = nan(sum(sigh_diaph),1);
        end
        h_diaph_sigh = plot(diaph.peak_t(sigh_diaph), y_diaph_mark, 'ro', 'MarkerFaceColor','r', ...
            'DisplayName', 'Sigh breaths');
        title('Sigh detection (diaphragm): red dots = sigh breaths')
        add_axis_legend(gca, [h_diaph_trace; h_diaph_sigh], {'Resp-Diaphragm', 'Sigh breaths'});
        xlabel('Time (s)'); ylabel('Resp-Diaphragm'); grid on; hold off

        % ----------------------
        % Subplot 3: SpO2 + desaturation thresholds
        % ----------------------
        ax3 = subplot(3,1,3);
        plot_spo2_diagnostic_panel(ax3, data, spo2_ref, session_reference, ...
            diagnostics_Des, config, 'SpO2 with desaturation thresholds');
    
        linkaxes([ax1 ax2 ax3], 'x');
        xlim(ax1, [0 t_grid(end)]);
        align_axes_x_widths([ax1 ax2 ax3]);

        title('SpO₂')
        xlabel('Time (s)')
        ylabel('SpO₂ (%)')
        grid on
        hold off
        title(ax3, 'SpO2 with desaturation thresholds')
        align_axes_x_widths([ax1 ax2 ax3]);

        save_figure(config, 'sigh');
    end
end

function diagnostics = empty_sigh_belt_diagnostics(belt)
% EMPTY_SIGH_BELT_DIAGNOSTICS Create an empty sigh belt diagnostics value.
%
% Syntax:
%   diagnostics = empty_sigh_belt_diagnostics(belt)
%
% Inputs:
%   belt - Respiratory-cycle or belt-evidence structure.
%
% Outputs:
%   diagnostics - Detector diagnostic structure.

    diagnostics = struct( ...
        'available', belt.global_amplitude_available, ...
        'reference_quality', belt.reference_quality, ...
        'peak_t', belt.peak_t, ...
        'amp_ratio_global', belt.amp_ratio_global, ...
        'decision_threshold', NaN, ...
        'selected_breath_mask', false(size(belt.peak_t)), ...
        'reviewed_selected_breath_mask', false(size(belt.peak_t)));
end

function tf = event_sets_equal(a, b)
% EVENT_SETS_EQUAL Perform the event sets equal operation.
%
% Syntax:
%   tf = event_sets_equal(a, b)
%
% Inputs:
%   a - Input value `a`.
%   b - Respiratory-cycle or belt-evidence structure.
%
% Outputs:
%   tf - Computed output value `tf`.

    if numel(a) ~= numel(b)
        tf = false;
        return;
    end
    if isempty(a)
        tf = true;
        return;
    end
    a = sortrows(struct2table(a), {'type', 'start_idx', 'end_idx'});
    b = sortrows(struct2table(b), {'type', 'start_idx', 'end_idx'});
    tf = isequal(a.type, b.type) && isequal(a.start_idx, b.start_idx) && ...
        isequal(a.end_idx, b.end_idx);
end

function [sigh_flags, local_ref, ratio, ratio_thr] = sigh_flags_global_ratio_outlier( ...
    b, ratio_prctile, min_abs_ratio, iqr_k, min_gap_sec)
% SIGH_FLAGS_GLOBAL_RATIO_OUTLIER Perform the sigh flags global ratio outlier operation.
%
% Syntax:
%   [sigh_flags, local_ref, ratio, ratio_thr] = sigh_flags_global_ratio_outlier(b, ratio_prctile, min_abs_ratio, iqr_k, min_gap_sec)
%
% Inputs:
%   b - Respiratory-cycle or belt-evidence structure.
%   ratio_prctile - Input value `ratio_prctile`.
%   min_abs_ratio - Input value `min_abs_ratio`.
%   iqr_k - Input value `iqr_k`.
%   min_gap_sec - Duration or window length in seconds.
%
% Outputs:
%   sigh_flags - Logical output mask.
%   local_ref - Computed output value `local_ref`.
%   ratio - Computed numeric value.
%   ratio_thr - Computed numeric value.

    peak_t = b.peak_t(:);
    amp = b.amp(:);

    L = min(numel(peak_t), numel(amp));
    peak_t = peak_t(1:L);
    amp = amp(1:L);
    sigh_flags = false(L,1);
    ratio_thr = NaN;

    if L < 10
        local_ref = nan(L,1);
        ratio = nan(L,1);
        return;
    end

    ratio = b.amp_ratio_global(:);
    ratio = ratio(1:L);
    local_ref = b.global_reference_value * ones(L, 1);
    valid = isfinite(ratio) & ratio > 0 & isfinite(amp) & amp > 0 & isfinite(local_ref) & local_ref > 0;

    if sum(valid) < 10
        return;
    end

    rv = ratio(valid);
    
    thr_pct = prctile(rv, ratio_prctile);
    thr_iqr = median(rv, 'omitnan') + iqr_k * iqr(rv);
    
    % Final threshold: percentile alone is not enough.
    % This prevents healthy controls from always getting the top 2% labeled.
    ratio_thr = max([thr_pct, thr_iqr, min_abs_ratio]);
    
    candidate_flags = false(L,1);
    candidate_flags(valid) = ratio(valid) >= ratio_thr;
    
    % Optional cleanup: keep only the strongest sigh within min_gap_sec.
    sigh_flags = enforce_min_gap_by_strength(candidate_flags, peak_t, ratio, min_gap_sec);
end


function sigh_flags = sigh_flags_legacy_60s(b, prev_win_sec, amp_ratio_thr, min_prev_breaths)
% SIGH_FLAGS_LEGACY_60S Perform the sigh flags legacy 60s operation.
%
% Syntax:
%   sigh_flags = sigh_flags_legacy_60s(b, prev_win_sec, amp_ratio_thr, min_prev_breaths)
%
% Inputs:
%   b - Respiratory-cycle or belt-evidence structure.
%   prev_win_sec - Duration or window length in seconds.
%   amp_ratio_thr - Selection threshold value.
%   min_prev_breaths - Input value `min_prev_breaths`.
%
% Outputs:
%   sigh_flags - Logical output mask.

    peak_t = b.peak_t(:);
    amp = b.amp(:);
    L = min(numel(peak_t), numel(amp));
    peak_t = peak_t(1:L);
    amp = amp(1:L);
    sigh_flags = false(L,1);

    for i = 1:L
        t = peak_t(i);
        lb = t - prev_win_sec;
        if lb < 0, continue; end
        prev_idx = find(peak_t < t & peak_t >= lb);
        if numel(prev_idx) < min_prev_breaths, continue; end
        med_prev = median(amp(prev_idx), 'omitnan');
        if ~isfinite(med_prev) || med_prev <= 0 || ~isfinite(amp(i)), continue; end
        if amp(i) >= amp_ratio_thr * med_prev
            sigh_flags(i) = true;
        end
    end
end

% rest unchanged

function events = sigh_flags_to_events(peak_t, flags, N, fs, belt)
% SIGH_FLAGS_TO_EVENTS Perform the sigh flags to events operation.
%
% Syntax:
%   events = sigh_flags_to_events(peak_t, flags, N, fs, belt)
%
% Inputs:
%   peak_t - Input value `peak_t`.
%   flags - Logical state or selection mask.
%   N - Number of samples.
%   fs - Sampling frequency in hertz.
%   belt - Respiratory-cycle or belt-evidence structure.
%
% Outputs:
%   events - Event structure array.

    events = empty_events();
    peak_t = peak_t(:);
    flags  = logical(flags(:));
    L = min(numel(peak_t), numel(flags));
    peak_t = peak_t(1:L);
    flags  = flags(1:L);

    n_events = sum(flags);
    if n_events == 0
        return;
    end
    template = struct( ...
        'type', '', ...
        'start_idx', 0, ...
        'end_idx', 0, ...
        'start_t', 0, ...
        'end_t', 0, ...
        'duration', 0);
    events = repmat(template, n_events, 1);
    out = 0;

    for i = 1:L
        if ~flags(i), continue; end

        t0 = peak_t(i);
        if i == 1 && L >= 2
            dt = peak_t(i+1) - peak_t(i);
            start_t = max(0, t0 - 0.5*dt);
        elseif i > 1
            start_t = 0.5*(peak_t(i-1) + peak_t(i));
        else
            start_t = max(0, t0 - 0.5); % fallback
        end

        if i == L && L >= 2
            dt = peak_t(i) - peak_t(i-1);
            end_t = min(N/fs, t0 + 0.5*dt);
        elseif i < L
            end_t = 0.5*(peak_t(i) + peak_t(i+1));
        else
            end_t = min(N/fs, t0 + 0.5); % fallback
        end

        s = max(1, min(N, round(start_t*fs) + 1));
        e = max(s, min(N, round(end_t*fs)));

        start_t = (s-1)/fs;
        end_t   = e/fs;

        out = out + 1;
        events(out) = struct( ...
            'type', ['sigh_' belt], ...
            'start_idx', s, ...
            'end_idx', e, ...
            'start_t', start_t, ...
            'end_t', end_t, ...
            'duration', (e - s + 1) / fs );

    end

    events = events(1:out);
end

function flags_out = enforce_min_gap_by_strength(flags_in, peak_t, strength, min_gap_sec)
% ENFORCE_MIN_GAP_BY_STRENGTH Perform the enforce min gap by strength operation.
%
% Syntax:
%   flags_out = enforce_min_gap_by_strength(flags_in, peak_t, strength, min_gap_sec)
%
% Inputs:
%   flags_in - Logical state or selection mask.
%   peak_t - Input value `peak_t`.
%   strength - Input value `strength`.
%   min_gap_sec - Duration or window length in seconds.
%
% Outputs:
%   flags_out - Logical output mask.

    flags_in = logical(flags_in(:));
    peak_t = peak_t(:);
    strength = strength(:);

    flags_out = false(size(flags_in));

    idx = find(flags_in);
    if isempty(idx)
        return;
    end

    % Sort candidates from strongest to weakest.
    [~, order] = sort(strength(idx), 'descend', 'MissingPlacement', 'last');
    idx_sorted = idx(order);

    for k = 1:numel(idx_sorted)
        i = idx_sorted(k);

        if ~isfinite(peak_t(i)) || ~isfinite(strength(i))
            continue;
        end

        already_kept = find(flags_out);
        if isempty(already_kept)
            flags_out(i) = true;
            continue;
        end

        too_close = any(abs(peak_t(already_kept) - peak_t(i)) < min_gap_sec);

        if ~too_close
            flags_out(i) = true;
        end
    end
end

function add_axis_legend(ax, handles, labels)
% ADD_AXIS_LEGEND Add axis legend.
%
% Syntax:
%   add_axis_legend(ax, handles, labels)
%
% Inputs:
%   ax - Target axes handle.
%   handles - Input value `handles`.
%   labels - Label identifier or label metadata.

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
        return;
    end
    legend(ax, handles, labels, 'Location', 'eastoutside');
end
