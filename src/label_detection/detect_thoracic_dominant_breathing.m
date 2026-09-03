function [events, boundary_info] = detect_thoracic_dominant_breathing(data, phys_feat, config)
% detect_thoracic_dominant_breathing
% Label 9 - sustained relative thoracoabdominal excursion dominance.
% Both belts and both fixed per-belt session references are required. This
% weak label is not a calibrated rib-cage contribution or clinical cutoff.
% A qualifying endpoint summarizes an aggregate median ratio. There is no
% validated breath-pairing rule that can localize this state without adding
% a new physiological definition. The retained candidate support therefore
% carries analysis-window-scale onset/offset uncertainty.

    events = empty_events();
    evidence = phys_feat.resp.thoracoabdominal_balance;
    boundary_info = make_label_boundary_info('thoracic', ...
        'detect_thoracic_dominant_breathing', 'not_evaluated', ...
        empty_events(), empty_events(), NaN, '', [], [], []);
    if ~evidence.available
        fprintf('Skipping thoracic detection: both session-normalized respiratory belts are required.\n');
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
    analysis_window_sec = get_config_value( ...
        config, 'TDB', 'analysis_win_sec', 30);
    endpoint_mask = false(size(state_mask));
    if isfield(evidence, 'dominance_endpoint_mask')
        endpoint_mask = evidence.dominance_endpoint_mask;
    end
    boundary_info = make_label_boundary_info('thoracic', ...
        'detect_thoracic_dominant_breathing', ...
        'aggregate_window_candidate_support_with_explicit_uncertainty', ...
        events, events, analysis_window_sec, ...
        'independently_session_normalized_belt_window_medians', ...
        endpoint_mask, state_mask, dominance_mask);

    if config.TDB.do_plot
        plot_thoracic_dominance_diagnostic( ...
            phys_feat.resp.time_sec, evidence, dominance_mask, events, config);
    end
end
