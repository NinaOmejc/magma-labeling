function events_Sig = detect_sigh(data, breaths_lungs, breaths_diaph, config)
% detect_sigh
% Label 8 – Sigh
%
% Definition:
%   Single breath with clearly larger amplitude compared to normal cycles.
%
% Conditions:
%   Cycle amplitude >= 1.5 * median amplitude from previous 60 s.
%   Computed per-breath using breath amplitudes from resp extraction.
%   If either lungs OR diaphragm meets criterion -> sigh.
%
% Additionally (summary metric):
%   Frequency >= 7–10 sighs per 30 minutes (does not change per-breath detection here).
%
% Usage:
%   events_Sig = detect_sigh(data, baseline, breaths_lungs, breaths_diaph, config);

    events_Sig = empty_events();

    N = size(data,1);
    fs = config.fs;
    t_grid = (0:config.grid_step_sec:(N-1)/config.fs)';  % common grid (seconds)

    if isempty(breaths_lungs) || isempty(breaths_diaph) || ...
       ~isfield(breaths_lungs,'peak_t') || ~isfield(breaths_lungs,'amp') || ...
       ~isfield(breaths_diaph,'peak_t') || ~isfield(breaths_diaph,'amp')
        return;
    end

    % ----------------------------
    % Config defaults
    % ----------------------------
    prev_win_sec        = 60;     % previous window length for "normal cycles"
    amp_ratio_thr       = 1.5;    % sigh threshold multiplier
    min_prev_breaths    = 3;      % need at least this many breaths in prev window
    use_either_belt     = true;   % OR across belts (recommended)
    do_plot             = false;

    % Optional frequency summary
    freq_win_sec        = 1800;   % 30 minutes
    freq_thr_per_30min  = 7;      % lower end of 7–10 / 30 min

    if isfield(config,'Sig')
        if isfield(config.Sig,'prev_win_sec'),       prev_win_sec = config.Sig.prev_win_sec; end
        if isfield(config.Sig,'amp_ratio_thr'),      amp_ratio_thr = config.Sig.amp_ratio_thr; end
        if isfield(config.Sig,'min_prev_breaths'),   min_prev_breaths = config.Sig.min_prev_breaths; end
        if isfield(config.Sig,'use_either_belt'),    use_either_belt = config.Sig.use_either_belt; end
        if isfield(config.Sig,'do_plot'),            do_plot = config.Sig.do_plot; end

        if isfield(config.Sig,'freq_win_sec'),       freq_win_sec = config.Sig.freq_win_sec; end
        if isfield(config.Sig,'freq_thr_per_30min'), freq_thr_per_30min = config.Sig.freq_thr_per_30min; end
    end

    % ----------------------------
    % Build sigh flags per-breath for each belt
    % ----------------------------
    sigh_lungs = sigh_flags_from_breath_series(breaths_lungs, prev_win_sec, amp_ratio_thr, min_prev_breaths);
    sigh_diaph = sigh_flags_from_breath_series(breaths_diaph, prev_win_sec, amp_ratio_thr, min_prev_breaths);

    % Build sigh events from each belt independently
    events_L = sigh_flags_to_events(breaths_lungs.peak_t, sigh_lungs, N, fs);
    events_D = sigh_flags_to_events(breaths_diaph.peak_t, sigh_diaph, N, fs);
    
    if use_either_belt
        events_Sig = merge_events([events_L; events_D], 0.5);  % merge overlaps; 0.5s tolerance
    else
        % "AND across belts": keep only events that overlap between belts
        events_Sig = intersect_events(events_L, events_D);
    end

    % ----------------------------
    % Optional: frequency summary per 30 min (does not affect event list)
    % ----------------------------
    if ~isempty(events_Sig)
        sigh_times = arrayfun(@(e) 0.5*(e.start_t + e.end_t), events_Sig);

        % Sliding count in [t - freq_win_sec, t]
        t_end = (N-1)/fs;
        t_grid_freq = (0:60:t_end)';  % every 60s for summary
        counts = zeros(size(t_grid_freq));

        for k = 1:numel(t_grid_freq)
            t = t_grid_freq(k);
            counts(k) = sum(sigh_times >= (t - freq_win_sec) & sigh_times <= t);
        end

        if any(counts >= freq_thr_per_30min)
            % You can turn this into a separate "sigh_cluster" label if you want later.
            % For now just display a message when plotting or debugging.
            if do_plot
                fprintf('[Sigh] High sigh frequency detected: max %d sighs / 30 min\n', max(counts));
            end
        end
    end

    % ----------------------------
    % Optional plot
    % ----------------------------
    if do_plot
        idx_lungs = find(strcmp(config.data_columns, 'Resp-Lungs'), 1);
        idx_diap  = find(strcmp(config.data_columns, 'Resp-Diaphragm'), 1);

        t_raw = (0:N-1)/fs;

        figure('Units','pixels','Position',[100 100 1200 800], 'Visible', config.make_figs_visible); 
        sgtitle(['SIGH | Subject: ' num2str(config.subject) ' | Condition: ' num2str(config.condition)])

        subplot(2,1,1); hold on
        if ~isempty(idx_lungs)
            plot(t_raw, data(:,idx_lungs), 'k')
        end
        plot(breaths_lungs.peak_t, breaths_lungs.amp, 'b')  % breath amp trace (lungs)
        plot(breaths_lungs.peak_t(sigh_lungs), breaths_lungs.amp(sigh_lungs), 'ro', 'MarkerFaceColor','r')
        title('Sigh detection (lungs): red dots = sigh breaths')
        xlabel('Time (s)'); ylabel('Resp-Lungs / amp')
        grid on
        hold off

        subplot(2,1,2); hold on
        if ~isempty(idx_diap)
            plot(t_raw, data(:,idx_diap), 'k')
        end

        % Diaphragm breath times may differ slightly; plot on its own axis
        plot(breaths_diaph.peak_t, breaths_diaph.amp, 'b')
        plot(breaths_diaph.peak_t(sigh_diaph), breaths_diaph.amp(sigh_diaph), 'ro', 'MarkerFaceColor','r')
        title('Sigh detection (diaphragm): red dots = sigh breaths')
        xlabel('Time (s)'); ylabel('Resp-Diaphragm / amp')
        grid on
        hold off

        ax = findall(gcf,'Type','axes');
        ax = ax(arrayfun(@(a) ~strcmp(a.Tag,'legend'), ax));
        linkaxes(ax,'x');          % tie x-zoom/pan
        xlim(ax(1), [0 t_grid(end)]);     % or whatever common range you want
   
        save_figure(config, 'sigh');
    end
end

% ===================== helpers =====================

function sigh_flags = sigh_flags_from_breath_series(b, prev_win_sec, amp_ratio_thr, min_prev_breaths)
% For each breath i, compute median amplitude over previous prev_win_sec seconds and compare:
%   sigh if b.amp(i) >= amp_ratio_thr * median(prev_amps)

    peak_t = b.peak_t(:);
    amp    = b.amp(:);

    L = min(numel(peak_t), numel(amp));
    peak_t = peak_t(1:L);
    amp    = amp(1:L);

    sigh_flags = false(L,1);

    for i = 1:L
        t = peak_t(i);
        lb = t - prev_win_sec;
        if lb < 0
            continue;
        end
        prev_idx = find(peak_t < t & peak_t >= lb);
        if numel(prev_idx) < min_prev_breaths
            continue;
        end

        med_prev = median(amp(prev_idx), 'omitnan');
        if ~isfinite(med_prev) || med_prev <= 0 || ~isfinite(amp(i))
            continue;
        end

        if amp(i) >= amp_ratio_thr * med_prev
            sigh_flags(i) = true;
        end
    end
end


function events = sigh_flags_to_events(peak_t, flags, N, fs)
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

        events(end+1,1) = struct('type','sigh','start_idx',s,'end_idx',e,'start_t',(s-1)/fs,'end_t',(e-1)/fs);
    end
end

function ev = merge_events(ev, tol_sec)
% Merge events that overlap or are within tol_sec of each other.
    if isempty(ev), return; end
    [~,ord] = sort([ev.start_t]);
    ev = ev(ord);

    out = ev(1);
    for i = 2:numel(ev)
        if ev(i).start_t <= out(end).end_t + tol_sec
            % merge
            out(end).end_t   = max(out(end).end_t, ev(i).end_t);
            out(end).end_idx = max(out(end).end_idx, ev(i).end_idx);
        else
            out(end+1,1) = ev(i); %#ok<AGROW>
        end
    end
    ev = out;
end

function out = intersect_events(a, b)
% Keep events in a that overlap any event in b (simple AND definition).
    out = empty_events();
    for i = 1:numel(a)
        for k = 1:numel(b)
            if ~(a(i).end_t < b(k).start_t || a(i).start_t > b(k).end_t)
                out(end+1,1) = a(i); %#ok<AGROW>
                break;
            end
        end
    end
end