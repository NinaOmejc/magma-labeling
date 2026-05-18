function h = shade_events_on_axis(events, display_name)
% Shade each event interval on current axes.
    h = gobjects(0);
    if nargin < 2
        display_name = '';
    end

    y_limits = ylim;
    for k = 1:numel(events)
        x0 = events(k).start_t;
        x1 = events(k).end_t;
        handle_visibility = 'off';
        patch_name = '';
        if k == 1 && ~isempty(display_name)
            handle_visibility = 'on';
            patch_name = display_name;
        end
        h(end+1,1) = patch([x0 x1 x1 x0], ...
              [y_limits(1) y_limits(1) y_limits(2) y_limits(2)], ...
              [1 0.8 0.8], ...
              'EdgeColor','none', ...
              'FaceAlpha',0.25, ...
              'DisplayName', patch_name, ...
              'HandleVisibility', handle_visibility); %#ok<AGROW>
    end
end
