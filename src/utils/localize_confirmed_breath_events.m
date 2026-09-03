function [events, records, localized_support_events] = localize_confirmed_breath_events( ...
    candidate_events, belt, N, fs, event_type, criterion, lower, upper, ...
    analysis_window_sec, min_duration_sec, belt_name)
% localize_confirmed_breath_events
% Refine already-confirmed candidate event boundaries using reviewed
% breath-level evidence. This function never decides whether an event
% exists. All disconnected localized qualifying runs are retained in QC
% records, and only runs meeting min_duration_sec become final events.
%
% Rate criteria use peak-to-peak intervals and breathwise rr_bpm. Amplitude
% criteria use midpoint cells around reviewed breaths and amp_ratio_session.

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

    starts = [];
    ends = [];
    uncertainty = [];
    source = '';
    method = '';
    if ~isstruct(belt) || ~isfield(belt, 'peak_t')
        return;
    end

    peak_t = belt.peak_t(:);
    switch criterion
        case {'rate_ge', 'rate_le'}
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
            else
                qualifies = valid & rr <= upper;
            end
            starts = peak_t(1:n);
            ends = peak_t(2:n+1);
            starts = starts(qualifies);
            ends = ends(qualifies);
            uncertainty = 0.5 * (ends - starts);
            source = 'reviewed_breathwise_rr_bpm';
            method = 'confirmed_window_breath_interval_localization';

        case {'amplitude_band', 'amplitude_ge', 'amplitude_le'}
            if ~isfield(belt, 'amp_ratio_session') || isempty(peak_t)
                return;
            end
            ratio = belt.amp_ratio_session(:);
            n = min(numel(peak_t), numel(ratio));
            peak_t = peak_t(1:n);
            ratio = ratio(1:n);
            valid = isfinite(peak_t) & isfinite(ratio);
            if strcmp(criterion, 'amplitude_band')
                qualifies = valid & ratio >= lower & ratio <= upper;
            elseif strcmp(criterion, 'amplitude_ge')
                qualifies = valid & ratio >= lower;
            else
                qualifies = valid & ratio <= upper;
            end
            [cell_start, cell_end] = breath_midpoint_cells(peak_t);
            starts = cell_start(qualifies);
            ends = cell_end(qualifies);
            uncertainty = 0.5 * (ends - starts);
            source = 'reviewed_breath_amplitude_ratio_session';
            method = 'confirmed_window_breath_midpoint_localization';
    end

    good = isfinite(starts) & isfinite(ends) & ends >= starts;
    starts = starts(good);
    ends = ends(good);
    uncertainty = uncertainty(good);
end

function [starts, ends] = breath_midpoint_cells(peak_t)
    peak_t = peak_t(:);
    starts = peak_t;
    ends = peak_t;
    if isscalar(peak_t)
        starts = peak_t - 0.5;
        ends = peak_t + 0.5;
        return;
    end
    midpoints = 0.5 * (peak_t(1:end-1) + peak_t(2:end));
    starts(2:end) = midpoints;
    ends(1:end-1) = midpoints;
    starts(1) = peak_t(1) - 0.5 * (peak_t(2) - peak_t(1));
    ends(end) = peak_t(end) + 0.5 * (peak_t(end) - peak_t(end-1));
end

function [run_starts, run_ends, run_uncertainties] = ...
    support_runs_inside_candidate(starts, ends, uncertainty, c0, c1)

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
    valid = ends >= starts;
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
    records = boundary_record_template();
    records = records([]);
end

function record = boundary_record_template()
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
