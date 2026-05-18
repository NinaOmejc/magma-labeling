function events = detect_apnea(data, baseline, breaths_lungs, breaths_diaph, spo2_feat, config)
% detect_apnea
% Label 7 – Apnea
%
% Criteria:
%   1) Amplitude criterion: lungs <= 10% ref AND diaphragm <= 10% ref
%      (>=90% reduction), evaluated using rolling windows.
%   2) Duration >= 10 s.
%   3) Optional: accompanying SpO2 desaturation (>=3% drop or <90%) that
%      30–60 s (SpO2 lag). If present, append "_desat" to event type.
%
% Current code uses config.spo2.desat_association_delay_sec as the single
% shared association delay for breathing-related desaturation; the older
% apnea-specific 30-60 s lag window is no longer used.
%
% Usage:
%   events_Apn = detect_apnea(data, baseline, breaths_lungs, breaths_diaph, spo2_feat, config);

    events = empty_events();

    N = size(data,1);
    t_grid = (0:config.grid_step_sec:(N-1)/config.fs)';  % seconds

    lungs_broken = isfield(config,'problems') && isfield(config.problems,'subjects_with_broken_lung_belt') && ...
        any(config.subject == config.problems.subjects_with_broken_lung_belt);
    lungs_valid = is_valid_breath_signal(breaths_lungs, true) && ~lungs_broken;
    diaph_valid = is_valid_breath_signal(breaths_diaph, true);
    if ~(lungs_valid || diaph_valid)
        return;
    end

    % ----------------------------
    % Config defaults
    % ----------------------------
    amp_ratio_thr    = 0.10;    % <=10% of reference for both belts
    min_dur_sec      = 10;      % apnea duration
    mark_desat       = true;    % optional certainty tagging
    desat_association_delay_sec = get_config_value(config, 'spo2', 'desat_association_delay_sec', 10);

    if isfield(config, 'Apn')
        if isfield(config.Apn, 'amp_ratio_thr'),    amp_ratio_thr    = config.Apn.amp_ratio_thr; end
        if isfield(config.Apn, 'min_dur_sec'),      min_dur_sec      = config.Apn.min_dur_sec; end
        if isfield(config.Apn, 'mark_desat'),       mark_desat       = config.Apn.mark_desat; end
    end

    % ----------------------------
    % Amplitude criterion on grid (both belts <= 10% reference)
    % ----------------------------
    ref_lungs = get_resp_ref_on_grid(baseline, 'lungs', t_grid);
    ref_diaph = get_resp_ref_on_grid(baseline, 'diaph', t_grid);

    if lungs_valid
        lungs_valid = any(isfinite(ref_lungs) & ref_lungs > 0);
    end
    if diaph_valid
        diaph_valid = any(isfinite(ref_diaph) & ref_diaph > 0);
    end
    if ~(lungs_valid || diaph_valid)
        return;
    end

    apnea_amp = apnea_amp_condition_on_grid( ...
        breaths_lungs, breaths_diaph, t_grid, min_dur_sec, ...
        ref_lungs, ref_diaph, amp_ratio_thr, lungs_valid, diaph_valid);

    % Sustain the endpoint amplitude condition before creating events.
    [events, apnea_amp] = sustained_condition_to_events( ...
        apnea_amp, t_grid, config.fs, N, min_dur_sec, 'apnea');

    % ----------------------------
    % Optional: mark apnea with desaturation (diagnostic certainty).
    % A desaturation is associated if it overlaps apnea or starts within
    % config.spo2.desat_association_delay_sec after apnea.
    % ----------------------------
    if mark_desat && exist('spo2_feat','var') && ~isempty(spo2_feat) && isfield(spo2_feat,'desat_events')
        desat_events = expand_events_for_delayed_overlap(spo2_feat.desat_events, desat_association_delay_sec);

        for e = 1:numel(events)
            if events_overlap_any(events(e), desat_events)
                events(e).type = [events(e).type '_desat'];
            end
        end
    end

    % ----------------------------
    % Optional plot (raw + shaded apnea mask)
    % ----------------------------
    if isfield(config, 'Apn') && isfield(config.Apn, 'do_plot') && config.Apn.do_plot
        idx_lungs = find(strcmp(config.data_columns, 'Resp-Lungs'), 1);
        idx_diaph  = find(strcmp(config.data_columns, 'Resp-Diaphragm'), 1);
        t_raw = (0:N-1)/config.fs;

        figure('Units','pixels','Position', near_fullscreen_figure_position(), 'Visible', config.make_figs_visible); 
        sgtitle(['APNEA | Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)])

        subplot(3,1,1); hold on
        plot(t_raw, data(:, idx_lungs), 'k')
        shade_mask_on_axis(t_grid, apnea_amp)
        yline(0, ':') % just a visual cue
        title('Apnea detection mask (both belts) over lungs raw signal')
        xlabel('Time (s)'); ylabel('Resp-Lungs'); grid on
        hold off

        subplot(3,1,2); hold on
        plot(t_raw, data(:, idx_diaph), 'k')
        shade_mask_on_axis(t_grid, apnea_amp)
        title('Apnea detection mask (both belts) over diaphragm raw signal')
        xlabel('Time (s)'); ylabel('Resp-Diaphragm'); grid on
        hold off

        subplot(3,1,3); hold on
        % Show amplitude ratios as traces for intuition (computed on grid)
        lungs_ratio = nan(size(t_grid));
        if lungs_valid
            lungs_ratio = amp_ratio_on_grid(breaths_lungs, t_grid, min_dur_sec, ref_lungs);
        end
        diaph_ratio  = nan(size(t_grid));
        if diaph_valid
            diaph_ratio = amp_ratio_on_grid(breaths_diaph, t_grid, min_dur_sec, ref_diaph);
        end
        plot(t_grid, lungs_ratio, 'k')
        plot(t_grid, diaph_ratio,  'b')
        yline(amp_ratio_thr, 'r--')
        if isfield(config,'rolling_baseline') && isfield(config.rolling_baseline,'enabled') && config.rolling_baseline.enabled
            title(sprintf('Amplitude ratios on grid (rolling ref win=%ds, lag=%ds)', config.rolling_baseline.win_sec, config.rolling_baseline.lag_sec))
        else
            title('Amplitude ratios on grid (static ref)')
        end
        xlabel('Time (s)'); ylabel('Amp ratio'); grid on
        legend('lungs ratio','diaph ratio','thr')
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

function cond = apnea_amp_condition_on_grid(b_l, b_d, t_grid, win_sec, ref_l, ref_d, amp_ratio_thr, use_lungs, use_diaph)
% If both belts are valid: require BOTH <= threshold.
% If only one belt is valid: use that belt alone.
    cond = false(size(t_grid));

    if isscalar(ref_l)
        ref_l = ref_l * ones(size(t_grid));
    end

    if isscalar(ref_d)
        ref_d = ref_d * ones(size(t_grid));
    end

    for i = 1:numel(t_grid)
        t = t_grid(i);
        lb = t - win_sec;
        if lb < 0
            continue;
        end
        lung_ok = false;
        diaph_ok = false;

        if use_lungs && isfinite(ref_l(i)) && ref_l(i) > 0
            a_l = b_l.amp(b_l.peak_t <= t & b_l.peak_t >= lb);
            if numel(a_l) >= 2
                med_l = median(a_l, 'omitnan');
                rl = med_l / ref_l(i);
                lung_ok = isfinite(rl) && rl <= amp_ratio_thr;
            end
        end

        if use_diaph && isfinite(ref_d(i)) && ref_d(i) > 0
            a_d = b_d.amp(b_d.peak_t <= t & b_d.peak_t >= lb);
            if numel(a_d) >= 2
                med_d = median(a_d, 'omitnan');
                rd = med_d / ref_d(i);
                diaph_ok = isfinite(rd) && rd <= amp_ratio_thr;
            end
        end

        if use_lungs && use_diaph
            cond(i) = lung_ok && diaph_ok;
        elseif use_lungs
            cond(i) = lung_ok;
        elseif use_diaph
            cond(i) = diaph_ok;
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
        if isscalar(ref_amp)
            ratio(i) = med_a / ref_amp;
        else
            ratio(i) = med_a / ref_amp(i);
        end
    end
end
