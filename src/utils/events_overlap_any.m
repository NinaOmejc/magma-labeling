
function tf = events_overlap_any(e, ev_list)
% EVENTS_OVERLAP_ANY Test whether an event overlaps any event in a list.
%
% Syntax:
%   tf = events_overlap_any(e, ev_list)
%
% Inputs:
%   e - Event to test.
%   ev_list - Event structure array to compare against.
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
