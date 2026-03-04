function events = detect_apnea(data, baseline, breaths_lungs, breaths_diaph, spo2_feat, config)
% detect_apnea
% Label 7 – Apnea
%
% Criteria:
%   1) Amplitude criterion: lungs <= 10% ref AND diaphragm <= 10% ref
%      (>=90% reduction), evaluated using rolling windows.
%   2) Duration >= 10 s.
%   3) Optional: accompanying SpO2 desaturation (>=3% drop or <90%) within
%      30–60 s (SpO2 lag). If present, append "_desat" to event type.
%
% Usage:
%   events_Apn = detect_apnea(data, baseline, breaths_lungs, breaths_diaph, spo2_feat, config);

    events = empty_events();

    N = size(data,1);
    t_grid = (0:config.grid_step_sec:(N-1)/config.fs)';  % seconds

    if isempty(breaths_lungs) || isempty(breaths_diaph) || ...
       ~isfield(breaths_lungs, 'peak_t') || ~isfield(breaths_diaph, 'peak_t')
        return;
    end

    if ~isfield(baseline, 'lungs_amp_ref') || ~isfinite(baseline.lungs_amp_ref) || baseline.lungs_amp_ref <= 0 || ...
       ~isfield(baseline, 'diap_amp_ref')  || ~isfinite(baseline.diap_amp_ref)  || baseline.diap_amp_ref  <= 0
        return;
    end

    % ----------------------------
    % Config defaults
    % ----------------------------
    analysis_win_sec = 30;      % for amplitude estimate during apnea (shorter than 60 is OK)
    amp_ratio_thr    = 0.10;    % <=10% of reference
    min_dur_sec      = 10;      % apnea duration

    mark_desat       = true;    % optional certainty tagging
    desat_lag_sec    = 45;      % allow SpO2 lag (use 30–60 s; pick 45 default)
    desat_pad_sec    = 0;       % optional extra padding (usually not needed)

    if isfield(config, 'Apn')
        if isfield(config.Apn, 'analysis_win_sec'), analysis_win_sec = config.Apn.analysis_win_sec; end
        if isfield(config.Apn, 'amp_ratio_thr'),    amp_ratio_thr    = config.Apn.amp_ratio_thr; end
        if isfield(config.Apn, 'min_dur_sec'),      min_dur_sec      = config.Apn.min_dur_sec; end
        if isfield(config.Apn, 'mark_desat'),       mark_desat       = config.Apn.mark_desat; end
        if isfield(config.Apn, 'desat_lag_sec'),    desat_lag_sec    = config.Apn.desat_lag_sec; end
        if isfield(config.Apn, 'desat_pad_sec'),    desat_pad_sec    = config.Apn.desat_pad_sec; end
    end

    % ----------------------------
    % Amplitude criterion on grid (both belts <= 10% reference)
    % ----------------------------
    apnea_amp = apnea_amp_condition_on_grid( ...
        breaths_lungs, breaths_diaph, t_grid, analysis_win_sec, ...
        baseline.lungs_amp_ref, baseline.diap_amp_ref, amp_ratio_thr);

    % Convert to events (>=10 s)
    ev_grid = runs_to_events(apnea_amp, 1/config.grid_step_sec, min_dur_sec, 'apnea');
    events  = grid_events_to_sample_events(ev_grid, config.fs, N);

    % ----------------------------
    % Optional: mark apnea with desaturation (diagnostic certainty)
    % We associate apnea with a desat event occurring within [start, end + lag]
    % (and optionally expand desat events a bit).
    % ----------------------------
    if mark_desat && exist('spo2_feat','var') && ~isempty(spo2_feat) && isfield(spo2_feat,'desat_events')
        desat_events = spo2_feat.desat_events;

        if desat_pad_sec > 0
            desat_events = expand_events_time(desat_events, desat_pad_sec, (N-1)/config.fs);
        end

        for e = 1:numel(events)
            % Build a lagged association window after apnea end
            assoc = struct('start_t', events(e).start_t, 'end_t', events(e).end_t + desat_lag_sec);

            if events_overlap_any(assoc, desat_events)
                events(e).type = [events(e).type '_desat'];
            end
        end
    end

    % ----------------------------
    % Optional plot (raw + shaded apnea mask)
    % ----------------------------
    if isfield(config, 'Apn') && isfield(config.Apn, 'do_plot') && config.Apn.do_plot
        idx_lungs = find(strcmp(config.data_columns, 'Resp-Lungs'), 1);
        idx_diap  = find(strcmp(config.data_columns, 'Resp-Diaphragm'), 1);
        t_raw = (0:N-1)/config.fs;

        figure('Units','pixels','Position',[100 100 1200 800], 'Visible', config.make_figs_visible); 
        sgtitle(['APNEA | Subject: ' num2str(config.subject) ' | Condition: ' num2str(config.condition)])

        subplot(3,1,1); hold on
        plot(t_raw, data(:, idx_lungs), 'k')
        shade_mask_on_axis(t_grid, apnea_amp)
        yline(0, ':') % just a visual cue
        title('Apnea detection mask (both belts) over lungs raw signal')
        xlabel('Time (s)'); ylabel('Resp-Lungs'); grid on
        hold off

        subplot(3,1,2); hold on
        plot(t_raw, data(:, idx_diap), 'k')
        shade_mask_on_axis(t_grid, apnea_amp)
        title('Apnea detection mask (both belts) over diaphragm raw signal')
        xlabel('Time (s)'); ylabel('Resp-Diaphragm'); grid on
        hold off

        subplot(3,1,3); hold on
        % Show amplitude ratios as traces for intuition (computed on grid)
        lungs_ratio = amp_ratio_on_grid(breaths_lungs, t_grid, analysis_win_sec, baseline.lungs_amp_ref);
        diap_ratio  = amp_ratio_on_grid(breaths_diaph, t_grid, analysis_win_sec, baseline.diap_amp_ref);
        plot(t_grid, lungs_ratio, 'k')
        plot(t_grid, diap_ratio,  'b')
        yline(amp_ratio_thr, 'r--')
        title('Amplitude ratios on grid (lungs/diap)')
        xlabel('Time (s)'); ylabel('Amp ratio'); grid on
        legend('lungs ratio','diap ratio','thr')
        hold off

        ax = findall(gcf,'Type','axes');
        ax = ax(arrayfun(@(a) ~strcmp(a.Tag,'legend'), ax));
        linkaxes(ax,'x');          % tie x-zoom/pan
        xlim(ax(1), [0 t_grid(end)]);     % or whatever common range you want
   
        save_figure(config, 'apnea');
    end
end

% =========================================================
% Helpers
% =========================================================

function cond = apnea_amp_condition_on_grid(b_l, b_d, t_grid, win_sec, ref_l, ref_d, amp_ratio_thr)
% True if BOTH belts have median amplitude ratio <= amp_ratio_thr in [t-win_sec, t]
    cond = false(size(t_grid));

    for i = 1:numel(t_grid)
        t = t_grid(i);
        lb = t - win_sec;
        if lb < 0
            continue;
        end
        a_l = b_l.amp(b_l.peak_t <= t & b_l.peak_t >= lb);
        a_d = b_d.amp(b_d.peak_t <= t & b_d.peak_t >= lb);

        if numel(a_l) < 2 || numel(a_d) < 2
            continue;
        end

        med_l = median(a_l, 'omitnan');
        med_d = median(a_d, 'omitnan');

        rl = med_l / ref_l; % relative = current amplitude / reference amp
        rd = med_d / ref_d;

        if isfinite(rl) && isfinite(rd) && rl <= amp_ratio_thr && rd <= amp_ratio_thr
            cond(i) = true;
        end
    end
end

function ratio = amp_ratio_on_grid(b, t_grid, win_sec, ref_amp)
% Median amplitude ratio in [t-win_sec, t] for plotting/intuition.
    ratio = nan(size(t_grid));
    for i = 1:numel(t_grid)
        t = t_grid(i);
        lb = t - win_sec;
        a = b.amp(b.peak_t <= t & b.peak_t >= lb);
        if numel(a) < 2, continue; end
        med_a = median(a, 'omitnan');
        ratio(i) = med_a / ref_amp;
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
% True if interval e overlaps any event in ev_list.
% e must contain fields start_t and end_t.
    tf = false;
    for k = 1:numel(ev_list)
        if ~(e.end_t < ev_list(k).start_t || e.start_t > ev_list(k).end_t)
            tf = true;
            return;
        end
    end
end