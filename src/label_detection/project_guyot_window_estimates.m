function [evaluable_time, pathological_time] = project_guyot_window_estimates( ...
    t_sec, center_t, evaluable_window, pathological_window)
% PROJECT_GUYOT_WINDOW_ESTIMATES Map centered decisions to nearest-center time.
% Each h/f_m estimate represents the interval halfway to its neighboring
% window centers. Support is limited to the first and last center: a positive
% estimate is deliberately not back-projected over the full 120-s window.

    evaluable_time = false(size(t_sec));
    pathological_time = false(size(t_sec));
    if isempty(center_t)
        return;
    end
    supported = t_sec >= center_t(1) & t_sec <= center_t(end);
    if isscalar(center_t)
        [~, index] = min(abs(t_sec - center_t));
        evaluable_time(index) = evaluable_window;
        pathological_time(index) = pathological_window & evaluable_window;
        return;
    end
    evaluable_time(supported) = interp1( ...
        center_t, double(evaluable_window), t_sec(supported), 'nearest') > 0.5;
    pathological_time(supported) = interp1( ...
        center_t, double(pathological_window), t_sec(supported), 'nearest') > 0.5;
    pathological_time = pathological_time & evaluable_time;
end
