function [mask, labelNames] = events_to_time_mask(events, N, config)
% events_to_time_mask
% Build an N-by-L logical mask using only the configured canonical labels.
% Unknown event types are rejected rather than silently adding columns.

    if nargin < 3 || ~isstruct(config) || ~isfield(config, 'labels') || ...
            ~isfield(config.labels, 'short')
        error('MAGMA:Mask:MissingCanonicalLabels', ...
            'config.labels.short is required to construct the final label mask.');
    end
    if ~isnumeric(N) || ~isscalar(N) || ~isfinite(N) || N < 0 || N ~= round(N)
        error('MAGMA:Mask:InvalidSampleCount', 'N must be a nonnegative integer.');
    end

    labelNames = {config.labels.short};
    if numel(unique(labelNames)) ~= numel(labelNames)
        error('MAGMA:Mask:DuplicateCanonicalLabel', ...
            'config.labels.short must contain unique canonical labels.');
    end
    mask = false(N, numel(labelNames));

    for i = 1:numel(events)
        event_type = char(string(events(i).type));
        label_index = find(strcmp(labelNames, event_type), 1);
        if isempty(label_index)
            error('MAGMA:Mask:UnknownEventType', ...
                'Event type "%s" is not in the configured canonical label set.', event_type);
        end
        if ~isfield(events, 'start_idx') || ~isfield(events, 'end_idx') || ...
                ~isnumeric(events(i).start_idx) || ~isscalar(events(i).start_idx) || ...
                ~isfinite(events(i).start_idx) || ...
                ~isnumeric(events(i).end_idx) || ~isscalar(events(i).end_idx) || ...
                ~isfinite(events(i).end_idx)
            error('MAGMA:Mask:InvalidEventInterval', ...
                'Event "%s" must have finite scalar start_idx and end_idx.', event_type);
        end

        start_idx = max(1, min(N, round(events(i).start_idx)));
        end_idx = max(1, min(N, round(events(i).end_idx)));
        if end_idx >= start_idx && N > 0
            mask(start_idx:end_idx, label_index) = true;
        end
    end
end
