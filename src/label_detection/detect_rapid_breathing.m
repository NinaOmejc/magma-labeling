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
    if classify_depth && isfinite(baseline.lungs_amp_ref) && baseline.lungs_amp_ref > 0 && ...
                        isfinite(baseline.diap_amp_ref)  && baseline.diap_amp_ref  > 0

        amp_shallow = shallow_amp_condition_on_grid( ...
            breaths_lungs, breaths_diaph, t_grid, analysis_win_sec, ...
            baseline.lungs_amp_ref, baseline.diap_amp_ref, shallow_lo_ratio, shallow_hi_ratio);

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
        sgtitle(['RAPID BREATHING' newline 'Subject: ' num2str(config.subject) ' | Condition: ' num2str(config.condition)])

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
% At each grid time t:
%   - take peaks in [t-win_sec, t]
%   - compute mean RR = 60 / mean(IBI)
%   - cond true if RR >= rr_thr_bpm
    cond = false(size(t_grid));
    peak_t = peak_t(:);

    for i = 1:numel(t_grid)
        t = t_grid(i);
        lb = t - win_sec;
        
        if lb < 0 
            continue;
        end

        idx = find(peak_t >= lb & peak_t <= t);
        if numel(idx) < 3
            continue; % need at least 2 IBIs
        end

        ibi = diff(peak_t(idx)); % seconds
        rr_mean = 60 / mean(ibi, 'omitnan');

        if isfinite(rr_mean) && rr_mean >= rr_thr_bpm
            cond(i) = true;
        end
    end
end
