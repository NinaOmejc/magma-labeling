function [events, boundary_info] = detect_deep_breathing(data, resp_features, config)
% DETECT_DEEP_BREATHING Localize consecutive high-amplitude breaths as events.
% Each internal breath at or above the session-normalized threshold contributes
% its complete trough-to-trough cycle. Touching cycles merge before the
% minimum-duration rule is applied. boundary_info has no candidate-window or
% endpoint evidence for this breathwise detector.

    events = empty_events();
    N = size(data, 1);
    t_grid = resp_features.time_sec;
    lungs = resp_features.lungs;
    diaph = resp_features.diaph;
    boundary_info = make_label_boundary_info('deep', ...
        'detect_deep_breathing', 'not_evaluated', empty_events(), ...
        empty_events(), NaN, '', [], [], []);

    if ~lungs.session_amplitude_available && ~diaph.session_amplitude_available
        fprintf('Skipping deep detection: no valid respiratory belt with usable breath amplitudes.\n');
        return;
    end

    [events_lungs, records_lungs, localized_lungs_events] = ...
        localize_breath_amplitude_events( ...
        lungs, N, config.fs, 'deep_breathing_lungs', ...
        'amplitude_ge', config.deep.amp_ratio_thr, NaN, ...
        config.deep.min_dur_sec, 'lungs');
    [events_diaph, records_diaph, localized_diaph_events] = ...
        localize_breath_amplitude_events( ...
        diaph, N, config.fs, 'deep_breathing_diaph', ...
        'amplitude_ge', config.deep.amp_ratio_thr, NaN, ...
        config.deep.min_dur_sec, 'diaph');
    events = merge_events({events_lungs, events_diaph});
    localized_lungs = events_to_grid_mask(localized_lungs_events, t_grid);
    localized_diaph = events_to_grid_mask(localized_diaph_events, t_grid);
    final_mask = events_to_grid_mask(events, t_grid);
    boundary_info = make_label_boundary_info('deep', ...
        'detect_deep_breathing', 'breathwise_amplitude_trough_localization', ...
        empty_events(), [events_lungs; events_diaph], ...
        0, 'breath_amplitude_ratio_session', [], [], ...
        localized_lungs | localized_diaph, final_mask);
    boundary_info.events = normalize_records([records_lungs; records_diaph]);
    boundary_info.boundary_uncertainty_sec = record_uncertainty(boundary_info.events);

    if config.deep.do_plot
        opts = struct( ...
            'figure_title', 'DEEP BREATHING', ...
            'event_name', 'Deep breathing', ...
            'lower_ratio', config.deep.amp_ratio_thr, ...
            'localized_mask_lungs', localized_lungs, ...
            'localized_mask_diaph', localized_diaph, ...
            'output_name', 'deep_breathing');
        plot_amplitude_state_diagnostic( ...
            resp_features, events_lungs, events_diaph, config, opts);
    end
end

function records = normalize_records(records)
% NORMALIZE_RECORDS Stamp localized boundary records with deep-label provenance.

    for i = 1:numel(records)
        records(i).label = 'deep';
        records(i).detector = 'detect_deep_breathing';
    end
end

function value = record_uncertainty(records)
% RECORD_UNCERTAINTY Collect per-event uncertainty in seconds, or NaN if empty.

    if isempty(records), value = NaN; else, value = [records.uncertainty_sec]'; end
end
