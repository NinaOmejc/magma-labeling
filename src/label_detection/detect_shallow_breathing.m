function [events, boundary_info] = detect_shallow_breathing(data, phys_feat, config)
% detect_shallow_breathing
% Label 1 - sustained relative respiratory-belt excursion in the configured
% shallow band. Lungs and diaphragm provide independent evidence; either
% usable belt may generate the label. SpO2 and respiratory rate do not
% modify shallow-breathing events.
% A TRUE endpoint means every eligible breath in the preceding analysis
% window is in-band. That all-breath condition confirms the event; boundary
% times are then placed at deterministic midpoint cells around qualifying
% reviewed breaths without changing event existence.

    events = empty_events();
    N = size(data, 1);
    t_grid = phys_feat.resp.time_sec;
    lungs = phys_feat.resp.lungs;
    diaph = phys_feat.resp.diaph;
    boundary_info = make_label_boundary_info('shallowB', ...
        'detect_shallow_breathing', 'not_evaluated', empty_events(), ...
        empty_events(), NaN, '', [], [], []);

    lungs_mask = false(size(t_grid));
    if lungs.session_amplitude_available
        lungs_mask = lungs.shallow_amplitude_mask;
    end
    diaph_mask = false(size(t_grid));
    if diaph.session_amplitude_available
        diaph_mask = diaph.shallow_amplitude_mask;
    end

    if ~lungs.session_amplitude_available && ~diaph.session_amplitude_available
        fprintf('Skipping shallowB detection: no valid respiratory belt with usable breath amplitudes.\n');
        return;
    end

    [candidate_lungs, lungs_candidate_mask] = sustained_condition_to_events( ...
        lungs_mask, t_grid, config.fs, N, config.ShB.min_dur_sec, ...
        'shallow_breathing_lungs');
    [candidate_diaph, diaph_candidate_mask] = sustained_condition_to_events( ...
        diaph_mask, t_grid, config.fs, N, config.ShB.min_dur_sec, ...
        'shallow_breathing_diaph');
    [events_lungs, records_lungs] = localize_confirmed_breath_events( ...
        candidate_lungs, lungs, N, config.fs, 'shallow_breathing_lungs', ...
        'amplitude_band', config.ShB.amp_ratio_low, config.ShB.amp_ratio_high, ...
        config.ShB.analysis_win_sec, 'lungs');
    [events_diaph, records_diaph] = localize_confirmed_breath_events( ...
        candidate_diaph, diaph, N, config.fs, 'shallow_breathing_diaph', ...
        'amplitude_band', config.ShB.amp_ratio_low, config.ShB.amp_ratio_high, ...
        config.ShB.analysis_win_sec, 'diaph');
    events = merge_events({events_lungs, events_diaph});
    endpoint_mask = get_endpoint_mask(lungs, 'shallow_amplitude_endpoint_mask', t_grid) | ...
        get_endpoint_mask(diaph, 'shallow_amplitude_endpoint_mask', t_grid);
    localized_mask = events_to_grid_mask(events, t_grid);
    boundary_info = make_label_boundary_info('shallowB', ...
        'detect_shallow_breathing', 'confirmed_all_breath_window_midpoint_localization', ...
        [candidate_lungs; candidate_diaph], [events_lungs; events_diaph], ...
        NaN, 'reviewed_breath_amplitude_ratio_session', endpoint_mask, ...
        lungs_candidate_mask | diaph_candidate_mask, localized_mask);
    boundary_info.events = normalize_records([records_lungs; records_diaph]);
    boundary_info.boundary_uncertainty_sec = record_uncertainty(boundary_info.events);

    if config.ShB.do_plot
        opts = struct( ...
            'figure_title', 'SHALLOW BREATHING', ...
            'event_name', 'Shallow breathing', ...
            'lower_ratio', config.ShB.amp_ratio_low, ...
            'upper_ratio', config.ShB.amp_ratio_high, ...
            'output_name', 'shallow_breathing');
        plot_amplitude_state_diagnostic( ...
            phys_feat, events_lungs, events_diaph, config, opts);
    end
end

function mask = get_endpoint_mask(belt, field, t_grid)
    mask = false(size(t_grid));
    if isfield(belt, field), mask = logical(belt.(field)); end
end

function records = normalize_records(records)
    for i = 1:numel(records)
        records(i).label = 'shallowB';
        records(i).detector = 'detect_shallow_breathing';
    end
end

function value = record_uncertainty(records)
    if isempty(records), value = NaN; else, value = [records.uncertainty_sec]'; end
end
