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

    if isempty(events)
        labelNames = {};
    else
        labelNames = unique({events.type}, 'stable');
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