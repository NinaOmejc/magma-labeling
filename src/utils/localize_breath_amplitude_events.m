function [events, records, localized_support_events] = ...
    localize_breath_amplitude_events( ...
        belt, N, fs, event_type, criterion, lower, upper, ...
        min_duration_sec, belt_name)
% LOCALIZE_BREATH_AMPLITUDE_EVENTS Convert qualifying breaths directly to events.
% Internal peaks are tested using session-normalized amplitude, represented by
% their complete detected trough-to-trough cycles, and merged when those cycles
% touch. localized_support_events contains every merged run; events retains only
% runs meeting min_duration_sec. records preserves per-run boundary provenance
% with NaN candidate times because no rolling candidate stage is used.

    events = empty_events();
    records = empty_boundary_records();
    localized_support_events = empty_events();
    if isstruct(belt) && isfield(belt, 'session_amplitude_available') && ...
            ~belt.session_amplitude_available
        return;
    end

    [starts, ends] = qualifying_amplitude_cycles( ...
        belt, criterion, lower, upper);
    [run_starts, run_ends] = merge_touching_cycles(starts, ends);

    for i = 1:numel(run_starts)
        localized = event_from_times( ...
            run_starts(i), run_ends(i), N, fs, event_type);
        passes = localized.duration >= min_duration_sec;
        localized_support_events(end+1, 1) = localized; %#ok<AGROW>
        if passes
            events(end+1, 1) = localized; %#ok<AGROW>
        end

        record = boundary_record_template();
        record.label = event_type;
        record.detector = event_type;
        record.belt = belt_name;
        record.boundary_method = 'breathwise_amplitude_trough_localization';
        record.localized_start_t = localized.start_t;
        record.localized_end_t = localized.end_t;
        record.localized_duration_sec = localized.duration;
        record.final_min_duration_sec = min_duration_sec;
        record.passes_final_min_duration = passes;
        if ~passes
            record.rejection_reason = 'localized_duration_below_minimum';
        end
        record.uncertainty_sec = 0;
        record.evidence_source = 'breath_amplitude_ratio_session';
        records(end+1, 1) = record; %#ok<AGROW>
    end
end

function [starts, ends] = qualifying_amplitude_cycles( ...
    belt, criterion, lower, upper)
% QUALIFYING_AMPLITUDE_CYCLES Select complete internal breath cycles.
% starts/ends are detected trough times in seconds. criterion is
% 'amplitude_band' for lower <= ratio <= upper or 'amplitude_ge' for
% ratio >= lower.

    starts = [];
    ends = [];
    if ~isstruct(belt) || ~isfield(belt, 'peak_t') || ...
            ~isfield(belt, 'trough_t') || ...
            ~isfield(belt, 'amp_ratio_session')
        return;
    end

    peak_t = belt.peak_t(:);
    trough_t = belt.trough_t(:);
    ratio = belt.amp_ratio_session(:);
    if numel(peak_t) ~= numel(ratio)
        error('MAGMA:AmplitudeLocalization:SizeMismatch', ...
            'peak_t and amp_ratio_session must have equal lengths.');
    end
    if ~isempty(trough_t) && numel(trough_t) ~= max(numel(peak_t) - 1, 0)
        error('MAGMA:AmplitudeLocalization:TroughAlignment', ...
            'trough_t must have length numel(peak_t)-1.');
    end
    if numel(peak_t) < 3 || numel(trough_t) < 2
        return;
    end

    internal_peak_t = peak_t(2:end-1);
    internal_ratio = ratio(2:end-1);
    starts = trough_t(1:end-1);
    ends = trough_t(2:end);
    valid = isfinite(internal_peak_t) & isfinite(internal_ratio) & ...
        isfinite(starts) & isfinite(ends) & ...
        starts < internal_peak_t & internal_peak_t < ends;

    switch criterion
        case 'amplitude_band'
            qualifies = valid & internal_ratio >= lower & ...
                internal_ratio <= upper;
        case 'amplitude_ge'
            qualifies = valid & internal_ratio >= lower;
        otherwise
            error('MAGMA:AmplitudeLocalization:InvalidCriterion', ...
                'criterion must be ''amplitude_band'' or ''amplitude_ge''.');
    end

    starts = starts(qualifies);
    ends = ends(qualifies);
end

function [run_starts, run_ends] = merge_touching_cycles(starts, ends)
% MERGE_TOUCHING_CYCLES Merge overlapping or adjacent cycle intervals.

    run_starts = [];
    run_ends = [];
    if isempty(starts)
        return;
    end

    [starts, order] = sort(starts);
    ends = ends(order);
    group_start = starts(1);
    group_end = ends(1);
    tolerance = 1e-9;
    for i = 2:numel(starts)
        if starts(i) <= group_end + tolerance
            group_end = max(group_end, ends(i));
        else
            run_starts(end+1, 1) = group_start; %#ok<AGROW>
            run_ends(end+1, 1) = group_end; %#ok<AGROW>
            group_start = starts(i);
            group_end = ends(i);
        end
    end
    run_starts(end+1, 1) = group_start;
    run_ends(end+1, 1) = group_end;
end

function event = event_from_times(start_t, end_t, N, fs, event_type)
% EVENT_FROM_TIMES Clamp trough bounds and populate canonical event fields.

    recording_end_t = N / fs;
    start_t = max(0, min(recording_end_t, start_t));
    end_t = max(start_t, min(recording_end_t, end_t));
    start_idx = max(1, min(N, round(start_t * fs) + 1));
    end_idx = max(start_idx, min(N, round(end_t * fs)));
    event = struct( ...
        'type', event_type, ...
        'start_idx', start_idx, ...
        'end_idx', end_idx, ...
        'start_t', (start_idx - 1) / fs, ...
        'end_t', end_idx / fs, ...
        'duration', (end_idx - start_idx + 1) / fs);
end

function records = empty_boundary_records()
% EMPTY_BOUNDARY_RECORDS Return a zero-length localized-boundary record array.

    records = boundary_record_template();
    records = records([]);
end

function record = boundary_record_template()
% BOUNDARY_RECORD_TEMPLATE Define direct amplitude-event provenance fields.

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
