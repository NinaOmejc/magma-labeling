
function tf = events_overlap_any(e, ev_list)
% EVENTS_OVERLAP_ANY Test whether an event overlaps any event in a list.
%
% Inputs:
%   e       - Scalar event with start_t and end_t boundaries in seconds.
%   ev_list - Event struct array using the same half-open time convention.
%
% Outputs:
%   tf - True when any overlap is present.

    tf = false;
    for k = 1:numel(ev_list)
        if ~(e.end_t <= ev_list(k).start_t || e.start_t >= ev_list(k).end_t)
            tf = true;
            return;
        end
    end
end
