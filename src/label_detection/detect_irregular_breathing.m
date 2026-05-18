function irregular_events = detect_irregular_breathing(data, breaths_lungs, breaths_diaph, config)
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
%   - Compute RMSSD = sqrt(mean(diff(IBI).^2)).
%   - If CoV >= threshold OR RMSSD >= threshold -> irregular breathing.
%   - No breathing pauses allowed in analyzed segment.
%   - A qualifying rolling analysis window is marked across the whole window;
%     only sustained runs of that window mask become labels.

    irregular_events = empty_events();

    N = size(data,1);
    t_grid = (0:config.grid_step_sec:(N-1)/config.fs)';

    lungs_broken = isfield(config,'problems') && isfield(config.problems,'subjects_with_broken_lung_belt') && ...
        any(config.subject == config.problems.subjects_with_broken_lung_belt);
    lungs_valid = is_valid_breath_signal(breaths_lungs, false) && ~lungs_broken;
    diaph_valid = is_valid_breath_signal(breaths_diaph, false);

    if ~lungs_valid && ~diaph_valid
        return;
    end

    cov_thr = 0.3;
    rmssd_thr = 0.0;
    pause_thr = 10;
    min_dur_sec = 60;
    plot_cov_step_sec = 15;
    do_plot = false;

    if isfield(config, 'IrB')
        if isfield(config.IrB, 'cov_thr'), cov_thr = config.IrB.cov_thr; end
        if isfield(config.IrB, 'rmssd_thr'), rmssd_thr = config.IrB.rmssd_thr; end
        if isfield(config.IrB, 'pause_thr_sec'), pause_thr = config.IrB.pause_thr_sec; end
        if isfield(config.IrB, 'min_dur_sec'), min_dur_sec = config.IrB.min_dur_sec; end
        if isfield(config.IrB, 'plot_cov_step_sec'), plot_cov_step_sec = config.IrB.plot_cov_step_sec; end
        if isfield(config.IrB, 'do_plot'), do_plot = config.IrB.do_plot; end
    end

    irregular_condition_lungs = false(size(t_grid));
    cov_lungs = nan(size(t_grid));
    if lungs_valid
        [irregular_condition_lungs, cov_lungs] = compute_irregularity_metrics( ...
            breaths_lungs, t_grid, min_dur_sec, cov_thr, rmssd_thr, pause_thr);
    end

    irregular_condition_diaph = false(size(t_grid));
    cov_diaph = nan(size(t_grid));
    if diaph_valid
        [irregular_condition_diaph, cov_diaph] = compute_irregularity_metrics( ...
            breaths_diaph, t_grid, min_dur_sec, cov_thr, rmssd_thr, pause_thr);
    end

    [irregular_events_lungs, irregular_mask_lungs] = sustained_condition_to_events( ...
        irregular_condition_lungs, t_grid, config.fs, N, min_dur_sec, 'irregular_breathing_lungs');
    [irregular_events_diaph, irregular_mask_diaph] = sustained_condition_to_events( ...
        irregular_condition_diaph, t_grid, config.fs, N, min_dur_sec, 'irregular_breathing_diaph');

    irregular_events = merge_events({irregular_events_lungs, irregular_events_diaph});

    if do_plot
        rmssd_suffix = '';
        if isfinite(rmssd_thr) && rmssd_thr > 0
            rmssd_suffix = ', RMSSD also enabled';
        end

        opts = struct( ...
            'figure_title', ['IRREGULAR BREATHING' newline 'Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)], ...
            'event_name', 'Irregular breathing', ...
            'metric_title', 'CoV used for irregular detection', ...
            'metric_detail', sprintf('%g s window, %g s held median%s', min_dur_sec, plot_cov_step_sec, rmssd_suffix), ...
            'metric_ylabel', 'CoV', ...
            'threshold', cov_thr, ...
            'threshold_label', sprintf('Threshold: CoV >= %g', cov_thr), ...
            'plot_step_sec', plot_cov_step_sec, ...
            'min_ymax', max(cov_thr * 1.5, 0.5), ...
            'ymax_padding', 0.1, ...
            'output_name', 'irregular_breathing');
        plot_belt_diagnostic_figure(data, config, t_grid, irregular_mask_lungs, irregular_mask_diaph, cov_lungs, cov_diaph, opts);
    end
end
