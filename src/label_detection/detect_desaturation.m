function [events_desat, diagnostics_desat] = detect_desaturation( ...
    data, spo2_ref, session_reference, config)
% DETECT_DESATURATION Detect desaturation.
%
% Syntax:
%   [events_desat, diagnostics_desat] = detect_desaturation(data, spo2_ref, session_reference, config)
%
% Inputs:
%   data - Input physiological signal data.
%   spo2_ref - SpO2-reference structure.
%   session_reference - Session-reference metadata.
%   config - Pipeline configuration structure.
%
% Outputs:
%   events_desat - Event structure array.
%   diagnostics_desat - Detector diagnostic structure.

    if ~isfield(config, 'channels')
        config = resolve_signal_channels(config);
    end

    events_desat = empty_events();
    diagnostics_desat = struct( ...
        'signal_available', false, ...
        'reference_available', false, ...
        'reference_quality', 'not_evaluated', ...
        'detection_available', false, ...
        'spo2', [], ...
        'time_sec', [], ...
        'valid_sample_mask', [], ...
        'desaturation_sample_mask', [], ...
        'events', events_desat);

    idx_spo2 = config.channels.spo2_idx;
    if isempty(idx_spo2)
        fprintf('Skipping desat detection: SpO2 signal or reference is unavailable.\n');
        return;
    end

    diagnostics_desat.spo2 = data(:, idx_spo2);
    diagnostics_desat.time_sec = ...
        (0:numel(diagnostics_desat.spo2)-1)' / config.fs;
    diagnostics_desat.valid_sample_mask = isfinite(diagnostics_desat.spo2);
    diagnostics_desat.desaturation_sample_mask = ...
        false(size(diagnostics_desat.spo2));
    diagnostics_desat.signal_available = ...
        nnz(diagnostics_desat.valid_sample_mask) >= 2;
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
        diagnostics_desat.spo2, spo2_ref.median_percent, config.fs, ...
        floor_thr, drop_thr, min_dur_sec);
    diagnostics_desat.desaturation_sample_mask = events_to_sample_mask( ...
        events_desat, numel(diagnostics_desat.spo2), config.fs);
    diagnostics_desat.events = events_desat;

    do_plot = isfield(config, 'desat') && isfield(config.desat, 'do_plot') && config.desat.do_plot;
    if ~do_plot
        return;
    end

    fig = figure('Units', 'pixels', 'Position', near_fullscreen_figure_position(), ...
        'Visible', config.make_figs_visible);
    sgtitle(['Subject: ' num2str(config.subject) ' | Measurement: ' ...
        num2str(config.measure) ' | Label 11 - Desaturation (Hypoxia)'])

    ax = gca;
    plot_spo2_diagnostic_panel(ax, data, spo2_ref, session_reference, ...
        diagnostics_desat, config, 'SpO2 desaturation');

    for k = 1:numel(events_desat)
        xline(ax, events_desat(k).start_t, ':', 'HandleVisibility', 'off');
        xline(ax, events_desat(k).end_t, ':', 'HandleVisibility', 'off');
    end

    set(fig, 'Visible', config.make_figs_visible);
    save_figure(config, 'desaturation');
end

function desat_events = detect_desaturation_events( ...
    spo2, spo2_base, fs, spo2_floor, drop_thr, min_dur_sec)
% DETECT_DESATURATION_EVENTS Detect desaturation events.
%
% Syntax:
%   desat_events = detect_desaturation_events(spo2, spo2_base, fs, spo2_floor, drop_thr, min_dur_sec)
%
% Inputs:
%   spo2 - Input value `spo2`.
%   spo2_base - Input value `spo2_base`.
%   fs - Sampling frequency in hertz.
%   spo2_floor - Input value `spo2_floor`.
%   drop_thr - Selection threshold value.
%   min_dur_sec - Duration or window length in seconds.
%
% Outputs:
%   desat_events - Event structure array.

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
