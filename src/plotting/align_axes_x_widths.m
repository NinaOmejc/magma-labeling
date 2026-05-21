function align_axes_x_widths(ax)
% align_axes_x_widths  Force axes plot boxes to share the same x-span.
%
% Legends placed eastoutside can shrink individual axes by different
% amounts. This helper aligns the plot boxes after legends are created.

    if nargin < 1 || isempty(ax)
        ax = findall(gcf, 'Type', 'axes');
    end

    ax = ax(isgraphics(ax, 'axes'));
    if isempty(ax)
        return;
    end

    is_legend = arrayfun(@(a) strcmp(a.Tag, 'legend'), ax);
    ax = ax(~is_legend);
    ax = ax(arrayfun(@is_positionable_axis, ax));
    if numel(ax) < 2
        return;
    end

    drawnow limitrate;

    original_units = cell(size(ax));
    for i = 1:numel(ax)
        original_units{i} = ax(i).Units;
        ax(i).Units = 'normalized';
    end

    pos = vertcat(ax.Position);
    left = max(pos(:, 1));
    right = min(pos(:, 1) + pos(:, 3));
    width = right - left;

    if ~isfinite(width) || width <= 0
        restore_units(ax, original_units);
        return;
    end

    for i = 1:numel(ax)
        p = ax(i).Position;
        p(1) = left;
        p(3) = width;
        ax(i).Position = p;
    end

    restore_units(ax, original_units);
end

function tf = is_positionable_axis(ax)
% Axes inside tiledlayout are positioned by the layout manager. Assigning
% Position on them creates repeated MATLAB warnings during batch plotting.
    tf = true;
    try
        tf = ~contains(class(ax.Parent), 'TiledChartLayout');
    catch
        tf = true;
    end
end

function restore_units(ax, units)
    for i = 1:numel(ax)
        if isgraphics(ax(i), 'axes')
            ax(i).Units = units{i};
        end
    end
end
