function mask = events_to_grid_mask(events, t_grid)
% events_to_grid_mask  Map event time intervals to an existing time grid.
    t_grid = t_grid(:);
    mask = false(size(t_grid));
    for i = 1:numel(events)
        mask = mask | (t_grid >= events(i).start_t & t_grid <= events(i).end_t);
    end
end
