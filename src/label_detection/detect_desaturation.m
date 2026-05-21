function events_Des = detect_desaturation(data, baseline, spo2_feat, config)
% detect_desaturation
% Label 6 - Desaturation (Hypoxia)
%
% This function does NOT re-detect desaturation. Detection is done in
% extract_spo2_features; this function returns those events and optionally
% plots the shared SpO2 diagnostic panel.

    events_Des = empty_events();

    if nargin < 3 || isempty(spo2_feat) || ~isfield(spo2_feat, 'desat_events') || ...
            ~isfield(spo2_feat, 'idx_spo2') || isempty(spo2_feat.idx_spo2)
        return;
    end

    events_Des = spo2_feat.desat_events;

    do_plot = isfield(config, 'Des') && isfield(config.Des, 'do_plot') && config.Des.do_plot;
    if ~do_plot
        return;
    end

    fig = figure('Units', 'pixels', 'Position', near_fullscreen_figure_position(), ...
        'Visible', config.make_figs_visible);
    sgtitle(['Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure) ' | Label 6 - Desaturation (Hypoxia)'])

    ax = gca;
    plot_spo2_diagnostic_panel(ax, data, baseline, spo2_feat, config, 'SpO2 desaturation');

    for k = 1:numel(events_Des)
        xline(ax, events_Des(k).start_t, ':', 'HandleVisibility', 'off');
        xline(ax, events_Des(k).end_t, ':', 'HandleVisibility', 'off');
    end

    set(fig, 'Visible', config.make_figs_visible);
    save_figure(config, 'desaturation');
end
