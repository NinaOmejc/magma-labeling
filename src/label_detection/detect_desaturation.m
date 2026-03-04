function events_Des = detect_desaturation(data, baseline, spo2_feat, config)
% detect_desaturation
% Label 6 – Desaturation (Hypoxia)
%
% This function does NOT re-detect desaturation (that is done in extract_spo2_features).
% It simply returns spo2_feat.desat_events and (optionally) plots SpO2 with shaded
% desaturation episodes.
%
% Usage:
%   events_Des = detect_desaturation(data, baseline, spo2_feat, config);

    events_Des = empty_events();

    if nargin < 3 || isempty(spo2_feat) || ~isfield(spo2_feat,'desat_events')
        return;
    end

    events_Des = spo2_feat.desat_events;

    do_plot = false;
    if isfield(config,'Des') && isfield(config.Des,'do_plot') && config.Des.do_plot
        do_plot = true;
    end
    if ~do_plot
        return;
    end

    % Need SpO2 for plotting
    if ~isfield(spo2_feat,'spo2') || isempty(spo2_feat.spo2)
        return;
    end

    spo2 = spo2_feat.spo2(:);
    t_spo2 = spo2_feat.t_spo2(:);

    % thresholds for informative lines (from config.Des if present)
    floor_thr = 90;
    drop_thr  = 3;
    if isfield(config,'spo2')
        if isfield(config.spo2,'spo2_floor'), floor_thr = config.spo2.spo2_floor; end
        if isfield(config.spo2,'drop_thr'),   drop_thr  = config.spo2.drop_thr; end
    end

    figure('Units','pixels','Position',[100 100 1200 800], 'Visible', config.make_figs_visible); 
    sgtitle(['Subject: ' num2str(config.subject) ' | Condition: ' num2str(config.condition) ' | Label 6 – Desaturation (Hypoxia)'])

    hold on
    plot(t_spo2, spo2, 'k')
    grid on
    xlabel('Time (s)')
    ylabel('SpO_2 (%)')

    % Baseline line (median first 60s)
    if isfield(baseline,'SpO2_median') && isfinite(baseline.SpO2_median)
        yline(baseline.SpO2_median, 'k--', 'baseline (median 60s)');
        yline(baseline.SpO2_median - drop_thr, 'r--', sprintf('baseline-%g', drop_thr));
    end

    % Absolute threshold
    yline(floor_thr, 'r--', sprintf('%g%%', floor_thr));

    % Shade detected desaturation events
    shade_events_on_axis(events_Des);

    % Optional: plot event start/end markers
    for k = 1:numel(events_Des)
        xline(events_Des(k).start_t, ':');
        xline(events_Des(k).end_t,   ':');
    end
    if isempty(events_Des)
        legend('SpO_2','baseline','baseline-drop','floor')
    else
        legend('SpO_2','baseline','baseline-drop','floor','desat events')        
    end
    hold off
    save_figure(config, 'desaturation');
end


