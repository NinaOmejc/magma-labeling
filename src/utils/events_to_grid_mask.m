function mask = events_to_grid_mask(events, t_grid)
% EVENTS_TO_GRID_MASK Rasterize event times onto an analysis grid.
% Each event contributes the half-open interval [start_t,end_t); mask is a
% logical column vector aligned with t_grid in seconds.

    t_grid = t_grid(:);
    mask = false(size(t_grid));
    for i = 1:numel(events)
        mask = mask | (t_grid >= events(i).start_t & t_grid < events(i).end_t);
    end
end
