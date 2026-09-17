function intervals = periodic_analysis_support_intervals( ...
    retained_events, center_t, contributing_center_mask, ...
    window_sec, recording_end_t)
% PERIODIC_ANALYSIS_SUPPORT_INTERVALS Union windows used by retained events.
% The returned N-by-2 intervals are plotting diagnostics only. A contributing
% center is included only when it lies within a final retained event; its full
% centered analysis window is clipped to the recording bounds before merging.

    intervals = zeros(0, 2);
    center_t = center_t(:);
    contributing_center_mask = logical(contributing_center_mask(:));
    if isempty(retained_events) || isempty(center_t)
        return;
    end
    if numel(center_t) ~= numel(contributing_center_mask)
        error('MAGMA:PeriodicPlot:SupportAlignment', ...
            'Window centers and contributing-center mask must align.');
    end

    retained_center_mask = false(size(center_t));
    for i = 1:numel(retained_events)
        retained_center_mask = retained_center_mask | ...
            (center_t >= retained_events(i).start_t & ...
             center_t <= retained_events(i).end_t);
    end
    centers = center_t(contributing_center_mask & retained_center_mask & ...
        isfinite(center_t));
    if isempty(centers)
        return;
    end

    half_window_sec = window_sec / 2;
    intervals = [max(0, centers - half_window_sec), ...
        min(recording_end_t, centers + half_window_sec)];
    intervals = intervals(intervals(:, 2) >= intervals(:, 1), :);
    intervals = sortrows(intervals, 1);
    intervals = merge_overlapping_intervals(intervals);
end

function merged = merge_overlapping_intervals(intervals)
% MERGE_OVERLAPPING_INTERVALS Form a union without accumulated patch opacity.

    if isempty(intervals)
        merged = intervals;
        return;
    end
    merged = intervals(1, :);
    for i = 2:size(intervals, 1)
        if intervals(i, 1) <= merged(end, 2)
            merged(end, 2) = max(merged(end, 2), intervals(i, 2));
        else
            merged(end + 1, :) = intervals(i, :); %#ok<AGROW>
        end
    end
end
