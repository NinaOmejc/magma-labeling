function [irregular_events, candidate_events] = detect_irregular_breathing(data, resp_features, config)
% DETECT_IRREGULAR_BREATHING Convert qualifying IBI-CoV window support to events.
% data supplies recording length; resp_features supplies each belt's CoV traces,
% endpoint_mask (the trailing analysis window ending here meets the threshold),
% and window_mask (the union of qualifying back-projected windows). Continuous
% window support is emitted directly, without a separate duration filter.
% Robust CoV is plotted only as a diagnostic and never drives classification.

    irregular_events = empty_events();

    N = size(data,1);
    t_grid = resp_features.time_sec;
    lungs = resp_features.lungs;
    diaph = resp_features.diaph;
    lungs_valid = lungs.available;
    diaph_valid = diaph.available;
    candidate_events = empty_candidate_events();

    if ~lungs_valid && ~diaph_valid
        log_message(config, 1, ...
            ['Skipping irregular detection: no valid respiratory belt with ' ...
             'usable breath timing.']);
        return;
    end

    cov_thr = 0.3;
    analysis_win_sec = 60;
    plot_cov_step_sec = 1;
    do_plot = false;

    if isfield(config, 'irregular')
        if isfield(config.irregular, 'cov_thr'), cov_thr = config.irregular.cov_thr; end
        if isfield(config.irregular, 'analysis_win_sec'), analysis_win_sec = config.irregular.analysis_win_sec; end
        if isfield(config.irregular, 'plot_cov_step_sec'), plot_cov_step_sec = config.irregular.plot_cov_step_sec; end
        if isfield(config.irregular, 'do_plot'), do_plot = config.irregular.do_plot; end
    end

    irregular_window_lungs = false(size(t_grid));
    irregular_endpoint_lungs = false(size(t_grid));
    cov_lungs = nan(size(t_grid));
    robust_cov_lungs = nan(size(t_grid));
    if lungs_valid
        irregular_window_lungs = lungs.irregularity.window_mask;
        irregular_endpoint_lungs = lungs.irregularity.endpoint_mask;
        cov_lungs = lungs.irregularity.cov;
        robust_cov_lungs = lungs.irregularity.robust_cov;
    end

    irregular_window_diaph = false(size(t_grid));
    irregular_endpoint_diaph = false(size(t_grid));
    cov_diaph = nan(size(t_grid));
    robust_cov_diaph = nan(size(t_grid));
    if diaph_valid
        irregular_window_diaph = diaph.irregularity.window_mask;
        irregular_endpoint_diaph = diaph.irregularity.endpoint_mask;
        cov_diaph = diaph.irregularity.cov;
        robust_cov_diaph = diaph.irregularity.robust_cov;
    end

    % Each true run is already the merged support of one or more qualifying
    % analysis windows. A zero minimum converts every such run directly.
    [irregular_events_lungs, irregular_mask_lungs] = sustained_condition_to_events( ...
        irregular_window_lungs, t_grid, config.fs, N, 0, 'irregular_breathing_lungs');
    [irregular_events_diaph, irregular_mask_diaph] = sustained_condition_to_events( ...
        irregular_window_diaph, t_grid, config.fs, N, 0, 'irregular_breathing_diaph');

    irregular_events = merge_events({irregular_events_lungs, irregular_events_diaph});
    if do_plot
        opts = struct( ...
            'figure_title', ['IRREGULAR BREATHING' newline 'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)], ...
            'event_name', 'Irregular breathing', ...
            'metric_title', 'IBI coefficient of variation', ...
            'metric_detail', sprintf('%g s analysis window; CoV drives detection; %g s held display', ...
                analysis_win_sec, plot_cov_step_sec), ...
            'metric_ylabel', 'IBI variability ratio', ...
            'primary_label', 'CoV', ...
            'threshold', cov_thr, ...
            'threshold_label', sprintf('CoV threshold: >= %g', cov_thr), ...
            'secondary_metric_lungs', robust_cov_lungs, ...
            'secondary_metric_diaph', robust_cov_diaph, ...
            'secondary_label', 'Robust CoV (diagnostic)', ...
            'metric_trigger_mask_lungs', irregular_endpoint_lungs, ...
            'metric_trigger_mask_diaph', irregular_endpoint_diaph, ...
            'final_state_label', 'Final irregular-window support', ...
            'plot_step_sec', plot_cov_step_sec, ...
            'min_ymax', cov_thr * 1.5, ...
            'ymax_padding', 0.1, ...
            'output_name', 'irregular_breathing');
        plot_belt_diagnostic_figure(data, config, t_grid, ...
            irregular_mask_lungs, irregular_mask_diaph, ...
            cov_lungs, cov_diaph, opts);
    end
end
