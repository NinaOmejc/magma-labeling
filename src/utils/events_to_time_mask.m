function [mask, labelNames] = events_to_time_mask(events, N, config)
% events_to_time_mask
% Returns an NxL logical matrix mask(:,j) where mask(t,j)=true
% if sample t is within any event of label j.
%
% Inputs:
%   events      : struct array with fields type,start_idx,end_idx,...
%   N           : number of samples
%   fs          : sampling rate (unused here, kept for interface consistency)
%   labelNames  : optional cellstr, fixed ordering of labels
%
% Outputs:
%   mask        : [N x L] logical
%   labelNames  : label names used (ordering)

    labelNames = {};
    if nargin >= 3 && isfield(config, 'labels') && isfield(config.labels, 'short')
        labelNames = {config.labels.short};
    end

    if ~isempty(events)
        eventLabelNames = unique({events.type}, 'stable');
        if isempty(labelNames)
            labelNames = eventLabelNames;
        else
            extraLabelNames = setdiff(eventLabelNames, labelNames, 'stable');
            labelNames = [labelNames, extraLabelNames];
        end
    end
    L = numel(labelNames);

    mask = false(N, L);

    for e = 1:numel(events)
        j = find(strcmp(labelNames, events(e).type), 1);
        if isempty(j), continue; end

        start_idx = max(1, min(N, events(e).start_idx));
        end_idx   = max(1, min(N, events(e).end_idx));

        if end_idx >= start_idx
            mask(start_idx:end_idx, j) = true;
        end
    end
end
