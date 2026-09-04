function [irregular_events, boundary_info] = detect_irregular_breathing(data, resp_features, config)
% DETECT_IRREGULAR_BREATHING Detect timing (not shape) irregularity breathing.
%
% Syntax:
%   [irregular_events, boundary_info] = detect_irregular_breathing(data, resp_features, config)
%
% Inputs:
%   data - Input physiological signal data.
%   resp_features - Respiratory-feature structure.
%   config - Pipeline configuration structure.
%
% Outputs:
%   irregular_events - Event structure array.
%   boundary_info - Event-boundary provenance structure.

    irregular_events = empty_events();

    N = size(data,1);
    t_grid = resp_features.resp.time_sec;
    lungs = resp_features.resp.lungs;
    diaph = resp_features.resp.diaph;
    lungs_valid = lungs.available;
    diaph_valid = diaph.available;
    boundary_info = make_label_boundary_info('irregular', ...
        'detect_irregular_breathing', 'not_evaluated', empty_events(), ...
        empty_events(), NaN, '', [], [], []);

    if ~lungs_valid && ~diaph_valid
        fprintf('Skipping irregular detection: no valid respiratory belt with usable breath timing.\n');
        return;
    end

    cov_thr = 0.3;
    min_dur_sec = 60;
    analysis_win_sec = 60;
    plot_cov_step_sec = 1;
    do_plot = false;

    if isfield(config, 'irregular')
        if isfield(config.irregular, 'cov_thr'), cov_thr = config.irregular.cov_thr; end
        if isfield(config.irregular, 'min_dur_sec'), min_dur_sec = config.irregular.min_dur_sec; end
        if isfield(config.irregular, 'analysis_win_sec'), analysis_win_sec = config.irregular.analysis_win_sec; end
        if isfield(config.irregular, 'plot_cov_step_sec'), plot_cov_step_sec = config.irregular.plot_cov_step_sec; end
        if isfield(config.irregular, 'do_plot'), do_plot = config.irregular.do_plot; end
    end

    irregular_condition_lungs = false(size(t_grid));
    irregular_endpoint_lungs = false(size(t_grid));
    cov_lungs = nan(size(t_grid));
    robust_cov_lungs = nan(size(t_grid));
    if lungs_valid
        irregular_condition_lungs = lungs.irregularity.window_mask;
        irregular_endpoint_lungs = lungs.irregularity.endpoint_mask;
        cov_lungs = lungs.irregularity.cov;
        robust_cov_lungs = lungs.irregularity.robust_cov;
    end

    irregular_condition_diaph = false(size(t_grid));
    irregular_endpoint_diaph = false(size(t_grid));
    cov_diaph = nan(size(t_grid));
    robust_cov_diaph = nan(size(t_grid));
    if diaph_valid
        irregular_condition_diaph = diaph.irregularity.window_mask;
        irregular_endpoint_diaph = diaph.irregularity.endpoint_mask;
        cov_diaph = diaph.irregularity.cov;
        robust_cov_diaph = diaph.irregularity.robust_cov;
    end

    [irregular_events_lungs, irregular_mask_lungs] = sustained_condition_to_events( ...
        irregular_condition_lungs, t_grid, config.fs, N, min_dur_sec, 'irregular_breathing_lungs');
    [irregular_events_diaph, irregular_mask_diaph] = sustained_condition_to_events( ...
        irregular_condition_diaph, t_grid, config.fs, N, min_dur_sec, 'irregular_breathing_diaph');

    irregular_events = merge_events({irregular_events_lungs, irregular_events_diaph});
    boundary_info = make_label_boundary_info('irregular', ...
        'detect_irregular_breathing', ...
        'multi_breath_window_candidate_support_with_explicit_uncertainty', ...
        irregular_events, irregular_events, analysis_win_sec, ...
        'interbreath_intervals_cov', ...
        irregular_endpoint_lungs | irregular_endpoint_diaph, ...
        irregular_condition_lungs | irregular_condition_diaph, ...
        irregular_mask_lungs | irregular_mask_diaph);

    if do_plot
        opts = struct( ...
            'figure_title', ['IRREGULAR BREATHING' newline 'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)], ...
            'event_name', 'Irregular breathing', ...
            'metric_title', 'IBI coefficient of variation', ...
            'metric_detail', sprintf('%g s analysis window, %g s minimum state, %g s held display; CoV drives detection', ...
                analysis_win_sec, min_dur_sec, plot_cov_step_sec), ...
            'metric_ylabel', 'IBI variability ratio', ...
            'primary_label', 'CoV', ...
            'threshold', cov_thr, ...
            'threshold_label', sprintf('CoV threshold: >= %g', cov_thr), ...
            'secondary_metric_lungs', robust_cov_lungs, ...
            'secondary_metric_diaph', robust_cov_diaph, ...
            'secondary_label', 'Robust CoV (diagnostic)', ...
            'metric_trigger_mask_lungs', irregular_endpoint_lungs, ...
            'metric_trigger_mask_diaph', irregular_endpoint_diaph, ...
            'plot_step_sec', plot_cov_step_sec, ...
            'min_ymax', cov_thr * 1.5, ...
            'ymax_padding', 0.1, ...
            'output_name', 'irregular_breathing');
        plot_belt_diagnostic_figure(data, config, t_grid, ...
            irregular_mask_lungs, irregular_mask_diaph, ...
            cov_lungs, cov_diaph, opts);
    end
end
