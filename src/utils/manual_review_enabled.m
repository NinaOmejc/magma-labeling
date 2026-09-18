function enabled = manual_review_enabled(config)
% MANUAL_REVIEW_ENABLED Derive the manual-review GUI policy from execution mode.

    if ~isfield(config, 'execution') || ~isstruct(config.execution) || ...
            ~isfield(config.execution, 'mode')
        error('MAGMA:Execution:MissingMode', ...
            'config.execution.mode is required.');
    end

    mode_value = string(config.execution.mode);
    if ~isscalar(mode_value) || ismissing(mode_value) || strlength(mode_value) == 0
        error('MAGMA:Execution:InvalidMode', ...
            'config.execution.mode must be a nonempty scalar value.');
    end
    mode = char(mode_value);
    valid_modes = {'analyze_only', 'analyze_and_review', 'review_only'};
    if ~ismember(mode, valid_modes)
        error('MAGMA:Execution:InvalidMode', ...
            ['config.execution.mode must be analyze_only, ' ...
             'analyze_and_review, or review_only.']);
    end

    enabled = ismember(mode, {'analyze_and_review', 'review_only'});
end
