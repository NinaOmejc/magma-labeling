function [events, boundary_info] = detect_rapid_breathing(data, phys_feat, config)
% detect_rapid_breathing
% Label 4 - mean respiratory rate >= the configured threshold. The rolling
% window confirms an event; reviewed breathwise RR localizes its boundary.
% A qualifying aggregate window is not treated as proof that every sample
% in the preceding window was rapid.
% Rate is evaluated independently per usable belt; amplitude and SpO2 do
% not modify rapid-breathing events.

    events = empty_events();
    N = size(data, 1);
    t_grid = phys_feat.resp.time_sec;
    lungs = phys_feat.resp.lungs;
    diaph = phys_feat.resp.diaph;
    boundary_info = make_label_boundary_info('rapidB', ...
        'detect_rapid_breathing', 'not_evaluated', empty_events(), ...
        empty_events(), NaN, '', [], [], []);

    if ~lungs.available && ~diaph.available
        fprintf('Skipping rapidB detection: no valid respiratory belt with usable breath timing.\n');
        return;
    end

    rr_thr_bpm = get_config_value(config, 'RaB', 'rr_thr_bpm', 20);
    analysis_win_sec = get_config_value(config, 'RaB', 'analysis_win_sec', 30);
    min_dur_sec = get_config_value(config, 'RaB', 'min_dur_sec', 30);
    plot_rr_step_sec = get_config_value(config, 'RaB', 'plot_rr_step_sec', 15);

    rr_lungs = nan(size(t_grid));
    rapid_lungs_state = false(size(t_grid));
    rapid_lungs_endpoint = false(size(t_grid));
    if lungs.available
        rr_lungs = lungs.rate_rapid_window_bpm;
        rapid_lungs_endpoint = isfinite(rr_lungs) & rr_lungs >= rr_thr_bpm;
        if isfield(lungs, 'rate_rapid_state_mask')
            rapid_lungs_state = lungs.rate_rapid_state_mask;
        else
            rapid_lungs_state = analysis_window_endpoints_to_state_mask( ...
                rapid_lungs_endpoint, t_grid, analysis_win_sec);
        end
    end

    rr_diaph = nan(size(t_grid));
    rapid_diaph_state = false(size(t_grid));
    rapid_diaph_endpoint = false(size(t_grid));
    if diaph.available
        rr_diaph = diaph.rate_rapid_window_bpm;
        rapid_diaph_endpoint = isfinite(rr_diaph) & rr_diaph >= rr_thr_bpm;
        if isfield(diaph, 'rate_rapid_state_mask')
            rapid_diaph_state = diaph.rate_rapid_state_mask;
        else
            rapid_diaph_state = analysis_window_endpoints_to_state_mask( ...
                rapid_diaph_endpoint, t_grid, analysis_win_sec);
        end
    end

    [candidate_lungs, rapid_lungs_candidate] = sustained_condition_to_events( ...
        rapid_lungs_state, t_grid, config.fs, N, min_dur_sec, ...
        'rapid_breathing_lungs');
    [candidate_diaph, rapid_diaph_candidate] = sustained_condition_to_events( ...
        rapid_diaph_state, t_grid, config.fs, N, min_dur_sec, ...
        'rapid_breathing_diaph');
    [events_lungs, records_lungs] = localize_confirmed_breath_events( ...
        candidate_lungs, lungs, N, config.fs, 'rapid_breathing_lungs', ...
        'rate_ge', rr_thr_bpm, NaN, analysis_win_sec, 'lungs');
    [events_diaph, records_diaph] = localize_confirmed_breath_events( ...
        candidate_diaph, diaph, N, config.fs, 'rapid_breathing_diaph', ...
        'rate_ge', rr_thr_bpm, NaN, analysis_win_sec, 'diaph');
    events = merge_events({events_lungs, events_diaph});
    rapid_lungs = events_to_grid_mask(events_lungs, t_grid);
    rapid_diaph = events_to_grid_mask(events_diaph, t_grid);
    boundary_info = make_label_boundary_info('rapidB', ...
        'detect_rapid_breathing', 'confirmed_window_breath_interval_localization', ...
        [candidate_lungs; candidate_diaph], [events_lungs; events_diaph], ...
        NaN, 'reviewed_breathwise_rr_bpm', ...
        rapid_lungs_endpoint | rapid_diaph_endpoint, ...
        rapid_lungs_candidate | rapid_diaph_candidate, ...
        rapid_lungs | rapid_diaph);
    boundary_info.events = normalize_records([records_lungs; records_diaph]);
    boundary_info.boundary_uncertainty_sec = record_uncertainty(boundary_info.events);

    if isempty(events)
        return;
    end

    if isfield(config, 'RaB') && isfield(config.RaB, 'do_plot') && config.RaB.do_plot
        opts = struct( ...
            'figure_title', ['RAPID BREATHING' newline 'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)], ...
            'event_name', 'Rapid breathing', ...
            'metric_title', 'Mean breaths/min used for rapid detection', ...
            'metric_detail', sprintf('%g s trailing analysis window; %g s held display', ...
                analysis_win_sec, plot_rr_step_sec), ...
            'metric_ylabel', 'Breaths/min', ...
            'threshold', rr_thr_bpm, ...
            'threshold_label', sprintf('Threshold: >= %g breaths/min', rr_thr_bpm), ...
            'plot_step_sec', plot_rr_step_sec, ...
            'min_ymax', rr_thr_bpm + 10, ...
            'ymax_padding', 5, ...
            'output_name', 'rapid_breathing');
        plot_belt_diagnostic_figure( ...
            data, config, t_grid, rapid_lungs, rapid_diaph, rr_lungs, rr_diaph, opts);
    end
end

function records = normalize_records(records)
    for i = 1:numel(records)
        records(i).label = 'rapidB';
        records(i).detector = 'detect_rapid_breathing';
    end
end

function value = record_uncertainty(records)
    if isempty(records), value = NaN; else, value = [records.uncertainty_sec]'; end
end
