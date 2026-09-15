function [events, diagnostics, review_info] = detect_sigh( ...
    data, resp_features, resp_cycles, config)
% DETECT_SIGH Identify isolated high-amplitude breaths and optionally review them.
% data/resp_cycles supply sample signals and breath markers; resp_features
% supplies global-normalized amplitudes; config controls outlier or legacy
% criteria, spacing, plotting, and review.
% events are midpoint-bounded breath events. diagnostics stores compact per-belt
% availability, reference quality, and recording-specific decision thresholds.
% review_info records review scope/status,
% sample review_mask, automatic/reviewed events, and per-belt breath flags.

    events = empty_events();

    N = size(data,1);
    fs = config.fs;

    lungs = resp_features.lungs;
    diaph = resp_features.diaph;
    lungs_valid = lungs.global_amplitude_available;
    diaph_valid = diaph.global_amplitude_available;
    diagnostics = struct( ...
        'available', lungs_valid || diaph_valid, ...
        'lungs', empty_sigh_belt_diagnostics(lungs), ...
        'diaph', empty_sigh_belt_diagnostics(diaph));
    review_info = struct( ...
        'reviewed', false, ...
        'review_scope', 'unreviewed', ...
        'review_mask', false(N,1), ...
        'status', 'unreviewed', ...
        'automatic_events', empty_events(), ...
        'reviewed_events', empty_events(), ...
        'automatic_flags_lungs', false(size(lungs.peak_t(:))), ...
        'automatic_flags_diaph', false(size(diaph.peak_t(:))), ...
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

    if isfield(config, 'sigh')
        if isfield(config.sigh,'method'), method = config.sigh.method; end
        if isfield(config.sigh,'ratio_prctile'), ratio_prctile = config.sigh.ratio_prctile; end
        if isfield(config.sigh,'do_plot'), do_plot = config.sigh.do_plot; end
        if isfield(config.sigh,'manual_control'), manual_control = logical(config.sigh.manual_control); end
        if isfield(config.sigh,'manual_window_sec'), manual_window_sec = config.sigh.manual_window_sec; end
        if isfield(config.sigh,'min_abs_ratio'), min_abs_ratio = config.sigh.min_abs_ratio; end
        if isfield(config.sigh,'iqr_k'), iqr_k = config.sigh.iqr_k; end
        if isfield(config.sigh,'min_gap_sec'), min_gap_sec = config.sigh.min_gap_sec; end

        if isfield(config.sigh,'legacy_prev_win_sec'), legacy_prev_win_sec = config.sigh.legacy_prev_win_sec; end
        if isfield(config.sigh,'legacy_amp_ratio_thr'), legacy_amp_ratio_thr = config.sigh.legacy_amp_ratio_thr; end
        if isfield(config.sigh,'legacy_min_prev_breaths'), legacy_min_prev_breaths = config.sigh.legacy_min_prev_breaths; end
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
                [sigh_lungs, ~, ~, ...
                    diagnostics.lungs.decision_threshold] = sigh_flags_global_ratio_outlier( ...
                    lungs, ratio_prctile, ...
                    min_abs_ratio, iqr_k, min_gap_sec);
            end
            
            sigh_diaph = false(size(diaph.peak_t(:)));
            if diaph_valid
                [sigh_diaph, ~, ~, ...
                    diagnostics.diaph.decision_threshold] = sigh_flags_global_ratio_outlier( ...
                    diaph, ratio_prctile, ...
                    min_abs_ratio, iqr_k, min_gap_sec);
            end
    end
    automatic_sigh_lungs = sigh_lungs;
    automatic_sigh_diaph = sigh_diaph;
    automatic_events_L = sigh_flags_to_events(lungs.peak_t, automatic_sigh_lungs, N, fs, 'lungs');
    automatic_events_D = sigh_flags_to_events(diaph.peak_t, automatic_sigh_diaph, N, fs, 'diaph');
    automatic_events = merge_events({automatic_events_L, automatic_events_D});
    review_info.automatic_events = automatic_events;
    review_info.automatic_flags_lungs = automatic_sigh_lungs;
    review_info.automatic_flags_diaph = automatic_sigh_diaph;

    if manual_control && lungs_valid && diaph_valid
        [sigh_lungs, sigh_diaph, sigh_review_mask] = manual_edit_sigh_flags( ...
            data, resp_cycles.lungs, resp_cycles.diaph, sigh_lungs, sigh_diaph, ...
            config, manual_window_sec);
        review_info.reviewed = true;
        review_info.review_scope = 'explicitly_viewed_regions_sigh_breaths_both_belts';
        review_info.review_mask = sigh_review_mask;
    elseif manual_control
        warning('MAGMA:Sigh:ManualSkipped', ...
            'Manual sigh editing requires two valid respiratory belts and was skipped for this input configuration.');
    end

    events_L = sigh_flags_to_events(lungs.peak_t, sigh_lungs, N, fs, 'lungs');
    events_D = sigh_flags_to_events(diaph.peak_t, sigh_diaph, N, fs, 'diaph');
    events = merge_events({events_L, events_D});
    review_info.reviewed_events = events;
    review_info.reviewed_flags_lungs = sigh_lungs;
    review_info.reviewed_flags_diaph = sigh_diaph;
    if review_info.reviewed
        if event_sets_equal(automatic_events, events)
            review_info.status = 'reviewed_accepted';
        elseif ~isempty(automatic_events) && isempty(events)
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

        ax1 = subplot(4,1,1); hold on
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

        ax2 = subplot(4,1,2); hold on
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

        ax3 = subplot(4,1,3);
        plot_sigh_ratio_evidence( ...
            ax3, lungs, diagnostics.lungs, sigh_lungs, 'lungs');

        ax4 = subplot(4,1,4);
        plot_sigh_ratio_evidence( ...
            ax4, diaph, diagnostics.diaph, sigh_diaph, 'diaphragm');

        linkaxes([ax1 ax2], 'x');
        recording_end_t = (N - 1) / fs;
        if recording_end_t > 0
            xlim(ax1, [0 recording_end_t]);
        end
        align_axes_x_widths([ax1 ax2 ax3 ax4]);

        save_figure(config, 'sigh');
    end
end

function plot_sigh_ratio_evidence( ...
    ax, belt, belt_diagnostics, selected_mask, belt_name)
% PLOT_SIGH_RATIO_EVIDENCE Show global breath ratios and the final threshold.

    hold(ax, 'on');
    title(ax, sprintf('Sigh amplitude-ratio evidence (%s)', belt_name));
    xlabel(ax, 'Breath peak time (s)');
    ylabel(ax, 'Breath amplitude / global reference');
    grid(ax, 'on');

    peak_t = belt.peak_t(:);
    ratio = belt.amp_ratio_global(:);
    selected_mask = logical(selected_mask(:));
    n_breaths = min([numel(peak_t), numel(ratio), numel(selected_mask)]);
    peak_t = peak_t(1:n_breaths);
    ratio = ratio(1:n_breaths);
    selected_mask = selected_mask(1:n_breaths);
    valid = isfinite(peak_t) & isfinite(ratio) & ratio > 0;

    set_breath_time_xlim(ax, peak_t(isfinite(peak_t)));
    if ~belt_diagnostics.available || ~any(valid)
        ylim(ax, [0 1]);
        text(ax, 0.5, 0.5, 'No usable breath-ratio evidence', ...
            'Units', 'normalized', 'HorizontalAlignment', 'center');
        hold(ax, 'off');
        return;
    end

    h_ratios = plot(ax, peak_t(valid), ratio(valid), 'o', ...
        'LineStyle', 'none', 'Color', [0.35 0.35 0.35], ...
        'MarkerSize', 4, 'DisplayName', 'breath ratios');
    h_threshold = gobjects(0);
    if isscalar(belt_diagnostics.decision_threshold) && ...
            isfinite(belt_diagnostics.decision_threshold)
        h_threshold = yline(ax, belt_diagnostics.decision_threshold, 'k--', ...
            'LineWidth', 1.2, 'DisplayName', 'decision threshold');
    end
    sigh_mask = valid & selected_mask;
    h_sighs = plot(ax, peak_t(sigh_mask), ratio(sigh_mask), 'ro', ...
        'LineStyle', 'none', 'MarkerFaceColor', 'r', 'MarkerSize', 6, ...
        'DisplayName', 'sigh breaths');
    handles = h_ratios;
    labels = {'breath ratios'};
    if ~isempty(h_threshold) && isgraphics(h_threshold)
        handles(end + 1, 1) = h_threshold;
        labels{end + 1} = 'decision threshold';
    end
    handles(end + 1, 1) = h_sighs;
    labels{end + 1} = 'sigh breaths';
    add_axis_legend(ax, handles, labels);
    hold(ax, 'off');
end

function set_breath_time_xlim(ax, peak_t)
% SET_BREATH_TIME_XLIM Span available breath times without linking raw panels.

    if isempty(peak_t)
        return;
    end
    limits = [min(peak_t), max(peak_t)];
    if limits(1) == limits(2)
        padding = max(0.5, 0.05 * max(1, abs(limits(1))));
        limits = limits + [-padding padding];
    end
    xlim(ax, limits);
end

function diagnostics = empty_sigh_belt_diagnostics(belt)
% EMPTY_SIGH_BELT_DIAGNOSTICS Initialize breath-level sigh evidence for one belt.
% Fields are availability, reference quality, and the adaptive threshold.

    diagnostics = struct( ...
        'available', belt.global_amplitude_available, ...
        'reference_quality', belt.reference_quality, ...
        'decision_threshold', NaN);
end

function tf = event_sets_equal(a, b)
% EVENT_SETS_EQUAL Compare event type and sample bounds independent of ordering.

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
% SIGH_FLAGS_GLOBAL_RATIO_OUTLIER Flag globally normalized amplitude outliers.
% b supplies aligned peak_t, amp, amp_ratio_global, and global reference.
% ratio_thr is the maximum of the requested percentile, median+iqr_k*IQR,
% and min_abs_ratio. sigh_flags is breath-level and retains only the strongest
% candidate within min_gap_sec; local_ref repeats the global belt amplitude.

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
% SIGH_FLAGS_LEGACY_60S Compare each breath with the preceding amplitude median.
% b supplies peak_t (s) and amp; a breath is flagged when it is at least
% amp_ratio_thr times the median of min_prev_breaths in the prior window.

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
% SIGH_FLAGS_TO_EVENTS Convert selected breaths to midpoint-bounded events.
% peak_t is seconds and flags is an aligned breath-level mask. N/fs clamp
% canonical sample/time bounds; belt is appended to the sigh event type.

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
% ENFORCE_MIN_GAP_BY_STRENGTH Greedily retain strongest separated breath candidates.
% flags_in, peak_t (s), and strength are aligned breath vectors. Any weaker
% candidate within min_gap_sec of an already retained candidate is removed.

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
% ADD_AXIS_LEGEND Show entries only for valid graphics with plotted X data.

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
