function events = detect_slow_breathing(data, baseline, breaths_lungs, breaths_diaph, spo2_feat, config)
% detect_slow_breathing
% Label 3 – Slow Breathing (Bradypnea)
%
% Conditions:
%   - Mean RR <= 10 bpm sustained for >= 30 s.
%   - 60 s windows analyzed.
%   - Computed separately for lungs and diaphragm; positive if either is positive.
%
% Notes:
%   1) Optionally distinguish "slow+deep" vs "slow+shallow" using amplitude ratio.
%   2) Optionally mark "slow breathing with desaturation" if SpO2 drop >=3% overlaps
%      slow breathing (with optional delay buffer).

    events = empty_events();

    N = size(data,1);
    t_grid = (0:config.grid_step_sec:(N-1)/config.fs)';  % seconds

    if isempty(breaths_lungs) || isempty(breaths_diaph) || ...
       ~isfield(breaths_lungs, 'peak_t') || ~isfield(breaths_diaph, 'peak_t')
        return;
    end

    % ----------------------------
    % Config defaults
    % ----------------------------
    analysis_win_sec = 60;
    rr_thr_bpm       = 10;
    min_dur_sec      = 30;

    classify_depth   = true;      % slow+shallow vs slow+deep
    shallow_hi_ratio = 0.35;      % same as ShB upper bound (20–35%); here we use <=0.35 => "shallow"
    shallow_lo_ratio = 0.20;      % not required for slow+shallow, but kept for symmetry

    mark_desat       = true;
    desat_delay_sec  = 20;        % allow SpO2 lag by expanding desat events by +/- this many sec

    if isfield(config, 'SlB')
        if isfield(config.SlB, 'analysis_win_sec'), analysis_win_sec = config.SlB.analysis_win_sec; end
        if isfield(config.SlB, 'rr_thr_bpm'),       rr_thr_bpm       = config.SlB.rr_thr_bpm; end
        if isfield(config.SlB, 'min_dur_sec'),      min_dur_sec      = config.SlB.min_dur_sec; end

        if isfield(config.SlB, 'classify_depth'),   classify_depth   = config.SlB.classify_depth; end
        if isfield(config.SlB, 'shallow_hi_ratio'), shallow_hi_ratio = config.SlB.shallow_hi_ratio; end
        if isfield(config.SlB, 'shallow_lo_ratio'), shallow_lo_ratio = config.SlB.shallow_lo_ratio; end

        if isfield(config.SlB, 'mark_desat'),       mark_desat       = config.SlB.mark_desat; end
        if isfield(config.SlB, 'desat_delay_sec'),  desat_delay_sec  = config.SlB.desat_delay_sec; end
    end

    % ----------------------------
    % Slow RR condition on grid (lungs/diap)
    % ----------------------------
    slow_lungs = rr_leq_condition_on_grid_from_peaks( ...
        breaths_lungs.peak_t, t_grid, analysis_win_sec, rr_thr_bpm);

    slow_diaph = rr_leq_condition_on_grid_from_peaks( ...
        breaths_diaph.peak_t, t_grid, analysis_win_sec, rr_thr_bpm);

    slow_any = slow_lungs | slow_diaph;

    % Sustain >= 30 s -> events
    ev_grid = runs_to_events(slow_any, 1/config.grid_step_sec, min_dur_sec, 'slow_breathing');
    events  = grid_events_to_sample_events(ev_grid, config.fs, N);

    % ----------------------------
    % Optional: classify slow+shallow vs slow+deep using amplitude ratio
    % ----------------------------
    if classify_depth && isfinite(baseline.lungs_amp_ref) && baseline.lungs_amp_ref > 0 && ...
                        isfinite(baseline.diap_amp_ref)  && baseline.diap_amp_ref  > 0

        % Build an amplitude "shallow-ish" mask on the same grid:
        % shallow-ish if median amp ratio in last 60s <= 0.35 (and >=0.20 if you want)
        amp_shallow = shallow_amp_condition_on_grid( ...
            breaths_lungs, breaths_diaph, t_grid, analysis_win_sec, ...
            baseline.lungs_amp_ref, baseline.diap_amp_ref, shallow_lo_ratio, shallow_hi_ratio);

        % Rewrite event types based on majority overlap with amp_shallow
        for e = 1:numel(events)
            g0 = max(1, round(events(e).start_t / config.grid_step_sec) + 1);
            g1 = min(numel(t_grid), round(events(e).end_t   / config.grid_step_sec) + 1);
            if g0 <= g1
                frac_shallow = mean(amp_shallow(g0:g1));
                if frac_shallow >= 0.5
                    events(e).type = 'slow_breathing_shallow';
                else
                    events(e).type = 'slow_breathing_deep';
                end
            end
        end
    end

    % ----------------------------
    % Optional: mark slow breathing WITH desaturation
    % ----------------------------
    if mark_desat && exist('spo2_feat','var') && ~isempty(spo2_feat) && isfield(spo2_feat,'desat_events')
    
        desat_events = spo2_feat.desat_events;
    
        % Expand desat events to allow SpO2 delay
        desat_events = expand_events_time(desat_events, desat_delay_sec, (N-1)/config.fs);
    
        % If a slow event overlaps any desat event -> relabel with "_desat"
        for e = 1:numel(events)
            if events_overlap_any(events(e), desat_events)
                events(e).type = [events(e).type '_desat'];
            end
        end
    end

    % ----------------------------
    % Optional plot (raw + shaded slow mask)
    % ----------------------------
    if isfield(config, 'SlB') && isfield(config.SlB, 'do_plot') && config.SlB.do_plot
        idx_lungs = find(strcmp(config.data_columns, 'Resp-Lungs'), 1);
        idx_diap  = find(strcmp(config.data_columns, 'Resp-Diaphragm'), 1);
        t_raw = (0:N-1)/config.fs;

        figure('Units','pixels','Position',[100 100 1200 800], 'Visible', config.make_figs_visible); 
        sgtitle(['SLOW BREATHING' newline 'Subject: ' num2str(config.subject) ' | Condition: ' num2str(config.condition)])

        subplot(3,1,1); hold on
        plot(t_raw, data(:, idx_lungs), 'k')
        shade_mask_on_axis(t_grid, slow_lungs)
        title('Slow breathing (lungs) over raw signal')
        xlabel('Time (s)'); ylabel('Resp-Lungs'); grid on
        hold off

        subplot(3,1,2); hold on
        plot(t_raw, data(:, idx_diap), 'k')
        shade_mask_on_axis(t_grid, slow_diaph)
        title('Slow breathing (diaphragm) over raw signal')
        xlabel('Time (s)'); ylabel('Resp-Diaphragm'); grid on
        hold off

        subplot(3,1,3); hold on
        plot(t_raw, data(:, idx_lungs), 'k')
        shade_mask_on_axis(t_grid, slow_any)
        title('Slow breathing (either belt)')
        xlabel('Time (s)'); ylabel('Resp-Lungs'); grid on
        hold off

        ax = findall(gcf,'Type','axes');
        ax = ax(arrayfun(@(a) ~strcmp(a.Tag,'legend'), ax));
        linkaxes(ax,'x');          % tie x-zoom/pan
        xlim(ax(1), [0 t_grid(end)]);     % or whatever common range you want
   
        save_figure(config, 'slow_breathing');
    end
end

% =========================================================
% Helpers
% =========================================================

function cond = rr_leq_condition_on_grid_from_peaks(peak_t, t_grid, win_sec, rr_thr_bpm)
% At each grid time t:
%   - take peaks in [t-win_sec, t]
%   - compute mean RR = 60 / mean(IBI)
%   - cond true if RR <= rr_thr_bpm
    cond = false(size(t_grid));
    peak_t = peak_t(:);

    for i = 1:numel(t_grid)
        t = t_grid(i);
        lb = t - win_sec;
        if lb < 0
            continue;  % not enough history for a full 60 s window yet
        end
        idx = find(peak_t >= lb & peak_t <= t);
        if numel(idx) < 3
            continue; % need at least 2 IBIs
        end

        ibi = diff(peak_t(idx)); % seconds
        rr_mean = 60 / mean(ibi, 'omitnan');

        if isfinite(rr_mean) && rr_mean <= rr_thr_bpm
            cond(i) = true;
        end
    end
end

function ev = expand_events_time(ev, pad_sec, t_max)
% Expand each event by +/- pad_sec seconds (clipped to [0, t_max]).
    for i = 1:numel(ev)
        ev(i).start_t = max(0, ev(i).start_t - pad_sec);
        ev(i).end_t   = min(t_max, ev(i).end_t + pad_sec);
    end
end

function tf = events_overlap_any(e, ev_list)
    tf = false;
    for k = 1:numel(ev_list)
        if ~(e.end_t < ev_list(k).start_t || e.start_t > ev_list(k).end_t)
            tf = true;
            return;
        end
    end
end
