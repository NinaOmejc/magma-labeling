function [events_desat, diagnostics_desat, spo2_ref] = detect_desaturation( ...
    data, session_reference, config)
% DETECT_DESATURATION Find sustained low SpO2 relative to absolute and baseline criteria.
% data is Nsample-by-Nchannel; session_reference defines the interval used to
% compute the SpO2 baseline; config supplies channel, fs, thresholds, duration,
% and plot settings. events_desat are sample/time events; diagnostics_desat is
% intentionally compact. spo2_ref is returned separately for authoritative
% storage at results.spo2_ref.

    if ~isfield(config, 'channels')
        config = resolve_signal_channels(config);
    end

    spo2_ref = compute_spo2_reference(data, session_reference, config);
    events_desat = empty_events();
    diagnostics_desat = struct( ...
        'signal_available', false, ...
        'reference_available', false, ...
        'reference_quality', 'not_evaluated', ...
        'detection_available', false);

    idx_spo2 = config.channels.spo2_idx;
    if isempty(idx_spo2)
        fprintf('Skipping desat detection: SpO2 signal or reference is unavailable.\n');
        return;
    end

    spo2 = data(:, idx_spo2);
    valid_sample_mask = isfinite(spo2);
    diagnostics_desat.signal_available = ...
        nnz(valid_sample_mask) >= 2;
    diagnostics_desat.reference_available = isstruct(spo2_ref) && ...
        isfield(spo2_ref, 'available') && logical(spo2_ref.available) && ...
        isfield(spo2_ref, 'median_percent') && ...
        isfinite(spo2_ref.median_percent);
    if isstruct(spo2_ref) && isfield(spo2_ref, 'quality')
        diagnostics_desat.reference_quality = char(string(spo2_ref.quality));
    end
    diagnostics_desat.detection_available = ...
        diagnostics_desat.signal_available && diagnostics_desat.reference_available;

    if ~diagnostics_desat.detection_available
        fprintf('Skipping desat detection: SpO2 signal or reference is unavailable.\n');
        return;
    end

    floor_thr = 90;
    drop_thr = 3;
    min_dur_sec = 10;
    if isfield(config, 'desat')
        if isfield(config.desat, 'spo2_floor'), floor_thr = config.desat.spo2_floor; end
        if isfield(config.desat, 'drop_thr'), drop_thr = config.desat.drop_thr; end
        if isfield(config.desat, 'min_dur_sec'), min_dur_sec = config.desat.min_dur_sec; end
    end

    events_desat = detect_desaturation_events( ...
        spo2, spo2_ref.median_percent, config.fs, ...
        floor_thr, drop_thr, min_dur_sec);

    do_plot = isfield(config, 'desat') && isfield(config.desat, 'do_plot') && config.desat.do_plot;
    if ~do_plot
        return;
    end

    pos = near_fullscreen_figure_position();
    pos(4) = 0.55 * pos(4);   % reduce figure height
    fig = figure('Units', 'pixels', 'Position', pos, 'Visible', config.make_figs_visible);
    sgtitle(['Subject: ' num2str(config.subject) ' | Measurement: ' ...
        num2str(config.measure) ' | Label 11 - Desaturation (Hypoxia)'])

    ax = gca;
    plot_spo2_diagnostic_panel(ax, data, session_reference, ...
        spo2_ref, events_desat, config, 'SpO2 desaturation');

    for k = 1:numel(events_desat)
        xline(ax, events_desat(k).start_t, ':', 'HandleVisibility', 'off');
        xline(ax, events_desat(k).end_t, ':', 'HandleVisibility', 'off');
    end

    set(fig, 'Visible', config.make_figs_visible);
    save_figure(config, 'desaturation');
end

function desat_events = detect_desaturation_events( ...
    spo2, spo2_base, fs, spo2_floor, drop_thr, min_dur_sec)
% DETECT_DESATURATION_EVENTS Convert sustained sample-level SpO2 criteria to events.
% spo2 and spo2_base are percentages; fs is hertz. A finite sample qualifies
% below spo2_floor or at least drop_thr percentage points below baseline.
% Runs shorter than min_dur_sec are discarded.

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
