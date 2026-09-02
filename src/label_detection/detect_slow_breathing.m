function events = detect_slow_breathing(data, phys_feat, config)
% detect_slow_breathing
% Label 3 - mean respiratory rate <= the configured threshold. Each TRUE
% endpoint summarizes the preceding analysis_win_sec; its complete window
% supports the inferred state. min_dur_sec is applied once to that state.
% Rate is evaluated independently per usable belt; amplitude and SpO2 do
% not modify slow-breathing events.

    events = empty_events();
    N = size(data, 1);
    t_grid = phys_feat.resp.time_sec;
    lungs = phys_feat.resp.lungs;
    diaph = phys_feat.resp.diaph;

    if ~lungs.available && ~diaph.available
        fprintf('Skipping slowB detection: no valid respiratory belt with usable breath timing.\n');
        return;
    end

    rr_thr_bpm = get_config_value(config, 'SlB', 'rr_thr_bpm', 10);
    min_dur_sec = get_config_value(config, 'SlB', 'min_dur_sec', 30);
    plot_rr_step_sec = get_config_value(config, 'SlB', 'plot_rr_step_sec', 15);

    rr_lungs = nan(size(t_grid));
    slow_lungs_state = false(size(t_grid));
    if lungs.available
        rr_lungs = lungs.rate_slow_window_bpm;
        slow_lungs_endpoint = isfinite(rr_lungs) & rr_lungs <= rr_thr_bpm;
        if isfield(lungs, 'rate_slow_state_mask')
            slow_lungs_state = lungs.rate_slow_state_mask;
        else
            slow_lungs_state = analysis_window_endpoints_to_state_mask( ...
                slow_lungs_endpoint, t_grid, phys_feat.resp.rate_windows_sec.slow);
        end
    end

    rr_diaph = nan(size(t_grid));
    slow_diaph_state = false(size(t_grid));
    if diaph.available
        rr_diaph = diaph.rate_slow_window_bpm;
        slow_diaph_endpoint = isfinite(rr_diaph) & rr_diaph <= rr_thr_bpm;
        if isfield(diaph, 'rate_slow_state_mask')
            slow_diaph_state = diaph.rate_slow_state_mask;
        else
            slow_diaph_state = analysis_window_endpoints_to_state_mask( ...
                slow_diaph_endpoint, t_grid, phys_feat.resp.rate_windows_sec.slow);
        end
    end

    [events_lungs, slow_lungs] = sustained_condition_to_events( ...
        slow_lungs_state, t_grid, config.fs, N, min_dur_sec, ...
        'slow_breathing_lungs');
    [events_diaph, slow_diaph] = sustained_condition_to_events( ...
        slow_diaph_state, t_grid, config.fs, N, min_dur_sec, ...
        'slow_breathing_diaph');
    events = merge_events({events_lungs, events_diaph});

    if isfield(config, 'SlB') && isfield(config.SlB, 'do_plot') && config.SlB.do_plot
        opts = struct( ...
            'figure_title', ['SLOW BREATHING' newline 'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)], ...
            'event_name', 'Slow breathing', ...
            'metric_title', 'Mean breaths/min used for slow detection', ...
            'metric_detail', sprintf('%g s trailing analysis window; %g s held display', ...
                phys_feat.resp.rate_windows_sec.slow, plot_rr_step_sec), ...
            'metric_ylabel', 'Breaths/min', ...
            'threshold', rr_thr_bpm, ...
            'threshold_label', sprintf('Threshold: <= %g breaths/min', rr_thr_bpm), ...
            'plot_step_sec', plot_rr_step_sec, ...
            'min_ymax', rr_thr_bpm + 10, ...
            'ymax_padding', 5, ...
            'output_name', 'slow_breathing');
        plot_belt_diagnostic_figure( ...
            data, config, t_grid, slow_lungs, slow_diaph, rr_lungs, rr_diaph, opts);
    end
end
