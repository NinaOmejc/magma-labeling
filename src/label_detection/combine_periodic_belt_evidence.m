function combined = combine_periodic_belt_evidence( ...
    t_sec, lungs_evaluable, lungs_positive, diaph_evaluable, ...
    diaph_positive, min_duration_sec, N, fs)
% COMBINE_PERIODIC_BELT_EVIDENCE Apply MAGMA's dynamic two-belt AND rule.
% At each supported time both evaluable belts must be positive; when only one
% belt is evaluable, that belt determines the result. The rule is a MAGMA
% design choice rather than part of either cited periodic-breathing method.

    t_sec = t_sec(:);
    lungs_evaluable = logical(lungs_evaluable(:));
    lungs_positive = logical(lungs_positive(:));
    diaph_evaluable = logical(diaph_evaluable(:));
    diaph_positive = logical(diaph_positive(:));
    expected_size = size(t_sec);
    inputs = {lungs_evaluable, lungs_positive, ...
        diaph_evaluable, diaph_positive};
    if any(cellfun(@(x) ~isequal(size(x), expected_size), inputs))
        error('MAGMA:CSR:BeltEvidenceSizeMismatch', ...
            'Periodic-breathing belt masks must align one-to-one with t_sec.');
    end

    both = lungs_evaluable & diaph_evaluable;
    evaluable = lungs_evaluable | diaph_evaluable;
    positive = ...
        (both & lungs_positive & diaph_positive) | ...
        (lungs_evaluable & ~diaph_evaluable & lungs_positive) | ...
        (~lungs_evaluable & diaph_evaluable & diaph_positive);
    positive = positive & evaluable;

    [events, candidate_mask, candidate_events] = ...
        sustained_periodic_mask_to_events( ...
        positive, t_sec, min_duration_sec, N, fs);
    combined = struct( ...
        'available', any(evaluable), ...
        't_sec', t_sec, ...
        'evaluable_mask', evaluable, ...
        'positive_mask', positive, ...
        'candidate_mask', candidate_mask, ...
        'candidate_events', candidate_events, ...
        'events', events);
end

function [events, retained_mask, candidates] = sustained_periodic_mask_to_events( ...
    mask, t_sec, min_duration_sec, N, fs)
% SUSTAINED_PERIODIC_MASK_TO_EVENTS Retain center-supported runs by duration.
% Each regularly spaced estimate represents support halfway to neighboring
% estimates. Bounds are clamped to the recording and converted to canonical
% inclusive sample indices and half-open times.

    events = empty_events();
    candidates = empty_candidate_events();
    retained_mask = false(size(mask));
    if isempty(mask)
        return;
    end
    if ~isscalar(min_duration_sec) || ~isfinite(min_duration_sec) || ...
            min_duration_sec <= 0
        error('MAGMA:CSR:InvalidMinimumDuration', ...
            'Periodic-breathing minimum duration must be positive.');
    end
    if numel(t_sec) > 1
        dt = median(diff(t_sec), 'omitnan');
    else
        dt = 1;
    end
    if ~isfinite(dt) || dt <= 0 || ...
            any(diff(t_sec) <= 0)
        error('MAGMA:CSR:InvalidTimeGrid', ...
            'Periodic-breathing diagnostic times must increase strictly.');
    end

    edges = diff([false; mask(:); false]);
    starts = find(edges == 1);
    stops = find(edges == -1) - 1;
    recording_end_t = N / fs;
    event_template = struct( ...
        'type', '', 'start_idx', 0, 'end_idx', 0, ...
        'start_t', 0, 'end_t', 0, 'duration', 0);
    events = repmat(event_template, numel(starts), 1);
    event_count = 0;
    for i = 1:numel(starts)
        start_t = max(0, t_sec(starts(i)) - 0.5 * dt);
        end_t = min(recording_end_t, t_sec(stops(i)) + 0.5 * dt);
        start_idx = max(1, min(N, round(start_t * fs) + 1));
        end_idx = max(start_idx, min(N, round(end_t * fs)));
        event = struct( ...
            'type', 'csr', ...
            'start_idx', start_idx, ...
            'end_idx', end_idx, ...
            'start_t', (start_idx - 1) / fs, ...
            'end_t', end_idx / fs, ...
            'duration', (end_idx - start_idx + 1) / fs);
        passes = end_t - start_t >= min_duration_sec;
        if passes
            reason = '';
        else
            reason = 'too_short';
        end
        candidates(end + 1, 1) = events_to_candidate_events( ...
            event, 'combined', passes, reason, 0.5 * dt); %#ok<AGROW>
        if ~passes
            continue;
        end
        retained_mask(starts(i):stops(i)) = true;
        event_count = event_count + 1;
        events(event_count, 1) = event;
    end
    if event_count == 0
        events = empty_events();
    else
        events = events(1:event_count);
    end
end
