function mode = execution_mode(config)
% EXECUTION_MODE Validate and return the configured pipeline execution mode.

    if ~isfield(config, 'execution') || ~isstruct(config.execution) || ...
            ~isfield(config.execution, 'mode')
        error('MAGMA:Execution:MissingMode', ...
            'config.execution.mode is required.');
    end
    value = string(config.execution.mode);
    if ~isscalar(value) || ismissing(value) || strlength(value) == 0
        error('MAGMA:Execution:InvalidMode', ...
            'config.execution.mode must be a nonempty scalar value.');
    end
    mode = char(value);
    if ~ismember(mode, {'analyze', 'analyze_and_review', 'review_only'})
        error('MAGMA:Execution:InvalidMode', ...
            ['config.execution.mode must be analyze, analyze_and_review, ' ...
             'or review_only.']);
    end
end
