function [events, records, localized_support_events] = localize_confirmed_breath_events( ...
    candidate_events, belt, N, fs, event_type, criterion, lower, upper, ...
    analysis_window_sec, min_duration_sec, belt_name)
% LOCALIZE_CONFIRMED_BREATH_EVENTS Refine confirmed rate windows using breath IBIs.
% Candidate grid-window events are intersected with qualifying peak-to-peak
% respiratory-rate intervals. N/fs define recording bounds; lower/upper encode
% the rate criterion; analysis_window_sec supplies fallback uncertainty; and
% min_duration_sec filters final events. localized_support_events also retains
% rejected short runs, while records documents boundary provenance.

    events = empty_events();
    records = empty_boundary_records();
    localized_support_events = empty_events();
    if isempty(candidate_events)
        return;
    end

    [support_start, support_end, uncertainty, evidence_source, method] = ...
        breath_support_intervals(belt, criterion, lower, upper);

    for i = 1:numel(candidate_events)
        candidate = candidate_events(i);
        [run_starts, run_ends, run_uncertainties] = ...
            support_runs_inside_candidate( ...
            support_start, support_end, uncertainty, ...
            candidate.start_t, candidate.end_t);

        if isempty(run_starts)
            record = boundary_record_template();
            record.label = event_type;
            record.detector = event_type;
            record.belt = belt_name;
            record.boundary_method = 'no_defensible_localized_support';
            record.candidate_start_t = candidate.start_t;
            record.candidate_end_t = candidate.end_t;
            record.localized_duration_sec = 0;
            record.final_min_duration_sec = min_duration_sec;
            record.passes_final_min_duration = false;
            record.rejection_reason = 'no_localized_qualifying_support';
            record.uncertainty_sec = analysis_window_sec;
            record.evidence_source = 'confirmation_window_only';
            records(end+1,1) = record; %#ok<AGROW>
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
            record = boundary_record_template();
            record.label = event_type;
            record.detector = event_type;
            record.belt = belt_name;
            record.boundary_method = method;
            record.candidate_start_t = candidate.start_t;
            record.candidate_end_t = candidate.end_t;
            record.localized_start_t = localized.start_t;
            record.localized_end_t = localized.end_t;
            record.localized_duration_sec = localized.duration;
            record.final_min_duration_sec = min_duration_sec;
            record.passes_final_min_duration = passes;
            if ~passes
                record.rejection_reason = 'localized_duration_below_minimum';
            end
            record.uncertainty_sec = run_uncertainties(j);
            record.evidence_source = evidence_source;
            records(end+1,1) = record; %#ok<AGROW>
        end
    end
end

function [starts, ends, uncertainty, source, method] = ...
    breath_support_intervals(belt, criterion, lower, upper)
% BREATH_SUPPORT_INTERVALS Convert qualifying rate evidence to IBI intervals.
% starts/ends/uncertainty are seconds; source and method describe the selected
% breath-level RR evidence.

    starts = [];
    ends = [];
    uncertainty = [];
    source = '';
    method = '';
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
    source = 'breathwise_rr_bpm';
    method = 'confirmed_window_breath_interval_localization';

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

function records = empty_boundary_records()
% EMPTY_BOUNDARY_RECORDS Return a zero-length localized-boundary record array.

    records = boundary_record_template();
    records = records([]);
end

function record = boundary_record_template()
% BOUNDARY_RECORD_TEMPLATE Define localized respiratory-event provenance fields.
% Stores label/detector/belt/method/source, candidate and localized times (s),
% localized and required durations (s), pass/rejection status, and uncertainty (s).

    record = struct( ...
        'label', '', ...
        'detector', '', ...
        'belt', '', ...
        'boundary_method', '', ...
        'candidate_start_t', NaN, ...
        'candidate_end_t', NaN, ...
        'localized_start_t', NaN, ...
        'localized_end_t', NaN, ...
        'localized_duration_sec', NaN, ...
        'final_min_duration_sec', NaN, ...
        'passes_final_min_duration', false, ...
        'rejection_reason', '', ...
        'uncertainty_sec', NaN, ...
        'evidence_source', '');
end
