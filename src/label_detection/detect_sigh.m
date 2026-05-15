function events = detect_sigh(data, baseline, breaths_lungs, breaths_diaph, spo2_feat, config)
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
    fs = config.fs;
    t_grid = (0:config.grid_step_sec:(N-1)/config.fs)';

    if isempty(breaths_lungs) || isempty(breaths_diaph) || ...
       ~isfield(breaths_lungs,'peak_t') || ~isfield(breaths_lungs,'amp') || ...
       ~isfield(breaths_diaph,'peak_t') || ~isfield(breaths_diaph,'amp')
        return;
    end

    method = 'global_ratio_outlier';
    ratio_prctile = 98;
    do_plot = false;

    % legacy
    legacy_prev_win_sec = 60;
    legacy_amp_ratio_thr = 1.5;
    legacy_min_prev_breaths = 3;

    if isfield(config,'Sig')
        if isfield(config.Sig,'method'), method = config.Sig.method; end
        if isfield(config.Sig,'ratio_prctile'), ratio_prctile = config.Sig.ratio_prctile; end
        if isfield(config.Sig,'do_plot'), do_plot = config.Sig.do_plot; end

        if isfield(config.Sig,'legacy_prev_win_sec'), legacy_prev_win_sec = config.Sig.legacy_prev_win_sec; end
        if isfield(config.Sig,'legacy_amp_ratio_thr'), legacy_amp_ratio_thr = config.Sig.legacy_amp_ratio_thr; end
        if isfield(config.Sig,'legacy_min_prev_breaths'), legacy_min_prev_breaths = config.Sig.legacy_min_prev_breaths; end
    end

    switch lower(method)
        case 'legacy_60s'
            sigh_lungs = sigh_flags_legacy_60s(breaths_lungs, legacy_prev_win_sec, legacy_amp_ratio_thr, legacy_min_prev_breaths);
            sigh_diaph = sigh_flags_legacy_60s(breaths_diaph, legacy_prev_win_sec, legacy_amp_ratio_thr, legacy_min_prev_breaths);
        otherwise
            sigh_lungs = sigh_flags_global_ratio_outlier( ...
                breaths_lungs, baseline, config, 'lungs_amp_ref', ratio_prctile);
            sigh_diaph = sigh_flags_global_ratio_outlier( ...
                breaths_diaph, baseline, config, 'diaph_amp_ref', ratio_prctile);
    end

    events_L = sigh_flags_to_events(breaths_lungs.peak_t, sigh_lungs, N, fs, 'lungs');
    events_D = sigh_flags_to_events(breaths_diaph.peak_t, sigh_diaph, N, fs, 'diaph');
    events = merge_events({events_L, events_D});

    desat_mask = get_desaturation_mask(spo2_feat.desat_events, t_grid);

    if do_plot
        idx_lungs = find(strcmp(config.data_columns, 'Resp-Lungs'), 1);
        idx_diaph  = find(strcmp(config.data_columns, 'Resp-Diaphragm'), 1);

        t_raw = (0:N-1)/fs;

        figure('Units','pixels','Position',[100 100 1500 800], 'Visible', config.make_figs_visible);
        sgtitle(['SIGH | Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)])

        subplot(3,1,1); hold on
        if ~isempty(idx_lungs), plot(t_raw, data(:,idx_lungs), 'k'); end
        % plot(breaths_lungs.peak_t, breaths_lungs.amp, 'b')
        plot(breaths_lungs.peak_t(sigh_lungs), breaths_lungs.amp(sigh_lungs), 'ro', 'MarkerFaceColor','r')
        title('Sigh detection (lungs): red dots = sigh breaths')
        xlabel('Time (s)'); ylabel('Resp-Lungs / amp'); grid on; hold off

        subplot(3,1,2); hold on
        if ~isempty(idx_diaph), plot(t_raw, data(:,idx_diaph), 'k'); end
        % plot(breaths_diaph.peak_t, breaths_diaph.amp, 'b')
        plot(breaths_diaph.peak_t(sigh_diaph), breaths_diaph.amp(sigh_diaph), 'ro', 'MarkerFaceColor','r')
        title('Sigh detection (diaphragm): red dots = sigh breaths')
        xlabel('Time (s)'); ylabel('Resp-Diaphragm / amp'); grid on; hold off

        ax = findall(gcf,'Type','axes');
        ax = ax(arrayfun(@(a) ~strcmp(a.Tag,'legend'), ax));
        linkaxes(ax,'x');
        xlim(ax(1), [0 t_grid(end)]);

        % ----------------------
        % Subplot 3: SpO2 + no_desat mask
        % ----------------------
        subplot(3,1,3)
        hold on
    
        % SpO2 time series (sampled signal)
        spo2 = spo2_feat.spo2(:);
        t_spo2 = spo2_feat.t_spo2(:);
    
        plot(t_spo2, spo2, 'k')
        yline(90, 'r--')
        ylim([89 100])
        xlim([0 1800])
    
        % baseline - drop threshold (informational)
        drop_thr = config.spo2.drop_thr;
        if isfield(baseline,'SpO2_median') && isfinite(baseline.SpO2_median)
            yline(baseline.SpO2_median - drop_thr, 'g--')
        end
    
        % Plot no_desat as a binary trace near bottom (scaled)
        spo2_min = min(spo2, [], 'omitnan');
        spo2_max = max(spo2, [], 'omitnan');
        y0 = spo2_min + 0.05*(spo2_max - spo2_min);
        y1 = spo2_min + 0.20*(spo2_max - spo2_min);
        % plot(t_grid, y0 + (y1-y0)*double(no_desat), 'b')
    
        % Optional: show desaturation event spans as shaded regions
        if isfield(spo2_feat,'desat_events') && ~isempty(spo2_feat.desat_events)
            shade_events_on_axis(spo2_feat.desat_events);
            legend('SpO₂','90%','Baseline-drop','desat events', 'Location','eastoutside')
        else
            legend('SpO₂','90%','Baseline-drop', 'Location','northeast')
        end
    
        title('SpO₂')
        xlabel('Time (s)')
        ylabel('SpO₂ (%)')
        grid on
        hold off

        save_figure(config, 'sigh', true);
    end
end

function sigh_flags = sigh_flags_global_ratio_outlier(b, baseline, config, rolling_field, ratio_prctile)
    peak_t = b.peak_t(:);
    amp = b.amp(:);

    L = min(numel(peak_t), numel(amp));
    peak_t = peak_t(1:L);
    amp = amp(1:L);
    sigh_flags = false(L,1);

    if L < 10
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

    ratio_thr = prctile(ratio(valid), ratio_prctile);
    sigh_flags(valid) = ratio(valid) >= ratio_thr;
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
        
        events(end+1,1) = struct( ...
            'type', ['sigh_' belt], ...
            'start_idx', s, ...
            'end_idx', e, ...
            'start_t', start_t, ...
            'end_t', end_t, ...
            'duration', end_t - start_t );

    end
end
