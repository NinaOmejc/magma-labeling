function events = detect_rapid_breathing(data, baseline, breaths_lungs, breaths_diaph, spo2_feat, config)
% detect_rapid_breathing
% Label 4 – Rapid Breathing (Tachypnea)
%
% Criteria:
%   - Mean RR >= 20 breaths/min sustained for >= 30 s.
%   - 60-second windows analyzed.
%   - Computed separately for lungs and diaphragm; positive if either is positive.
%
% Notes:
%   1) Distinguish "fast+deep" vs "fast+shallow" using amplitude ratio (as in ShB).
%   2) If SpO2 drop >=3% accompanies rapid breathing -> append "_desat"
%      (optional SpO2 delay handled via expanding desat events).

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
    rr_thr_bpm       = 20;
    min_dur_sec      = 30;

    classify_depth   = true;     % fast+shallow vs fast+deep
    shallow_lo_ratio = 0.20;
    shallow_hi_ratio = 0.35;

    mark_desat      = true;
    desat_delay_sec = 20;        % allow SpO2 lag by expanding desat events by +/- this many sec

    if isfield(config, 'RaB')
        if isfield(config.RaB, 'analysis_win_sec'), analysis_win_sec = config.RaB.analysis_win_sec; end
        if isfield(config.RaB, 'rr_thr_bpm'),       rr_thr_bpm       = config.RaB.rr_thr_bpm; end
        if isfield(config.RaB, 'min_dur_sec'),      min_dur_sec      = config.RaB.min_dur_sec; end

        if isfield(config.RaB, 'classify_depth'),   classify_depth   = config.RaB.classify_depth; end
        if isfield(config.RaB, 'shallow_lo_ratio'), shallow_lo_ratio = config.RaB.shallow_lo_ratio; end
        if isfield(config.RaB, 'shallow_hi_ratio'), shallow_hi_ratio = config.RaB.shallow_hi_ratio; end

        if isfield(config.RaB, 'mark_desat'),       mark_desat       = config.RaB.mark_desat; end
        if isfield(config.RaB, 'desat_delay_sec'),  desat_delay_sec  = config.RaB.desat_delay_sec; end
    end

    % ----------------------------
    % Rapid RR condition on grid (lungs/diap)
    % ----------------------------
    rapid_lungs = rr_geq_condition_on_grid_from_peaks( ...
        breaths_lungs.peak_t, t_grid, analysis_win_sec, rr_thr_bpm);

    rapid_diaph = rr_geq_condition_on_grid_from_peaks( ...
        breaths_diaph.peak_t, t_grid, analysis_win_sec, rr_thr_bpm);

    rapid_any = rapid_lungs | rapid_diaph;

    % Sustain >= 30 s -> events
    ev_grid = runs_to_events(rapid_any, 1/config.grid_step_sec, min_dur_sec, 'rapid_breathing');
    events  = grid_events_to_sample_events(ev_grid, config.fs, N);

    % ----------------------------
    % Optional: classify fast+shallow vs fast+deep using amplitude ratio
    % ----------------------------
    if classify_depth

        ref_lungs = get_resp_ref_on_grid(baseline, 'lungs', t_grid);
        ref_diap = get_resp_ref_on_grid(baseline, 'diap', t_grid);

        amp_shallow = shallow_amp_condition_on_grid( ...
            breaths_lungs, breaths_diaph, t_grid, analysis_win_sec, ...
            ref_lungs, ref_diap, shallow_lo_ratio, shallow_hi_ratio);

        for e = 1:numel(events)
            g0 = max(1, round(events(e).start_t / config.grid_step_sec) + 1);
            g1 = min(numel(t_grid), round(events(e).end_t   / config.grid_step_sec) + 1);
            if g0 <= g1
                frac_shallow = mean(amp_shallow(g0:g1));
                if frac_shallow >= 0.5
                    events(e).type = 'rapid_breathing_shallow';
                else
                    events(e).type = 'rapid_breathing_deep';
                end
            end
        end
    end

    % ----------------------------
    % Optional: mark rapid breathing WITH desaturation
    % ----------------------------
    if mark_desat && exist('spo2_feat','var') && ~isempty(spo2_feat) && isfield(spo2_feat,'desat_events')

        desat_events = spo2_feat.desat_events;
        desat_events = expand_events_time(desat_events, desat_delay_sec, (N-1)/config.fs);

        for e = 1:numel(events)
            if events_overlap_any(events(e), desat_events)
                events(e).type = [events(e).type '_desat'];
            end
        end
    end

    % ----------------------------
    % Optional debug plot (raw + shaded rapid mask)
    % ----------------------------
    if isfield(config, 'RaB') && isfield(config.RaB, 'do_plot') && config.RaB.do_plot
        idx_lungs = find(strcmp(config.data_columns, 'Resp-Lungs'), 1);
        idx_diap  = find(strcmp(config.data_columns, 'Resp-Diaphragm'), 1);
        t_raw = (0:N-1)/config.fs;

        figure('Units','pixels','Position',[100 100 1200 800], 'Visible', config.make_figs_visible); 
        sgtitle(['RAPID BREATHING' newline 'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)])

        subplot(2,1,1); hold on
        plot(t_raw, data(:, idx_lungs), 'k')
        shade_mask_on_axis(t_grid, rapid_lungs)
        title('Rapid breathing (lungs) over raw signal')
        xlabel('Time (s)'); ylabel('Resp-Lungs'); grid on
        hold off

        subplot(2,1,2); hold on
        plot(t_raw, data(:, idx_diap), 'k')
        shade_mask_on_axis(t_grid, rapid_diaph)
        title('Rapid breathing (diaphragm) over raw signal')
        xlabel('Time (s)'); ylabel('Resp-Diaphragm'); grid on
        hold off

        ax = findall(gcf,'Type','axes');
        ax = ax(arrayfun(@(a) ~strcmp(a.Tag,'legend'), ax));
        linkaxes(ax,'x');          % tie x-zoom/pan
        xlim(ax(1), [0 t_grid(end)]);     % or whatever common range you want
   
        save_figure(config, 'rapid_breathing');
    end
end

% =========================================================
% Helpers
% =========================================================
function cond = rr_geq_condition_on_grid_from_peaks(peak_t, t_grid, win_sec, rr_thr_bpm)
%RR_GEQ_CONDITION_ON_GRID_FROM_PEAKS
% Rapid-breathing / tachypnea condition.
%
% At each grid time t:
%   - take respiratory peaks in previous window: [t-win_sec, t)
%   - estimate mean RR by breath count:
%         rr_mean = n_breaths / win_sec * 60
%   - cond(i) = true if rr_mean >= rr_thr_bpm
%
% Example for tachypnea:
%   cond = rr_geq_condition_on_grid_from_peaks(peak_t, t_grid, 60, 20);

    cond = false(size(t_grid));

    peak_t = peak_t(:);
    peak_t = peak_t(isfinite(peak_t));

    for i = 1:numel(t_grid)
        t = t_grid(i);
        lb = t - win_sec;

        % Need full backward-looking window
        if lb < 0
            continue;
        end

        % Count breaths in [t-win_sec, t)
        n_breaths = sum(peak_t >= lb & peak_t < t);

        % Convert to breaths/min
        rr_mean = n_breaths / win_sec * 60;

        cond(i) = isfinite(rr_mean) && rr_mean >= rr_thr_bpm;
    end
end