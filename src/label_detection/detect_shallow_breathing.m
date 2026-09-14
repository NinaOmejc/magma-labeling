function [events, boundary_info] = detect_shallow_breathing(data, resp_features, config)
% DETECT_SHALLOW_BREATHING Localize consecutive shallow breaths as events.
% Each internal breath whose session-normalized excursion lies within the
% configured band contributes its complete trough-to-trough cycle. Touching
% cycles merge before the minimum-duration rule is applied. boundary_info has
% no candidate-window or endpoint evidence for this breathwise detector.

    events = empty_events();
    N = size(data, 1);
    t_grid = resp_features.resp.time_sec;
    lungs = resp_features.resp.lungs;
    diaph = resp_features.resp.diaph;
    boundary_info = make_label_boundary_info('shallow', ...
        'detect_shallow_breathing', 'not_evaluated', empty_events(), ...
        empty_events(), NaN, '', [], [], []);

    if ~lungs.session_amplitude_available && ~diaph.session_amplitude_available
        fprintf('Skipping shallow detection: no valid respiratory belt with usable breath amplitudes.\n');
        return;
    end

    [events_lungs, records_lungs, localized_lungs_events] = ...
        localize_breath_amplitude_events( ...
        lungs, N, config.fs, 'shallow_breathing_lungs', ...
        'amplitude_band', config.shallow.amp_ratio_low, config.shallow.amp_ratio_high, ...
        config.shallow.min_dur_sec, 'lungs');

    [events_diaph, records_diaph, localized_diaph_events] = ...
        localize_breath_amplitude_events( ...
        diaph, N, config.fs, 'shallow_breathing_diaph', ...
        'amplitude_band', config.shallow.amp_ratio_low, config.shallow.amp_ratio_high, ...
        config.shallow.min_dur_sec, 'diaph');

    events = merge_events({events_lungs, events_diaph});
    localized_lungs = events_to_grid_mask(localized_lungs_events, t_grid);
    localized_diaph = events_to_grid_mask(localized_diaph_events, t_grid);
    final_mask = events_to_grid_mask(events, t_grid);

    boundary_info = make_label_boundary_info('shallow', ...
        'detect_shallow_breathing', 'breathwise_amplitude_trough_localization', ...
        empty_events(), [events_lungs; events_diaph], ...
        0, 'breath_amplitude_ratio_session', [], [], ...
        localized_lungs | localized_diaph, final_mask);

    boundary_info.events = normalize_records([records_lungs; records_diaph]);
    boundary_info.boundary_uncertainty_sec = record_uncertainty(boundary_info.events);

    if config.shallow.do_plot
        opts = struct( ...
            'figure_title', 'SHALLOW BREATHING', ...
            'event_name', 'Shallow breathing', ...
            'lower_ratio', config.shallow.amp_ratio_low, ...
            'upper_ratio', config.shallow.amp_ratio_high, ...
            'localized_mask_lungs', localized_lungs, ...
            'localized_mask_diaph', localized_diaph, ...
            'output_name', 'shallow_breathing');
        plot_amplitude_state_diagnostic( ...
            resp_features, events_lungs, events_diaph, config, opts);
    end
end

function records = normalize_records(records)
% NORMALIZE_RECORDS Stamp localized boundary records with shallow-label provenance.

    for i = 1:numel(records)
        records(i).label = 'shallow';
        records(i).detector = 'detect_shallow_breathing';
    end
end

function value = record_uncertainty(records)
% RECORD_UNCERTAINTY Collect per-event uncertainty in seconds, or NaN if empty.

    if isempty(records), value = NaN; else, value = [records.uncertainty_sec]'; end
end
