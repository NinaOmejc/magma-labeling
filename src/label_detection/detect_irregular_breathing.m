function irregular_events = detect_irregular_breathing(data, resp_feat, config)
% detect_irregular_breathing
% Label 2 - Irregular Breathing
%
% Definition:
%   Irregular breathing means that durations of consecutive breathing cycles
%   vary unpredictably and without a clear pattern.
%
% Measurements (per 30-60 s segments):
%   - Compute IBI = time between consecutive respiratory peaks.
%   - Compute CoV = std(IBI) / mean(IBI).
%   - Compute robust CoV = 1.4826 * MAD(IBI) / median(IBI).
%   - Compute RMSSD = sqrt(mean(diff(IBI).^2)).
%   - Use config.IrB.detection_metric to choose the detection metric.
%   - No breathing pauses allowed in analyzed segment.
%   - A qualifying rolling analysis window is marked across the whole window;
%     only sustained runs of that window mask become labels.

    irregular_events = empty_events();

    N = size(data,1);
    t_grid = (0:config.grid_step_sec:(N-1)/config.new_fs)';

    lungs_broken = isfield(config,'problems') && isfield(config.problems,'subjects_with_broken_lung_belt') && ...
        any(config.subject == config.problems.subjects_with_broken_lung_belt);
    lungs_valid = is_valid_breath_signal(resp_feat.lungs, false) && ~lungs_broken;
    diaph_valid = is_valid_breath_signal(resp_feat.diaph, false);

    if ~lungs_valid && ~diaph_valid
        return;
    end

    cov_thr = 0.3;
    robust_cov_thr = 0.25;
    rmssd_thr = 0.0;
    pause_thr = 10;
    min_dur_sec = 60;
    plot_cov_step_sec = 15;
    detection_metric = 'robust_cov';
    do_plot = false;

    if isfield(config, 'IrB')
        if isfield(config.IrB, 'cov_thr'), cov_thr = config.IrB.cov_thr; end
        if isfield(config.IrB, 'robust_cov_thr'), robust_cov_thr = config.IrB.robust_cov_thr; end
        if isfield(config.IrB, 'rmssd_thr'), rmssd_thr = config.IrB.rmssd_thr; end
        if isfield(config.IrB, 'pause_thr_sec'), pause_thr = config.IrB.pause_thr_sec; end
        if isfield(config.IrB, 'min_dur_sec'), min_dur_sec = config.IrB.min_dur_sec; end
        if isfield(config.IrB, 'plot_cov_step_sec'), plot_cov_step_sec = config.IrB.plot_cov_step_sec; end
        if isfield(config.IrB, 'detection_metric'), detection_metric = config.IrB.detection_metric; end
        if isfield(config.IrB, 'do_plot'), do_plot = config.IrB.do_plot; end
    end
    if isstring(detection_metric)
        detection_metric = char(detection_metric);
    end

    irregular_condition_lungs = false(size(t_grid));
    cov_lungs = nan(size(t_grid));
    robust_cov_lungs = nan(size(t_grid));
    if lungs_valid
        [irregular_condition_lungs, cov_lungs, robust_cov_lungs] = compute_irregularity_metrics( ...
            resp_feat.lungs, t_grid, min_dur_sec, cov_thr, robust_cov_thr, rmssd_thr, pause_thr, detection_metric);
    end

    irregular_condition_diaph = false(size(t_grid));
    cov_diaph = nan(size(t_grid));
    robust_cov_diaph = nan(size(t_grid));
    if diaph_valid
        [irregular_condition_diaph, cov_diaph, robust_cov_diaph] = compute_irregularity_metrics( ...
            resp_feat.diaph, t_grid, min_dur_sec, cov_thr, robust_cov_thr, rmssd_thr, pause_thr, detection_metric);
    end

    [irregular_events_lungs, irregular_mask_lungs] = sustained_condition_to_events( ...
        irregular_condition_lungs, t_grid, config.new_fs, N, min_dur_sec, 'irregular_breathing_lungs');
    [irregular_events_diaph, irregular_mask_diaph] = sustained_condition_to_events( ...
        irregular_condition_diaph, t_grid, config.new_fs, N, min_dur_sec, 'irregular_breathing_diaph');

    irregular_events = merge_events({irregular_events_lungs, irregular_events_diaph});

    if do_plot
        rmssd_suffix = '';
        if isfinite(rmssd_thr) && rmssd_thr > 0
            rmssd_suffix = ', RMSSD also enabled';
        end

        opts = struct( ...
            'figure_title', ['IRREGULAR BREATHING' newline 'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)], ...
            'event_name', 'Irregular breathing', ...
            'metric_title', 'IBI variability used for irregular detection', ...
            'metric_detail', sprintf('%g s window, %g s held median, detection=%s%s', min_dur_sec, plot_cov_step_sec, detection_metric, rmssd_suffix), ...
            'metric_ylabel', 'IBI variability ratio', ...
            'primary_label', 'CoV', ...
            'threshold', cov_thr, ...
            'threshold_label', threshold_label('CoV', cov_thr, detection_metric, {'cov','plain_cov','either','both'}), ...
            'secondary_metric_lungs', robust_cov_lungs, ...
            'secondary_metric_diaph', robust_cov_diaph, ...
            'secondary_label', 'Robust CoV', ...
            'secondary_threshold', robust_cov_thr, ...
            'secondary_threshold_label', threshold_label('Robust CoV', robust_cov_thr, detection_metric, {'robust_cov','robust','either','both'}), ...
            'plot_step_sec', plot_cov_step_sec, ...
            'min_ymax', max([cov_thr, robust_cov_thr] * 1.5, [], 'omitnan'), ...
            'ymax_padding', 0.1, ...
            'output_name', 'irregular_breathing');
        plot_belt_diagnostic_figure(data, config, t_grid, irregular_mask_lungs, irregular_mask_diaph, cov_lungs, cov_diaph, opts);
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
