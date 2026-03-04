function shade_mask_on_axis(t_grid, mask)
% Shades regions where mask == true

    ax = gca;
    y_limits = ylim;

    d = diff([false; mask(:); false]);
    starts = find(d == 1);
    ends   = find(d == -1) - 1;

    for i = 1:numel(starts)
        x0 = t_grid(starts(i));
        x1 = t_grid(ends(i));

        patch([x0 x1 x1 x0], ...
              [y_limits(1) y_limits(1) y_limits(2) y_limits(2)], ...
              [1 0.8 0.8], ...   % light red
              'EdgeColor','none', ...
              'FaceAlpha',0.3);
    end
end
