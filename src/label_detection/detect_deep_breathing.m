function events = detect_deep_breathing(data, phys_feat, config)
% detect_deep_breathing
% Label 10 - sustained relative increase in respiratory-belt excursion.
% A reviewed breath is deep when its excursion divided by that belt's fixed
% session reference is >= config.DeB.amp_ratio_thr. This is an uncalibrated,
% within-record belt-amplitude state, not absolute tidal volume.

    events = empty_events();
    N = size(data, 1);
    t_grid = phys_feat.resp.time_sec;
    lungs = phys_feat.resp.lungs;
    diaph = phys_feat.resp.diaph;

    lungs_mask = false(size(t_grid));
    if lungs.session_amplitude_available
        lungs_mask = lungs.deep_amplitude_mask;
    end
    diaph_mask = false(size(t_grid));
    if diaph.session_amplitude_available
        diaph_mask = diaph.deep_amplitude_mask;
    end

    if ~lungs.session_amplitude_available && ~diaph.session_amplitude_available
        fprintf('Skipping deepB detection: no valid respiratory belt with usable breath amplitudes.\n');
        return;
    end

    [events_lungs, ~] = sustained_condition_to_events( ...
        lungs_mask, t_grid, config.fs, N, config.DeB.min_dur_sec, ...
        'deep_breathing_lungs');
    [events_diaph, ~] = sustained_condition_to_events( ...
        diaph_mask, t_grid, config.fs, N, config.DeB.min_dur_sec, ...
        'deep_breathing_diaph');
    events = merge_events({events_lungs, events_diaph});

    if config.DeB.do_plot
        opts = struct( ...
            'figure_title', 'DEEP BREATHING', ...
            'event_name', 'Deep breathing', ...
            'lower_ratio', config.DeB.amp_ratio_thr, ...
            'output_name', 'deep_breathing');
        plot_amplitude_state_diagnostic( ...
            phys_feat, events_lungs, events_diaph, config, opts);
    end
end
