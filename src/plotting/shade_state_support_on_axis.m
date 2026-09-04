function handles = shade_state_support_on_axis( ...
    ax, t_grid, candidate_mask, localized_mask, final_mask)
% SHADE_STATE_SUPPORT_ON_AXIS Perform the shade state support on axis operation.
%
% Syntax:
%   handles = shade_state_support_on_axis(ax, t_grid, candidate_mask, localized_mask, final_mask)
%
% Inputs:
%   ax - Target axes handle.
%   t_grid - Time coordinates in seconds.
%   candidate_mask - Logical state or selection mask.
%   localized_mask - Logical state or selection mask.
%   final_mask - Logical state or selection mask.
%
% Outputs:
%   handles - Graphics handle or array.

    three_layer_mode = ~isempty(candidate_mask) || ~isempty(localized_mask);
    layers = { ...
        candidate_mask, [0.55 0.55 0.55], 0.16, 'Rolling/candidate support'; ...
        localized_mask, [1.00 0.65 0.00], 0.24, 'All localized qualifying support'; ...
        final_mask, [0.15 0.60 0.25], 0.34, 'Final retained state'};
    handles = gobjects(0);
    t_grid = t_grid(:);
    if isempty(t_grid)
        return;
    end

    y_limits = ylim(ax);
    if numel(t_grid) > 1
        grid_step_sec = median(diff(t_grid), 'omitnan');
    else
        grid_step_sec = 0;
    end
    if ~isfinite(grid_step_sec) || grid_step_sec < 0
        grid_step_sec = 0;
    end

    for layer_index = 1:size(layers, 1)
        mask = logical(layers{layer_index, 1}(:));
        if isempty(mask) || ~any(mask)
            if three_layer_mode
                p = patch(ax, nan(1,4), nan(1,4), layers{layer_index, 2}, ...
                    'EdgeColor', 'none', 'FaceAlpha', layers{layer_index, 3}, ...
                    'DisplayName', layers{layer_index, 4});
                handles(end+1, 1) = p; %#ok<AGROW>
            end
            continue;
        end
        if numel(mask) ~= numel(t_grid)
            error('MAGMA:Plot:SupportMaskAlignment', ...
                'Candidate, localized, and final masks must align with t_grid.');
        end
        d = diff([false; mask; false]);
        starts = find(d == 1);
        ends = find(d == -1) - 1;
        for run_index = 1:numel(starts)
            x0 = t_grid(starts(run_index));
            x1 = t_grid(ends(run_index)) + grid_step_sec;
            visibility = 'off';
            if run_index == 1
                visibility = 'on';
            end
            p = patch(ax, [x0 x1 x1 x0], ...
                [y_limits(1) y_limits(1) y_limits(2) y_limits(2)], ...
                layers{layer_index, 2}, 'EdgeColor', 'none', ...
                'FaceAlpha', layers{layer_index, 3}, ...
                'DisplayName', layers{layer_index, 4}, ...
                'HandleVisibility', visibility);
            handles(end+1, 1) = p; %#ok<AGROW>
        end
    end
end
