function pos = near_fullscreen_figure_position(margin_px)
% NEAR_FULLSCREEN_FIGURE_POSITION Perform the near fullscreen figure position operation.
%
% Syntax:
%   pos = near_fullscreen_figure_position(margin_px)
%
% Inputs:
%   margin_px - Input value `margin_px`.
%
% Outputs:
%   pos - Computed output value `pos`.

    if nargin < 1 || isempty(margin_px)
        margin_px = [60 110];
    end

    try
        screen = get(groot, 'ScreenSize');
    catch
        screen = get(0, 'ScreenSize');
    end

    if isempty(screen) || numel(screen) < 4 || any(~isfinite(screen(3:4))) || any(screen(3:4) <= 0)
        pos = [100 100 1600 850];
        return;
    end

    margin_px = max(0, round(margin_px(:)'));
    if numel(margin_px) == 1
        margin_px = [margin_px margin_px];
    else
        margin_px = margin_px(1:2);
    end

    margin_px(1) = min(margin_px(1), floor(0.10 * screen(3)));
    margin_px(2) = min(margin_px(2), floor(0.18 * screen(4)));

    pos = [
        screen(1) + margin_px(1), ...
        screen(2) + margin_px(2), ...
        max(1, screen(3) - 2 * margin_px(1)), ...
        max(1, screen(4) - 2 * margin_px(2))
    ];
end
