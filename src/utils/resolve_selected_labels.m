function selected_labels = resolve_selected_labels(config)
% RESOLVE_SELECTED_LABELS Normalize and validate an optional detector subset.
% Missing or empty config.execution.selected_labels returns {}. Non-empty
% char, string, string-array, or cell text input is normalized to unique
% canonical short label names in caller order.

    selected_labels = {};
    if ~isstruct(config) || ~isfield(config, 'execution') || ...
            ~isstruct(config.execution) || ...
            ~isfield(config.execution, 'selected_labels')
        return;
    end
    value = config.execution.selected_labels;
    if isempty(value)
        return;
    end
    if ischar(value)
        value = {value};
    elseif isstring(value)
        value = cellstr(value(:));
    elseif iscell(value)
        normalized = cell(size(value));
        for i = 1:numel(value)
            if ~(ischar(value{i}) || (isstring(value{i}) && isscalar(value{i})))
                error('MAGMA:Execution:InvalidSelectedLabels', ...
                    ['config.execution.selected_labels must contain only ' ...
                     'character vectors or scalar strings.']);
            end
            normalized{i} = char(string(value{i}));
        end
        value = normalized;
    else
        error('MAGMA:Execution:InvalidSelectedLabels', ...
            ['config.execution.selected_labels must be empty or text ' ...
             '(char, string, string array, or cellstr).']);
    end

    value = cellfun(@(name) lower(strtrim(name)), value(:)', ...
        'UniformOutput', false);
    if any(cellfun(@isempty, value))
        error('MAGMA:Execution:InvalidSelectedLabels', ...
            'Selected label names must not be empty.');
    end
    canonical = get_labels('short');
    unknown = value(~ismember(value, canonical));
    if ~isempty(unknown)
        error('MAGMA:Execution:UnknownSelectedLabel', ...
            'Unknown selected label(s): %s. Valid labels are: %s.', ...
            strjoin(unique(unknown, 'stable'), ', '), ...
            strjoin(canonical, ', '));
    end
    selected_labels = unique(value, 'stable');
end
