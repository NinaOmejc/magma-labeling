function [events, boundary_info] = detect_thoracic_dominant_breathing(data, resp_features, config)
% DETECT_THORACIC_DOMINANT_BREATHING Detect thoracic dominant breathing.
%
% Syntax:
%   [events, boundary_info] = detect_thoracic_dominant_breathing(data, resp_features, config)
%
% Inputs:
%   data - Input physiological signal data.
%   resp_features - Respiratory-feature structure.
%   config - Pipeline configuration structure.
%
% Outputs:
%   events - Event structure array.
%   boundary_info - Event-boundary provenance structure.

    events = empty_events();
    evidence = resp_features.resp.thoracoabdominal_balance;
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
        state_mask, resp_features.resp.time_sec, config.fs, ...
        size(data, 1), config.thoracic.min_dur_sec, ...
        'thoracic_dominant_breathing');
    analysis_window_sec = get_config_value( ...
        config, 'thoracic', 'analysis_win_sec', 30);
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

    if config.thoracic.do_plot
        plot_thoracic_dominance_diagnostic( ...
            resp_features.resp.time_sec, evidence, dominance_mask, events, config);
    end
end
