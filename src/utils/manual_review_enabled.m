function enabled = manual_review_enabled(config)
% MANUAL_REVIEW_ENABLED Derive the manual-review GUI policy from execution mode.

    mode = execution_mode(config);
    enabled = ismember(mode, {'analyze_and_review', 'review_only'});
end
