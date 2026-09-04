function [mask, labelNames] = events_to_time_mask(events, N, config)
% EVENTS_TO_TIME_MASK Perform the events to time mask operation.
%
% Syntax:
%   [mask, labelNames] = events_to_time_mask(events, N, config)
%
% Inputs:
%   events - Event structure data.
%   N - Number of samples.
%   config - Pipeline configuration structure.
%
% Outputs:
%   mask - Logical output mask.
%   labelNames - Output text or identifier.

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

        original_start_idx = round(events(i).start_idx);
        original_end_idx = round(events(i).end_idx);
        if N == 0 || original_end_idx < 1 || original_start_idx > N
            continue;
        end
        start_idx = max(1, original_start_idx);
        end_idx = min(N, original_end_idx);
        if end_idx >= start_idx
            mask(start_idx:end_idx, label_index) = true;
        end
    end
end
