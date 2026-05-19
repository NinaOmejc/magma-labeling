function events = detect_sigh(data, baseline, resp_feat, spo2_feat, config)
% detect_sigh
% Label 8 – Sigh
%
% Default method: global nonparametric outlier detection on normalized breath amplitude.
% ratio = breath_amp / baseline_ref_at_breath
% sigh if ratio >= prctile(ratio_valid, ratio_prctile)
%
% Baseline source:
%   - rolling baseline, when available and enabled
%   - otherwise stationary baseline (median breath amplitude)
%
% Legacy method (optional): previous-window thresholding.

    events = empty_events();

    N = size(data,1);
    fs = config.new_fs;
    t_grid = (0:config.grid_step_sec:(N-1)/config.new_fs)';

    lungs_broken = isfield(config,'problems') && isfield(config.problems,'subjects_with_broken_lung_belt') && ...
        any(config.subject == config.problems.subjects_with_broken_lung_belt);
    lungs_valid = is_valid_breath_signal(resp_feat.lungs, true) && ~lungs_broken;
    diaph_valid = is_valid_breath_signal(resp_feat.diaph, true);

    if ~lungs_valid && ~diaph_valid
        return;
    end
    
    method = 'global_ratio_outlier';
    ratio_prctile = 98;
    
    % New robust sigh criteria
    min_abs_ratio = 1.8;      % sigh must be at least 1.8x local baseline
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
            sigh_lungs = false(size(resp_feat.lungs.peak_t(:)));
            if lungs_valid
                sigh_lungs = sigh_flags_legacy_60s(resp_feat.lungs, legacy_prev_win_sec, legacy_amp_ratio_thr, legacy_min_prev_breaths);
            end
            sigh_diaph = false(size(resp_feat.diaph.peak_t(:)));
            if diaph_valid
                sigh_diaph = sigh_flags_legacy_60s(resp_feat.diaph, legacy_prev_win_sec, legacy_amp_ratio_thr, legacy_min_prev_breaths);
            end
        otherwise
            sigh_lungs = false(size(resp_feat.lungs.peak_t(:)));
            if lungs_valid
                sigh_lungs = sigh_flags_global_ratio_outlier( ...
                    resp_feat.lungs, baseline, config, 'lungs_amp_ref', ratio_prctile, ...
                    min_abs_ratio, iqr_k, min_gap_sec);
            end
            
            sigh_diaph = false(size(resp_feat.diaph.peak_t(:)));
            if diaph_valid
                sigh_diaph = sigh_flags_global_ratio_outlier( ...
                    resp_feat.diaph, baseline, config, 'diaph_amp_ref', ratio_prctile, ...
                    min_abs_ratio, iqr_k, min_gap_sec);
            end
    end

    if manual_control
        [sigh_lungs, sigh_diaph] = manual_edit_sigh_flags(data, resp_feat.lungs, resp_feat.diaph, sigh_lungs, sigh_diaph, baseline, spo2_feat, config, manual_window_sec);
    end

    events_L = sigh_flags_to_events(resp_feat.lungs.peak_t, sigh_lungs, N, fs, 'lungs');
    events_D = sigh_flags_to_events(resp_feat.diaph.peak_t, sigh_diaph, N, fs, 'diaph');
    events = merge_events({events_L, events_D});

    if do_plot
        idx_lungs = find(strcmp(config.data_columns, 'Resp-Lungs'), 1);
        idx_diaph  = find(strcmp(config.data_columns, 'Resp-Diaphragm'), 1);

        t_raw = (0:N-1)/fs;

        figure('Units','pixels','Position', near_fullscreen_figure_position(), 'Visible', config.make_figs_visible);
        sgtitle(['SIGH | Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)])

        ax1 = subplot(3,1,1); hold on
        h_lungs_trace = gobjects(0);
        if ~isempty(idx_lungs), h_lungs_trace = plot(t_raw, data(:,idx_lungs), 'k', 'DisplayName', 'Resp-Lungs'); end
        if ~isempty(idx_lungs)
            y_lungs_mark = interp1(t_raw, data(:,idx_lungs), resp_feat.lungs.peak_t(sigh_lungs), 'linear', 'extrap');
        else
            y_lungs_mark = nan(sum(sigh_lungs),1);
        end
        h_lungs_sigh = plot(resp_feat.lungs.peak_t(sigh_lungs), y_lungs_mark, 'ro', 'MarkerFaceColor','r', ...
            'DisplayName', 'Sigh breaths');
        title('Sigh detection (lungs): red dots = sigh breaths')
        add_axis_legend(gca, [h_lungs_trace; h_lungs_sigh], {'Resp-Lungs', 'Sigh breaths'});
        xlabel('Time (s)'); ylabel('Resp-Lungs'); grid on; hold off

        ax2 = subplot(3,1,2); hold on
        h_diaph_trace = gobjects(0);
        if ~isempty(idx_diaph), h_diaph_trace = plot(t_raw, data(:,idx_diaph), 'k', 'DisplayName', 'Resp-Diaphragm'); end
        if ~isempty(idx_diaph)
            y_diaph_mark = interp1(t_raw, data(:,idx_diaph), resp_feat.diaph.peak_t(sigh_diaph), 'linear', 'extrap');
        else
            y_diaph_mark = nan(sum(sigh_diaph),1);
        end
        h_diaph_sigh = plot(resp_feat.diaph.peak_t(sigh_diaph), y_diaph_mark, 'ro', 'MarkerFaceColor','r', ...
            'DisplayName', 'Sigh breaths');
        title('Sigh detection (diaphragm): red dots = sigh breaths')
        add_axis_legend(gca, [h_diaph_trace; h_diaph_sigh], {'Resp-Diaphragm', 'Sigh breaths'});
        xlabel('Time (s)'); ylabel('Resp-Diaphragm'); grid on; hold off

        % ----------------------
        % Subplot 3: SpO2 + desaturation thresholds
        % ----------------------
        ax3 = subplot(3,1,3);
        plot_spo2_diagnostic_panel(ax3, data, baseline, spo2_feat, config, 'SpO2 with desaturation thresholds');
    
        linkaxes([ax1 ax2 ax3], 'x');
        xlim(ax1, [0 t_grid(end)]);

        title('SpO₂')
        xlabel('Time (s)')
        ylabel('SpO₂ (%)')
        grid on
        hold off
        title(ax3, 'SpO2 with desaturation thresholds')

        save_figure(config, 'sigh');
    end
end

function [sigh_flags, local_ref, ratio, ratio_thr] = sigh_flags_global_ratio_outlier( ...
    b, baseline, config, rolling_field, ratio_prctile, min_abs_ratio, iqr_k, min_gap_sec)
    
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

    local_ref = nan(L,1);
    use_rolling = isfield(config,'rolling_baseline') && isfield(config.rolling_baseline,'enabled') && config.rolling_baseline.enabled && ...
        isfield(baseline,'rolling') && isfield(baseline.rolling,'t_grid') && isfield(baseline.rolling,rolling_field);

    if use_rolling
        local_ref = interp1(baseline.rolling.t_grid, baseline.rolling.(rolling_field), peak_t, 'linear', 'extrap');
    elseif isfield(b,'amp_ref') && isfinite(b.amp_ref) && b.amp_ref > 0
        local_ref(:) = b.amp_ref;
    else
        ref = median(amp, 'omitnan');
        local_ref(:) = ref;
    end

    ratio = amp ./ local_ref;
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
            end_t = min((N-1)/fs, t0 + 0.5*dt);
        elseif i < L
            end_t = 0.5*(peak_t(i) + peak_t(i+1));
        else
            end_t = min((N-1)/fs, t0 + 0.5); % fallback
        end

        s = max(1, min(N, round(start_t*fs) + 1));
        e = max(1, min(N, round(end_t*fs)   + 1));

        start_t = (s-1)/fs;
        end_t   = (e-1)/fs;

        out = out + 1;
        events(out) = struct( ...
            'type', ['sigh_' belt], ...
            'start_idx', s, ...
            'end_idx', e, ...
            'start_t', start_t, ...
            'end_t', end_t, ...
            'duration', end_t - start_t );

    end

    events = events(1:out);
end

function flags_out = enforce_min_gap_by_strength(flags_in, peak_t, strength, min_gap_sec)
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
