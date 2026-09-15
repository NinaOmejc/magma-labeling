function [events, candidates, localized_support_events] = localize_confirmed_breath_events( ...
    candidate_events, belt, N, fs, event_type, criterion, lower, upper, ...
    min_duration_sec, belt_name)
% LOCALIZE_CONFIRMED_BREATH_EVENTS Refine confirmed rate windows using breath IBIs.
% Candidate grid-window events are intersected with qualifying peak-to-peak
% respiratory-rate intervals. N/fs define recording bounds; lower/upper encode
% the rate criterion; analysis_window_sec supplies fallback uncertainty; and
% min_duration_sec filters final events. localized_support_events and compact
% candidates retain rejected short runs. Rolling candidates without a
% defensible localized interval do not create placeholder records.

    events = empty_events();
    candidates = empty_candidate_events();
    localized_support_events = empty_events();
    if isempty(candidate_events)
        return;
    end

    [support_start, support_end, uncertainty] = ...
        breath_support_intervals(belt, criterion, lower, upper);

    for i = 1:numel(candidate_events)
        candidate = candidate_events(i);
        [run_starts, run_ends, run_uncertainties] = ...
            support_runs_inside_candidate( ...
            support_start, support_end, uncertainty, ...
            candidate.start_t, candidate.end_t);

        if isempty(run_starts)
            continue;
        end

        for j = 1:numel(run_starts)
            localized = event_from_times(candidate, run_starts(j), run_ends(j), ...
                N, fs, event_type);
            passes = localized.duration >= min_duration_sec;
            localized_support_events(end+1,1) = localized; %#ok<AGROW>
            if passes
                events(end+1,1) = localized; %#ok<AGROW>
            end
            if passes
                reason = '';
            else
                reason = 'too_short';
            end
            candidates(end + 1, 1) = events_to_candidate_events( ...
                localized, belt_name, passes, reason, ...
                run_uncertainties(j)); %#ok<AGROW>
        end
    end
end

function [starts, ends, uncertainty] = ...
    breath_support_intervals(belt, criterion, lower, upper)
% BREATH_SUPPORT_INTERVALS Convert qualifying rate evidence to IBI intervals.
% starts/ends/uncertainty are seconds.

    starts = [];
    ends = [];
    uncertainty = [];
    if ~isstruct(belt) || ~isfield(belt, 'peak_t')
        return;
    end

    peak_t = belt.peak_t(:);
    if ~isfield(belt, 'rr_bpm') || numel(peak_t) < 2
        return;
    end
    rr = belt.rr_bpm(:);
    n = min(numel(rr), numel(peak_t) - 1);
    peak_t = peak_t(1:n+1);
    rr = rr(1:n);
    valid = isfinite(peak_t(1:n)) & isfinite(peak_t(2:n+1)) & ...
        peak_t(2:n+1) > peak_t(1:n) & isfinite(rr);
    if strcmp(criterion, 'rate_ge')
        qualifies = valid & rr >= lower;
    elseif strcmp(criterion, 'rate_le')
        qualifies = valid & rr <= upper;
    else
        error('MAGMA:BreathLocalization:InvalidRateCriterion', ...
            'criterion must be ''rate_ge'' or ''rate_le''.');
    end
    starts = peak_t(1:n);
    ends = peak_t(2:n+1);
    starts = starts(qualifies);
    ends = ends(qualifies);
    uncertainty = 0.5 * (ends - starts);

    good = isfinite(starts) & isfinite(ends) & ends > starts;
    starts = starts(good);
    ends = ends(good);
    uncertainty = uncertainty(good);
end

function [run_starts, run_ends, run_uncertainties] = ...
    support_runs_inside_candidate(starts, ends, uncertainty, c0, c1)
% SUPPORT_RUNS_INSIDE_CANDIDATE Clip, merge, and summarize support intervals.
% All bounds and uncertainties are seconds. Only intervals intersecting
% [c0,c1] remain; touching intervals merge and keep maximum uncertainty.

    run_starts = [];
    run_ends = [];
    run_uncertainties = [];
    if isempty(starts)
        return;
    end

    keep = ends > c0 & starts < c1;
    starts = max(starts(keep), c0);
    ends = min(ends(keep), c1);
    uncertainty = uncertainty(keep);
    valid = ends > starts;
    starts = starts(valid);
    ends = ends(valid);
    uncertainty = uncertainty(valid);
    if isempty(starts)
        return;
    end

    [starts, order] = sort(starts);
    ends = ends(order);
    uncertainty = uncertainty(order);
    group_start = starts(1);
    group_end = ends(1);
    group_uncertainty = uncertainty(1);
    tol = 1e-9;
    for i = 2:numel(starts)
        if starts(i) <= group_end + tol
            group_end = max(group_end, ends(i));
            group_uncertainty = max(group_uncertainty, uncertainty(i));
        else
            run_starts(end+1, 1) = group_start; %#ok<AGROW>
            run_ends(end+1, 1) = group_end; %#ok<AGROW>
            run_uncertainties(end+1, 1) = group_uncertainty; %#ok<AGROW>
            group_start = starts(i);
            group_end = ends(i);
            group_uncertainty = uncertainty(i);
        end
    end
    run_starts(end+1, 1) = group_start;
    run_ends(end+1, 1) = group_end;
    run_uncertainties(end+1, 1) = group_uncertainty;
end

function event = event_from_times(template, start_t, end_t, N, fs, event_type)
% EVENT_FROM_TIMES Clamp time bounds and populate canonical event fields.
% N/fs define the recording; template preserves any additional fields.

    recording_end_t = N / fs;
    start_t = max(0, min(recording_end_t, start_t));
    end_t = max(start_t, min(recording_end_t, end_t));
    event = template;
    event.type = event_type;
    event.start_idx = max(1, min(N, round(start_t * fs) + 1));
    event.end_idx = max(event.start_idx, min(N, round(end_t * fs)));
    event.start_t = (event.start_idx - 1) / fs;
    event.end_t = event.end_idx / fs;
    event.duration = (event.end_idx - event.start_idx + 1) / fs;
end
