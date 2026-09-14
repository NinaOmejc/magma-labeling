function h = shade_session_reference_on_axis(ax, session_reference, display_name)
% SHADE_SESSION_REFERENCE_ON_AXIS Shade the common physiological reference interval.
%
% Inputs:
%   ax                - Target axes handle, or empty for the current axes.
%   session_reference - Struct with available plus reference_start_t and
%                       reference_end_t boundaries in seconds.
%   display_name      - Optional legend text for the shaded interval.
%
% Outputs:
%   h - Patch handle, or an empty graphics vector when no interval is valid.

    h = gobjects(0);
    if nargin < 1 || isempty(ax)
        ax = gca;
    end
    if nargin < 3 || isempty(display_name)
        display_name = 'session reference interval';
    end
    if isempty(session_reference) || ~isstruct(session_reference) || ...
            ~isfield(session_reference, 'available') || ~session_reference.available
        return;
    end

    start_t = session_reference.reference_start_t;
    end_t = session_reference.reference_end_t;
    if ~isfinite(start_t) || ~isfinite(end_t) || end_t <= start_t
        return;
    end

    y_limits = ylim(ax);
    h = patch(ax, [start_t end_t end_t start_t], ...
        [y_limits(1) y_limits(1) y_limits(2) y_limits(2)], ...
        [0.80 0.88 1.00], 'EdgeColor', 'none', 'FaceAlpha', 0.25, ...
        'DisplayName', display_name);
    try
        uistack(h, 'bottom');
    catch
        % Older graphics backends may not support uistack for this handle.
    end
end
