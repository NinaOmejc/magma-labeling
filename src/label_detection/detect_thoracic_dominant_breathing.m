function events = detect_thoracic_dominant_breathing(data, phys_feat, config)
% detect_thoracic_dominant_breathing
% Label 11 - sustained relative thoracoabdominal excursion dominance.
% Both belts and both fixed per-belt session references are required. This
% weak label is not a calibrated rib-cage contribution or clinical cutoff.
% A qualifying endpoint already summarizes analysis_win_sec of evidence.
% Its preceding support window is included in dominance_state_mask, and
% min_dur_sec is applied once to that inferred state (not to endpoints).

    events = empty_events();
    evidence = phys_feat.resp.thoracoabdominal_balance;
    if ~evidence.available
        fprintf('Skipping thorDomB detection: both session-normalized respiratory belts are required.\n');
        return;
    end

    if isfield(evidence, 'dominance_state_mask')
        state_mask = evidence.dominance_state_mask;
    else
        state_mask = evidence.dominance_mask;
    end
    [events, dominance_mask] = sustained_condition_to_events( ...
        state_mask, phys_feat.resp.time_sec, config.fs, ...
        size(data, 1), config.TDB.min_dur_sec, ...
        'thoracic_dominant_breathing');

    if config.TDB.do_plot
        plot_thoracic_dominance_diagnostic( ...
            phys_feat.resp.time_sec, evidence, dominance_mask, events, config);
    end
end
