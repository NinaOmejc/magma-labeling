function shade_events_on_axis(events)
% Shade each event interval on current axes.
    y_limits = ylim;
    for k = 1:numel(events)
        x0 = events(k).start_t;
        x1 = events(k).end_t;
        patch([x0 x1 x1 x0], ...
              [y_limits(1) y_limits(1) y_limits(2) y_limits(2)], ...
              [1 0.8 0.8], 'EdgeColor','none', 'FaceAlpha',0.25);
    end
end