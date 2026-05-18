function [events, sustained_mask, grid_events] = sustained_condition_to_events(cond, t_grid, fs, N, min_dur_sec, label)
% sustained_condition_to_events
% Convert a grid diagnostic condition into sustained events.
%
% The input condition should already represent the detector's intended
% diagnostic mask on t_grid. Rolling-window detectors may pass either an
% endpoint mask or a backfilled analysis-window mask, depending on their
% event semantics. This helper only keeps runs where the provided condition
% stays true for min_dur_sec.

    cond = cond(:) ~= 0;
    t_grid = t_grid(:);

    if numel(cond) ~= numel(t_grid)
        error('cond and t_grid must have the same number of elements.');
    end

    events = empty_events();
    sustained_mask = false(size(t_grid));
    grid_events = empty_events();

    if isempty(t_grid) || isempty(cond)
        return;
    end

    if numel(t_grid) > 1
        grid_step_sec = median(diff(t_grid), 'omitnan');
    else
        grid_step_sec = 1;
    end

    if ~isfinite(grid_step_sec) || grid_step_sec <= 0
        error('t_grid must be increasing with a positive step.');
    end

    grid_events = runs_to_events(cond, 1/grid_step_sec, min_dur_sec, label);

    for i = 1:numel(grid_events)
        g0 = max(1, grid_events(i).start_idx);
        g1 = min(numel(t_grid), grid_events(i).end_idx);
        sustained_mask(g0:g1) = true;
    end

    events = grid_events_to_sample_events(grid_events, fs, N);
end
