function events = detect_rapid_breathing(data, baseline, breaths_lungs, breaths_diaph, spo2_feat, config)
% detect_rapid_breathing
% Label 4 – Rapid Breathing (Tachypnea)
%
% Criteria:
%   - Mean RR >= 20 breaths/min sustained for >= 30 s.
%   - 30-second windows analyzed by default.
%   - Computed separately for lungs and diaphragm; positive if either is positive.
%
% Notes:
%   1) rapid_shallow = rapid breathing + shallow amplitude band.
%   2) rapid_deep    = rapid breathing + 20-35% amplitude increase from baseline.
%   3) rapid_desat   = rapid breathing + SpO2 desaturation, allowing delayed SpO2.
%   4) rapid         = rapid breathing without shallow/deep/desat subtype evidence.

    events = empty_events();

    N = size(data,1);
    t_grid = (0:config.grid_step_sec:(N-1)/config.fs)';  % seconds

    lungs_broken = isfield(config,'problems') && isfield(config.problems,'subjects_with_broken_lung_belt') && ...
        any(config.subject == config.problems.subjects_with_broken_lung_belt);
    lungs_valid = is_valid_breath_signal(breaths_lungs, false) && ~lungs_broken;
    diaph_valid = is_valid_breath_signal(breaths_diaph, false);
    lungs_amp_valid = lungs_valid && is_valid_breath_signal(breaths_lungs, true);
    diaph_amp_valid = diaph_valid && is_valid_breath_signal(breaths_diaph, true);

    if ~lungs_valid && ~diaph_valid
        return;
    end

    analysis_win_sec = get_config_value(config, 'RaB', 'analysis_win_sec', 30);
    rr_thr_bpm = get_config_value(config, 'RaB', 'rr_thr_bpm', 20);
    min_dur_sec = get_config_value(config, 'RaB', 'min_dur_sec', 30);
    classify_depth = get_config_value(config, 'RaB', 'classify_depth', true);
    shallow_lo_ratio = get_config_value(config, 'RaB', 'shallow_lo_ratio', get_config_value(config, 'ShB', 'amp_ratio_low', 0.65));
    shallow_hi_ratio = get_config_value(config, 'RaB', 'shallow_hi_ratio', get_config_value(config, 'ShB', 'amp_ratio_high', 0.80));
    deep_lo_ratio = get_config_value(config, 'RaB', 'deep_lo_ratio', 1.20);
    deep_hi_ratio = get_config_value(config, 'RaB', 'deep_hi_ratio', 1.35);
    amp_win_sec = get_config_value(config, 'ShB', 'min_dur_sec', min_dur_sec);
    subtype_min_overlap_frac = get_config_value(config, 'RaB', 'subtype_min_overlap_frac', 0.5);
    mark_desat = get_config_value(config, 'RaB', 'mark_desat', true);
    desat_delay_sec = get_config_value(config, 'RaB', 'desat_delay_sec', 20);

    rapid_lungs = false(size(t_grid));
    if lungs_valid
        rapid_lungs = compute_breath_rate_mask(breaths_lungs.peak_t, t_grid, analysis_win_sec, rr_thr_bpm, '>=', true);
    end

    rapid_diaph = false(size(t_grid));
    if diaph_valid
        rapid_diaph = compute_breath_rate_mask(breaths_diaph.peak_t, t_grid, analysis_win_sec, rr_thr_bpm, '>=', true);
    end
    rapid_any = rapid_lungs | rapid_diaph;

    ev_grid = runs_to_events(rapid_any, 1/config.grid_step_sec, min_dur_sec, 'rapid');
    rapid_events = grid_events_to_sample_events(ev_grid, config.fs, N);
    if isempty(rapid_events)
        return;
    end

    shallow_amp = false(size(t_grid));
    deep_amp = false(size(t_grid));
    if classify_depth && (lungs_amp_valid || diaph_amp_valid)
        ref_lungs = get_resp_ref_on_grid(baseline, 'lungs', t_grid);
        ref_diaph = get_resp_ref_on_grid(baseline, 'diaph', t_grid);
        shallow_amp = compute_amplitude_band_mask( ...
            breaths_lungs, lungs_amp_valid, breaths_diaph, diaph_amp_valid, ...
            t_grid, amp_win_sec, ref_lungs, ref_diaph, shallow_lo_ratio, shallow_hi_ratio);
        deep_amp = compute_amplitude_band_mask( ...
            breaths_lungs, lungs_amp_valid, breaths_diaph, diaph_amp_valid, ...
            t_grid, amp_win_sec, ref_lungs, ref_diaph, deep_lo_ratio, deep_hi_ratio);
    end

    desat_events = empty_events();
    if mark_desat && exist('spo2_feat','var') && ~isempty(spo2_feat) && isfield(spo2_feat,'desat_events')
        desat_events = expand_events_for_delayed_overlap(spo2_feat.desat_events, desat_delay_sec);
    end

    events = tag_rapid_events(rapid_events, shallow_amp, deep_amp, desat_events, ...
        t_grid, config.grid_step_sec, subtype_min_overlap_frac);

    % ----------------------------
    % Optional debug plot (raw + shaded rapid mask)
    % ----------------------------
    if isfield(config, 'RaB') && isfield(config.RaB, 'do_plot') && config.RaB.do_plot
        idx_lungs = find(strcmp(config.data_columns, 'Resp-Lungs'), 1);
        idx_diaph  = find(strcmp(config.data_columns, 'Resp-Diaphragm'), 1);
        t_raw = (0:N-1)/config.fs;

        figure('Units','pixels','Position', near_fullscreen_figure_position(), 'Visible', config.make_figs_visible); 
        sgtitle(['RAPID BREATHING' newline 'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)])

        subplot(2,1,1); hold on
        plot(t_raw, data(:, idx_lungs), 'k')
        shade_mask_on_axis(t_grid, rapid_lungs)
        title('Rapid breathing (lungs) over raw signal')
        xlabel('Time (s)'); ylabel('Resp-Lungs'); grid on
        hold off

        subplot(2,1,2); hold on
        plot(t_raw, data(:, idx_diaph), 'k')
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

function events = tag_rapid_events(rapid_events, shallow_amp, deep_amp, desat_events, t_grid, grid_step_sec, min_frac)
    events = empty_events();

    for e = 1:numel(rapid_events)
        g0 = max(1, floor(rapid_events(e).start_t / grid_step_sec) + 1);
        g1 = min(numel(t_grid), ceil(rapid_events(e).end_t / grid_step_sec) + 1);

        labels = {};
        if g0 <= g1 && mean(shallow_amp(g0:g1)) >= min_frac
            labels{end+1} = 'rapid_shallow'; %#ok<AGROW>
        end
        if g0 <= g1 && mean(deep_amp(g0:g1)) >= min_frac
            labels{end+1} = 'rapid_deep'; %#ok<AGROW>
        end
        if ~isempty(desat_events) && events_overlap_any(rapid_events(e), desat_events)
            labels{end+1} = 'rapid_desat'; %#ok<AGROW>
        end
        if isempty(labels)
            labels = {'rapid'};
        end

        for k = 1:numel(labels)
            ev = rapid_events(e);
            ev.type = labels{k};
            events(end+1,1) = ev; %#ok<AGROW>
        end
    end
end
