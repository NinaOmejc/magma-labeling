function mask = events_to_grid_mask(events, t_grid)
% EVENTS_TO_GRID_MASK Perform the events to grid mask operation.
%
% Syntax:
%   mask = events_to_grid_mask(events, t_grid)
%
% Inputs:
%   events - Event structure data.
%   t_grid - Time coordinates in seconds.
%
% Outputs:
%   mask - Logical output mask.

    t_grid = t_grid(:);
    mask = false(size(t_grid));
    for i = 1:numel(events)
        mask = mask | (t_grid >= events(i).start_t & t_grid < events(i).end_t);
    end
end
