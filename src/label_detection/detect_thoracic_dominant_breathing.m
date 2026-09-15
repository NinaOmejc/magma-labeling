function [events, candidate_events] = detect_thoracic_dominant_breathing(data, resp_features, config)
% DETECT_THORACIC_DOMINANT_BREATHING Convert sustained cross-belt dominance to events.
% resp_features supplies trailing-window medians of independently session-
% normalized thoracic and abdominal amplitudes. data/config provide recording
% length, sampling, minimum duration, and plotting. candidate_events retains
% every event-like state run before the final duration decision.

    events = empty_events();
    evidence = resp_features.thoracoabdominal_balance;
    candidate_events = empty_candidate_events();
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
        state_mask, resp_features.time_sec, config.fs, ...
        size(data, 1), config.thoracic.min_dur_sec, ...
        'thoracic_dominant_breathing');
    analysis_window_sec = get_config_value( ...
        config, 'thoracic', 'analysis_win_sec', 30);
    [pre_duration_events, ~] = sustained_condition_to_events( ...
        state_mask, resp_features.time_sec, config.fs, ...
        size(data, 1), 0, 'thoracic_dominant_breathing');
    if ~isempty(pre_duration_events)
        accepted = [pre_duration_events.duration]' >= ...
            config.thoracic.min_dur_sec;
        reasons = repmat({''}, numel(pre_duration_events), 1);
        reasons(~accepted) = {'too_short'};
        candidate_events = events_to_candidate_events( ...
            pre_duration_events, 'both', accepted, reasons, ...
            analysis_window_sec);
    end

    if config.thoracic.do_plot
        plot_thoracic_dominance_diagnostic( ...
            resp_features.time_sec, evidence, dominance_mask, events, config);
    end
end
