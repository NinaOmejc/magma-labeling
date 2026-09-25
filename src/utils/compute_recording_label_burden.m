function summary = compute_recording_label_burden( ...
    mask, label_names, label_available, events, fs, assessable_mask)
% COMPUTE_RECORDING_LABEL_BURDEN Summarize duration, fraction, and count per label.
% mask and assessable_mask are Nsample-by-Nlabel; availability and names align
% with columns; events are canonical and fs is hertz. summary fields are version,
% recording_duration_sec, by_label entries (available, duration_sec, fraction,
% event_count, assessable_duration_sec, and event-duration summaries), plus
% compact sigh timing/rate summaries derived from canonical sigh events.
% Event summaries include only events whose midpoint is assessable for the
% corresponding annotation layer.

    label_names = cellstr(string(label_names));
    label_available = logical(label_available(:)');
    if size(mask, 2) ~= numel(label_names) || ...
            numel(label_available) ~= numel(label_names)
        error('MAGMA:Burden:LabelAlignment', ...
            'mask, label_names, and label_available must align.');
    end
    if nargin < 6 || isempty(assessable_mask)
        assessable_mask = repmat(label_available, size(mask, 1), 1);
    end
    if ~isequal(size(assessable_mask), size(mask))
        error('MAGMA:Burden:AssessableMaskSize', ...
            'assessable_mask must have the same size as mask.');
    end
    assessable_mask = logical(assessable_mask);

    summary = struct();
    summary.version = 'recording_label_burden_v3';
    summary.recording_duration_sec = size(mask, 1) / fs;
    summary.by_label = struct();

    for i = 1:numel(label_names)
        name = label_names{i};
        available = label_available(i) && any(assessable_mask(:, i));
        entry = struct('available', available, 'duration_sec', NaN, ...
            'fraction', NaN, 'event_count', NaN, ...
            'assessable_duration_sec', NaN, ...
            'median_event_duration_sec', NaN, ...
            'max_event_duration_sec', NaN, ...
            'missing_reason', 'detector_unavailable');
        if available
            valid = assessable_mask(:, i);
            labeled = logical(mask(:, i)) & valid;
            entry.missing_reason = '';
            entry.duration_sec = nnz(labeled) / fs;
            entry.assessable_duration_sec = nnz(valid) / fs;
            entry.fraction = nnz(labeled) / nnz(valid);
            [entry.event_count, event_duration_sec] = ...
                event_duration_summary(events, name, fs, valid);
            entry.median_event_duration_sec = finite_median(event_duration_sec);
            entry.max_event_duration_sec = finite_max(event_duration_sec);
        end
        summary.by_label.(name) = entry;
    end

    sigh = summary.by_label.sigh;
    summary.sigh_count = sigh.event_count;
    summary.sighs_per_15_min = NaN;
    summary.max_sighs_in_any_15_min_window = NaN;
    summary.max_sighs_in_any_15_min_window_available = false;
    summary.max_sighs_in_any_15_min_window_missing_reason = ...
        'sigh_detector_unavailable';
    summary.median_inter_sigh_interval_sec = NaN;
    summary.minimum_inter_sigh_interval_sec = NaN;
    if sigh.available && sigh.assessable_duration_sec > 0
        summary.sighs_per_15_min = ...
            sigh.event_count / (sigh.assessable_duration_sec / (15 * 60));
        sigh_index = find(strcmp(label_names, 'sigh'), 1);
        sigh_scope = assessable_mask(:, sigh_index);
        sigh_t = event_start_times(events, 'sigh', fs, sigh_scope);
        [summary.max_sighs_in_any_15_min_window, max_available] = ...
            maximum_events_in_assessable_window( ...
                sigh_t, sigh_scope, fs, 15 * 60);
        summary.max_sighs_in_any_15_min_window_available = max_available;
        if max_available
            summary.max_sighs_in_any_15_min_window_missing_reason = '';
        else
            summary.max_sighs_in_any_15_min_window_missing_reason = ...
                'insufficient_continuous_assessable_15_min_interval';
        end
        inter_sigh_sec = diff(sort(sigh_t));
        summary.median_inter_sigh_interval_sec = finite_median(inter_sigh_sec);
        summary.minimum_inter_sigh_interval_sec = finite_min(inter_sigh_sec);
    end
end

function [count, durations] = event_duration_summary( ...
    events, label, fs, assessable_mask)
% EVENT_DURATION_SUMMARY Count one label and return finite canonical durations.

    durations = zeros(0, 1);
    selected = select_label_events(events, label);
    selected = events_with_assessable_midpoint( ...
        selected, assessable_mask, fs);
    count = numel(selected);
    if isempty(selected)
        return;
    end
    durations = nan(count, 1);
    for i = 1:count
        if isfield(selected, 'duration') && ...
                isfinite(selected(i).duration) && selected(i).duration >= 0
            durations(i) = selected(i).duration;
        elseif isfield(selected, 'start_idx') && isfield(selected, 'end_idx') && ...
                isfinite(selected(i).start_idx) && isfinite(selected(i).end_idx)
            durations(i) = max(0, ...
                (selected(i).end_idx - selected(i).start_idx + 1) / fs);
        end
    end
    durations = durations(isfinite(durations));
end

function times = event_start_times(events, label, fs, assessable_mask)
% EVENT_START_TIMES Return sorted canonical event starts in seconds.

    selected = select_label_events(events, label);
    selected = events_with_assessable_midpoint( ...
        selected, assessable_mask, fs);
    times = nan(numel(selected), 1);
    for i = 1:numel(selected)
        if isfield(selected, 'start_t') && isfinite(selected(i).start_t)
            times(i) = selected(i).start_t;
        elseif isfield(selected, 'start_idx') && isfinite(selected(i).start_idx)
            times(i) = (selected(i).start_idx - 1) / fs;
        end
    end
    times = sort(times(isfinite(times)));
end

function selected = select_label_events(events, label)
% SELECT_LABEL_EVENTS Select canonical/legacy aliases belonging to one label.

    selected = empty_events();
    if isempty(events) || ~isfield(events, 'type')
        return;
    end
    types = canonicalize_label_names({events.type});
    selected = events(strcmp(types, label));
end

function selected = events_with_assessable_midpoint(events, assessable_mask, fs)
% EVENTS_WITH_ASSESSABLE_MIDPOINT Restrict event summaries to layer scope.

    selected = events([]);
    N = numel(assessable_mask);
    for i = 1:numel(events)
        index = event_midpoint_index(events(i), fs, N);
        if isfinite(index) && assessable_mask(index)
            selected(end + 1) = events(i); %#ok<AGROW>
        end
    end
end

function index = event_midpoint_index(event, fs, N)
% EVENT_MIDPOINT_INDEX Convert canonical event coordinates to a sample index.

    index = NaN;
    if isfield(event, 'start_idx') && isfield(event, 'end_idx') && ...
            isfinite(event.start_idx) && isfinite(event.end_idx)
        index = round((double(event.start_idx) + double(event.end_idx)) / 2);
    elseif isfield(event, 'start_t') && isfield(event, 'end_t') && ...
            isfinite(event.start_t) && isfinite(event.end_t)
        index = round(((double(event.start_t) + double(event.end_t)) / 2) * fs) + 1;
    end
    if ~isfinite(index) || index < 1 || index > N
        index = NaN;
    end
end

function [count, available] = maximum_events_in_assessable_window( ...
    times, assessable_mask, fs, window_sec)
% MAXIMUM_EVENTS_IN_ASSESSABLE_WINDOW Require a continuous valid window.
% Unreviewed gaps therefore cannot be interpreted as reviewed negatives.

    count = NaN;
    available = false;
    padded = [false; logical(assessable_mask(:)); false];
    transitions = diff(padded);
    starts = find(transitions == 1);
    stops = find(transitions == -1) - 1;
    run_duration = (stops - starts + 1) / fs;
    eligible = find(run_duration >= window_sec);
    if isempty(eligible)
        return;
    end
    available = true;
    count = 0;
    for k = reshape(eligible, 1, [])
        run_start_sec = (starts(k) - 1) / fs;
        run_end_sec = stops(k) / fs;
        run_times = sort(times(times >= run_start_sec & times <= run_end_sec));
        if isempty(run_times)
            continue;
        end
        left = 1;
        for right = 1:numel(run_times)
            while run_times(right) - run_times(left) > window_sec
                left = left + 1;
            end
            count = max(count, right - left + 1);
        end
    end
end

function value = finite_median(values)
% FINITE_MEDIAN Return NaN for an empty finite subset.

    values = values(isfinite(values));
    if isempty(values), value = NaN; else, value = median(values); end
end

function value = finite_min(values)
% FINITE_MIN Return NaN for an empty finite subset.

    values = values(isfinite(values));
    if isempty(values), value = NaN; else, value = min(values); end
end

function value = finite_max(values)
% FINITE_MAX Return NaN for an empty finite subset.

    values = values(isfinite(values));
    if isempty(values), value = NaN; else, value = max(values); end
end
