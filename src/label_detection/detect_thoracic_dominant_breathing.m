function events = detect_thoracic_dominant_breathing(data, phys_feat, config)
% detect_thoracic_dominant_breathing
% Label 11 - sustained relative thoracoabdominal excursion dominance.
% Both belts and both fixed per-belt session references are required. This
% weak label is not a calibrated rib-cage contribution or clinical cutoff.

    events = empty_events();
    evidence = phys_feat.resp.thoracoabdominal_balance;
    if ~evidence.available
        fprintf('Skipping thorDomB detection: both session-normalized respiratory belts are required.\n');
        return;
    end

    [events, dominance_mask] = sustained_condition_to_events( ...
        evidence.dominance_mask, phys_feat.resp.time_sec, config.fs, ...
        size(data, 1), config.TDB.min_dur_sec, ...
        'thoracic_dominant_breathing');

    if config.TDB.do_plot
        plot_thoracic_dominance_diagnostic( ...
            phys_feat.resp.time_sec, evidence, dominance_mask, events, config);
    end
end
