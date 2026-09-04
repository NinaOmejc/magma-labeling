function shade_mask_on_axis(varargin)
% SHADE_MASK_ON_AXIS Perform the shade mask on axis operation.
%
% Syntax:
%   shade_mask_on_axis(varargin)
%
% Inputs:
%   varargin - Optional positional or name-value inputs.

    h = gobjects(0);
    if nargin >= 3 && isgraphics(varargin{1}, 'axes')
        ax = varargin{1};
        t_grid = varargin{2};
        mask = varargin{3};
    else
        ax = gca;
        t_grid = varargin{1};
        mask = varargin{2};
    end

    t_grid = t_grid(:);
    mask = mask(:) ~= 0;
    if isempty(mask) || ~any(mask)
        return;
    end
    if numel(t_grid) ~= numel(mask)
        error('t_grid and mask must have the same number of elements.');
    end

    y_limits = ylim(ax);
    grid_step_sec = median(diff(t_grid), 'omitnan');
    if ~isfinite(grid_step_sec) || grid_step_sec <= 0
        grid_step_sec = 0;
    end

    d = diff([false; mask(:); false]);
    starts = find(d == 1);
    ends   = find(d == -1) - 1;

    for i = 1:numel(starts)
        x0 = t_grid(starts(i));
        x1 = t_grid(ends(i)) + grid_step_sec;

        h(end+1,1) = patch(ax, [x0 x1 x1 x0], ...
              [y_limits(1) y_limits(1) y_limits(2) y_limits(2)], ...
              [1.00 0.65 0.65], ...
              'EdgeColor','none', ...
              'FaceAlpha',0.45, ...
              'HandleVisibility','off'); %#ok<AGROW>
        try
            uistack(h(end), 'bottom');
        catch
        end
    end
end
