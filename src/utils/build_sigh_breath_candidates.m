function [events, peak_t, panel_peaks] = build_sigh_breath_candidates(resp_cycles, N, fs)
% BUILD_SIGH_BREATH_CANDIDATES Pair corresponding belt peaks into discrete breaths.

    events = normalize_review_events(empty_events(), fs);
    peak_t = zeros(0, 1);
    panel_peaks = nan(0, 2);
    belt_names = {'lungs', 'diaph'};
    for i = 1:numel(belt_names)
        name = belt_names{i};
        if ~isstruct(resp_cycles) || ~isfield(resp_cycles, name) || ...
                ~isfield(resp_cycles.(name), 'peak_t')
            continue;
        end
        belt = resp_cycles.(name);
        if isfield(belt, 'available') && ~belt.available
            continue;
        end
        belt_peaks = belt.peak_t(:);
        valid = isfinite(belt_peaks) & belt_peaks >= 0 & ...
            belt_peaks <= (N - 1) / fs;
        if isfield(belt, 'amp') && numel(belt.amp) == numel(belt_peaks)
            amplitude = belt.amp(:);
            valid = valid & isfinite(amplitude) & amplitude > 0;
        end
        belt_peaks = belt_peaks(valid);
        belt_peaks = unique(sort(belt_peaks));
        [belt_events, belt_centers] = midpoint_breath_events( ...
            belt_peaks, N, fs);
        for j = 1:numel(belt_events), belt_events(j).belt = name; end
        events = [events; belt_events]; %#ok<AGROW>
        peak_t = [peak_t; belt_centers]; %#ok<AGROW>
        points = nan(numel(belt_centers), 2); points(:, i) = belt_centers;
        panel_peaks = [panel_peaks; points]; %#ok<AGROW>
    end
    if isempty(peak_t)
        return;
    end
    keep = true(numel(events), 1);
    lungs = find(isfinite(panel_peaks(:, 1)));
    diaph = find(isfinite(panel_peaks(:, 2)));
    paired = false(numel(lungs), 1);
    for d = reshape(diaph, 1, [])
        if isempty(lungs), break; end
        [distance, l] = min(abs(peak_t(lungs) - peak_t(d)));
        [~, nearest_d] = min(abs(peak_t(diaph) - peak_t(lungs(l))));
        span = min(events(lungs(l)).duration, events(d).duration);
        % Mutual nearest peaks within less than half a breath form one identity.
        if ~paired(l) && diaph(nearest_d) == d && distance <= max(1/fs, 0.45*span)
            panel_peaks(lungs(l), 2) = peak_t(d);
            events(lungs(l)).belt = 'both';
            paired(l) = true;
            keep(d) = false;
        end
    end
    events = events(keep); peak_t = peak_t(keep); panel_peaks = panel_peaks(keep, :);
    for i = 1:numel(events)
        source = events(i).belt;
        events(i) = make_event('sigh', peak_t(i), peak_t(i), N, fs);
        events(i).belt = source;
    end
    [peak_t, order] = sort(peak_t);
    events = events(order);
    panel_peaks = panel_peaks(order, :);
end

function [events, centers] = midpoint_breath_events(peak_t, N, fs)
% MIDPOINT_BREATH_EVENTS Bound each breath halfway to neighboring peaks.

    centers = peak_t(:);
    events = normalize_review_events(empty_events(), fs);
    if isempty(centers)
        return;
    end
    events = repmat(make_event('sigh', 0, 0, N, fs), numel(centers), 1);
    for i = 1:numel(centers)
        if i == 1
            if numel(centers) > 1
                start_t = max(0, centers(i) - 0.5 * (centers(i + 1) - centers(i)));
            else
                start_t = max(0, centers(i) - 0.5);
            end
        else
            start_t = 0.5 * (centers(i - 1) + centers(i));
        end
        if i == numel(centers)
            if numel(centers) > 1
                end_t = min(N / fs, centers(i) + 0.5 * (centers(i) - centers(i - 1)));
            else
                end_t = min(N / fs, centers(i) + 0.5);
            end
        else
            end_t = 0.5 * (centers(i) + centers(i + 1));
        end
        events(i) = make_event('sigh', start_t, end_t, N, fs);
    end
end

function event = make_event(type,t0,t1,N,fs)
% Canonical sample bounds are compatibility wrappers for point sigh identities.
    first = max(1,min(N,round(t0*fs)+1));
    last = max(first,min(N,round(t1*fs)));
    event = normalize_event_types_and_meta(struct('type',type, ...
        'start_idx',first,'end_idx',last),fs);
end
