function [irregular_events, boundary_info] = detect_irregular_breathing(data, resp_features, config)
% detect_irregular_breathing
% Label 5 - Irregular Breathing
%
% Definition:
%   Irregular breathing means that durations of consecutive breathing cycles
%   vary unpredictably and without a clear pattern.
%
% Measurements (per config.IrB.analysis_win_sec segments):
%   - Compute IBI = time between consecutive respiratory peaks.
%   - Compute CoV = std(IBI) / mean(IBI).
%   - Compute robust CoV = 1.4826 * MAD(IBI) / median(IBI).
%   - Compute RMSSD = sqrt(mean(diff(IBI).^2)).
%   - Use config.IrB.detection_metric to choose the detection metric.
% Detector grids map to master samples using config.fs.
%   - No breathing pauses allowed in analyzed segment.
%   - CoV is intrinsically a multi-breath/window property. Candidate support
%     is retained with explicit analysis-window timing uncertainty; no
%     unsupported instantaneous onset is claimed.

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
    robust_cov_thr = 0.25;
    rmssd_thr = 0.0;
    min_dur_sec = 60;
    analysis_win_sec = 60;
    plot_cov_step_sec = 15;
    detection_metric = 'cov';
    do_plot = false;

    if isfield(config, 'IrB')
        if isfield(config.IrB, 'cov_thr'), cov_thr = config.IrB.cov_thr; end
        if isfield(config.IrB, 'robust_cov_thr'), robust_cov_thr = config.IrB.robust_cov_thr; end
        if isfield(config.IrB, 'rmssd_thr'), rmssd_thr = config.IrB.rmssd_thr; end
        if isfield(config.IrB, 'min_dur_sec'), min_dur_sec = config.IrB.min_dur_sec; end
        if isfield(config.IrB, 'analysis_win_sec'), analysis_win_sec = config.IrB.analysis_win_sec; end
        if isfield(config.IrB, 'plot_cov_step_sec'), plot_cov_step_sec = config.IrB.plot_cov_step_sec; end
        if isfield(config.IrB, 'detection_metric'), detection_metric = config.IrB.detection_metric; end
        if isfield(config.IrB, 'do_plot'), do_plot = config.IrB.do_plot; end
    end
    if isstring(detection_metric)
        detection_metric = char(detection_metric);
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
        ['reviewed_interbreath_intervals_' lower(strtrim(detection_metric))], ...
        irregular_endpoint_lungs | irregular_endpoint_diaph, ...
        irregular_condition_lungs | irregular_condition_diaph, ...
        irregular_mask_lungs | irregular_mask_diaph);

    if do_plot
        rmssd_suffix = '';
        if isfinite(rmssd_thr) && rmssd_thr > 0
            rmssd_suffix = ', RMSSD also enabled';
        end
        [primary_lungs, primary_diaph, primary_label, primary_thr, primary_used, ...
            secondary_lungs, secondary_diaph, secondary_label, secondary_thr, secondary_used] = ...
            irregular_plot_metrics(cov_lungs, cov_diaph, robust_cov_lungs, robust_cov_diaph, ...
            cov_thr, robust_cov_thr, detection_metric);

        opts = struct( ...
            'figure_title', ['IRREGULAR BREATHING' newline 'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)], ...
            'event_name', 'Irregular breathing', ...
            'metric_title', 'IBI variability used for irregular detection', ...
            'metric_detail', sprintf('%g s analysis window, %g s minimum state, %g s held display, detection=%s%s', ...
                analysis_win_sec, min_dur_sec, plot_cov_step_sec, detection_metric, rmssd_suffix), ...
            'metric_ylabel', 'IBI variability ratio', ...
            'primary_label', primary_label, ...
            'threshold', primary_thr, ...
            'threshold_label', threshold_label(primary_label, primary_thr, detection_metric, primary_used), ...
            'secondary_metric_lungs', secondary_lungs, ...
            'secondary_metric_diaph', secondary_diaph, ...
            'secondary_label', secondary_label, ...
            'secondary_threshold', secondary_thr, ...
            'secondary_threshold_label', threshold_label(secondary_label, secondary_thr, detection_metric, secondary_used), ...
            'metric_trigger_mask_lungs', irregular_endpoint_lungs, ...
            'metric_trigger_mask_diaph', irregular_endpoint_diaph, ...
            'plot_step_sec', plot_cov_step_sec, ...
            'min_ymax', max([cov_thr, robust_cov_thr] * 1.5, [], 'omitnan'), ...
            'ymax_padding', 0.1, ...
            'output_name', 'irregular_breathing');
        plot_belt_diagnostic_figure(data, config, t_grid, irregular_mask_lungs, irregular_mask_diaph, primary_lungs, primary_diaph, opts);
    end
end

function [primary_lungs, primary_diaph, primary_label, primary_thr, primary_used, ...
    secondary_lungs, secondary_diaph, secondary_label, secondary_thr, secondary_used] = ...
    irregular_plot_metrics(cov_lungs, cov_diaph, robust_cov_lungs, robust_cov_diaph, ...
    cov_thr, robust_cov_thr, detection_metric)

    if any(strcmpi(strtrim(detection_metric), {'robust_cov','robust'}))
        primary_lungs = robust_cov_lungs;
        primary_diaph = robust_cov_diaph;
        primary_label = 'Robust CoV';
        primary_thr = robust_cov_thr;
        primary_used = {'robust_cov','robust'};
        secondary_lungs = cov_lungs;
        secondary_diaph = cov_diaph;
        secondary_label = 'CoV';
        secondary_thr = cov_thr;
        secondary_used = {'cov','plain_cov'};
    else
        primary_lungs = cov_lungs;
        primary_diaph = cov_diaph;
        primary_label = 'CoV';
        primary_thr = cov_thr;
        primary_used = {'cov','plain_cov','either','both'};
        secondary_lungs = robust_cov_lungs;
        secondary_diaph = robust_cov_diaph;
        secondary_label = 'Robust CoV';
        secondary_thr = robust_cov_thr;
        secondary_used = {'robust_cov','robust','either','both'};
    end
end

function label = threshold_label(metric_name, threshold, detection_metric, used_metrics)
    is_used = any(strcmpi(strtrim(detection_metric), used_metrics));
    used_suffix = '';
    if is_used
        used_suffix = ' (used)';
    end
    label = sprintf('%s threshold: >= %g%s', metric_name, threshold, used_suffix);
end
