function [events_Des, diagnostics_Des] = detect_desaturation( ...
    data, spo2_ref, session_reference, config)
% detect_desaturation
% Label 11 - Desaturation (Hypoxia)

    if ~isfield(config, 'channels')
        config = resolve_signal_channels(config);
    end

    events_Des = empty_events();
    diagnostics_Des = struct( ...
        'signal_available', false, ...
        'reference_available', false, ...
        'reference_quality', 'not_evaluated', ...
        'detection_available', false, ...
        'spo2', [], ...
        'time_sec', [], ...
        'valid_sample_mask', [], ...
        'desaturation_sample_mask', [], ...
        'events', events_Des);

    idx_spo2 = config.channels.spo2_idx;
    if isempty(idx_spo2)
        fprintf('Skipping desat detection: SpO2 signal or reference is unavailable.\n');
        return;
    end

    diagnostics_Des.spo2 = data(:, idx_spo2);
    diagnostics_Des.time_sec = ...
        (0:numel(diagnostics_Des.spo2)-1)' / config.fs;
    diagnostics_Des.valid_sample_mask = isfinite(diagnostics_Des.spo2);
    diagnostics_Des.desaturation_sample_mask = ...
        false(size(diagnostics_Des.spo2));
    diagnostics_Des.signal_available = ...
        nnz(diagnostics_Des.valid_sample_mask) >= 2;
    diagnostics_Des.reference_available = isstruct(spo2_ref) && ...
        isfield(spo2_ref, 'available') && logical(spo2_ref.available) && ...
        isfield(spo2_ref, 'median_percent') && ...
        isfinite(spo2_ref.median_percent);
    if isstruct(spo2_ref) && isfield(spo2_ref, 'quality')
        diagnostics_Des.reference_quality = char(string(spo2_ref.quality));
    end
    diagnostics_Des.detection_available = ...
        diagnostics_Des.signal_available && diagnostics_Des.reference_available;

    if ~diagnostics_Des.detection_available
        fprintf('Skipping desat detection: SpO2 signal or reference is unavailable.\n');
        return;
    end

    floor_thr = 90;
    drop_thr = 3;
    min_dur_sec = 10;
    if isfield(config, 'spo2')
        if isfield(config.spo2, 'spo2_floor'), floor_thr = config.spo2.spo2_floor; end
        if isfield(config.spo2, 'drop_thr'), drop_thr = config.spo2.drop_thr; end
        if isfield(config.spo2, 'min_dur_sec'), min_dur_sec = config.spo2.min_dur_sec; end
    end

    events_Des = detect_desaturation_events( ...
        diagnostics_Des.spo2, spo2_ref.median_percent, config.fs, ...
        floor_thr, drop_thr, min_dur_sec);
    diagnostics_Des.desaturation_sample_mask = events_to_sample_mask( ...
        events_Des, numel(diagnostics_Des.spo2), config.fs);
    diagnostics_Des.events = events_Des;

    do_plot = isfield(config, 'Des') && isfield(config.Des, 'do_plot') && config.Des.do_plot;
    if ~do_plot
        return;
    end

    fig = figure('Units', 'pixels', 'Position', near_fullscreen_figure_position(), ...
        'Visible', config.make_figs_visible);
    sgtitle(['Subject: ' num2str(config.subject) ' | Measurement: ' ...
        num2str(config.measure) ' | Label 11 - Desaturation (Hypoxia)'])

    ax = gca;
    plot_spo2_diagnostic_panel(ax, data, spo2_ref, session_reference, ...
        diagnostics_Des, config, 'SpO2 desaturation');

    for k = 1:numel(events_Des)
        xline(ax, events_Des(k).start_t, ':', 'HandleVisibility', 'off');
        xline(ax, events_Des(k).end_t, ':', 'HandleVisibility', 'off');
    end

    set(fig, 'Visible', config.make_figs_visible);
    save_figure(config, 'desaturation');
end

function desat_events = detect_desaturation_events( ...
    spo2, spo2_base, fs, spo2_floor, drop_thr, min_dur_sec)
% Detect sustained SpO2 desaturation episodes.

    desat_events = empty_events();

    if nargin < 6 || isempty(min_dur_sec), min_dur_sec = 10; end
    if nargin < 5 || isempty(drop_thr), drop_thr = 3; end
    if nargin < 4 || isempty(spo2_floor), spo2_floor = 90; end

    if isempty(spo2) || all(isnan(spo2)) || ~isfinite(spo2_base) || ...
            ~isfinite(fs) || fs <= 0
        return;
    end

    spo2 = spo2(:);
    is_desat = false(numel(spo2), 1);
    valid = isfinite(spo2);
    is_desat(valid) = (spo2(valid) < spo2_floor) | ...
        ((spo2_base - spo2(valid)) >= drop_thr);
    desat_events = runs_to_events( ...
        is_desat, fs, min_dur_sec, 'desaturation');
end
