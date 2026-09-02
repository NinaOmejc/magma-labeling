function events = detect_shallow_breathing(data, phys_feat, config)
% detect_shallow_breathing
% Label 1 - sustained relative respiratory-belt excursion in the configured
% shallow band. Lungs and diaphragm provide independent evidence; either
% usable belt may generate the label. SpO2 and respiratory rate do not
% modify shallow-breathing events.
% A TRUE endpoint means every eligible breath in the preceding analysis
% window is in-band. phys_feat backfills that window into an inferred state;
% min_dur_sec is then applied once to that state.

    events = empty_events();
    N = size(data, 1);
    t_grid = phys_feat.resp.time_sec;
    lungs = phys_feat.resp.lungs;
    diaph = phys_feat.resp.diaph;

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

    [events_lungs, ~] = sustained_condition_to_events( ...
        lungs_mask, t_grid, config.fs, N, config.ShB.min_dur_sec, ...
        'shallow_breathing_lungs');
    [events_diaph, ~] = sustained_condition_to_events( ...
        diaph_mask, t_grid, config.fs, N, config.ShB.min_dur_sec, ...
        'shallow_breathing_diaph');
    events = merge_events({events_lungs, events_diaph});

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
