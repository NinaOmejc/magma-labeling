function h = shade_static_baseline_on_axis(ax, baseline, display_name)
% shade_static_baseline_on_axis
% Shade the static baseline interval stored by compute_baseline.

    h = gobjects(0);

    if nargin < 1 || isempty(ax)
        ax = gca;
    end
    if nargin < 3 || isempty(display_name)
        display_name = 'baseline window';
    end

    if isempty(baseline) || ~isstruct(baseline)
        return;
    end

    if isfield(baseline, 'SpO2_baseline_start_t') && isfield(baseline, 'SpO2_baseline_end_t')
        start_t = baseline.SpO2_baseline_start_t;
        end_t = baseline.SpO2_baseline_end_t;
    elseif isfield(baseline, 'static_baseline_start_t') && isfield(baseline, 'static_baseline_end_t')
        start_t = baseline.static_baseline_start_t;
        end_t = baseline.static_baseline_end_t;
    else
        return;
    end

    if ~isfinite(start_t) || ~isfinite(end_t) || end_t <= start_t
        return;
    end

    y_limits = ylim(ax);
    h = patch(ax, [start_t end_t end_t start_t], ...
              [y_limits(1) y_limits(1) y_limits(2) y_limits(2)], ...
              [0.80 0.88 1.00], ...
              'EdgeColor', 'none', ...
              'FaceAlpha', 0.25, ...
              'DisplayName', display_name);

    try
        uistack(h, 'bottom');
    catch
        % Older graphics backends may not support uistack for this handle.
    end
end
