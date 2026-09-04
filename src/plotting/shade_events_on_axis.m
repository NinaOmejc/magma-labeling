function h = shade_events_on_axis(ax, events, display_name)
% SHADE_EVENTS_ON_AXIS Perform the shade events on axis operation.
%
% Syntax:
%   h = shade_events_on_axis(ax, events, display_name)
%
% Inputs:
%   ax - Target axes handle.
%   events - Event structure data.
%   display_name - Input value `display_name`.
%
% Outputs:
%   h - Graphics handle or array.

    h = gobjects(0);
    if nargin < 1 || isempty(ax)
        ax = gca;
    end
    if nargin < 3
        display_name = '';
    end

    y_limits = ylim(ax);
    for k = 1:numel(events)
        x0 = events(k).start_t;
        x1 = events(k).end_t;
        handle_visibility = 'off';
        patch_name = '';
        if k == 1 && ~isempty(display_name)
            handle_visibility = 'on';
            patch_name = display_name;
        end
        h(end+1,1) = patch(ax, [x0 x1 x1 x0], ...
              [y_limits(1) y_limits(1) y_limits(2) y_limits(2)], ...
              [1.00 0.65 0.65], ...
              'EdgeColor','none', ...
              'FaceAlpha',0.45, ...
              'DisplayName', patch_name, ...
              'HandleVisibility', handle_visibility); %#ok<AGROW>
        try
            uistack(h(end), 'bottom');
        catch
        end
    end
end
