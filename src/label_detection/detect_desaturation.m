function events_Des = detect_desaturation(~, baseline, spo2_feat, config)
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

    figure('Units','pixels','Position', near_fullscreen_figure_position(), 'Visible', config.make_figs_visible); 
    sgtitle(['Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure) ' | Label 6 – Desaturation (Hypoxia)'])

    hold on
    grid on
    xlabel('Time (s)')
    ylabel('SpO_2 (%)')
    ylim([89, 100])
    shade_static_baseline_on_axis(baseline, 'SpO2 baseline window');
    plot(t_spo2, spo2, 'k', 'DisplayName', 'SpO2')

    % Baseline line (median of configured static segment)
    if isfield(baseline,'SpO2_median') && isfinite(baseline.SpO2_median)
        yline(baseline.SpO2_median, 'k--', 'baseline median', 'DisplayName', 'baseline');
        yline(baseline.SpO2_median - drop_thr, 'r--', sprintf('baseline-%g', drop_thr), 'DisplayName', 'baseline-drop');
    end

    % Absolute threshold
    yline(floor_thr, 'r--', sprintf('%g%%', floor_thr), 'DisplayName', 'floor');

    % Shade detected desaturation events
    shade_events_on_axis(events_Des, 'desat events');

    % Optional: plot event start/end markers
    for k = 1:numel(events_Des)
        xline(events_Des(k).start_t, ':', 'HandleVisibility', 'off');
        xline(events_Des(k).end_t,   ':', 'HandleVisibility', 'off');
    end
    legend('show')
    hold off
    save_figure(config, 'desaturation');
end


