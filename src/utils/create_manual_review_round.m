function [final_event_sets, review_round] = create_manual_review_round( ...
    source_event_sets, edited_event_sets, review_coverage_mask, config, metadata)
% CREATE_MANUAL_REVIEW_ROUND Replace labels only inside explicit review coverage.
% source_event_sets and edited_event_sets are structs keyed by editable label;
% review_coverage_mask is Nsample-by-Neditable-label; config supplies canonical
% label order and fs. final_event_sets preserves source labels outside coverage.
% review_round fields include round/timestamp/reviewer/source analysis metadata; canonical
% events and mask; full-label review_mask/status; changed_labels; notes; schema
% version; and accepted_as_active.

    defs = manual_label_definitions();
    label_names = {config.labels.short};
    if ~isequal(label_names, get_labels('short'))
        error('MAGMA:ManualReview:CanonicalLabels', ...
            'Manual review requires the frozen 11-label order.');
    end
    if ~islogical(review_coverage_mask) || ...
            size(review_coverage_mask, 2) ~= numel(defs)
        error('MAGMA:ManualReview:CoverageAlignment', ...
            'review_coverage_mask must be a logical N-by-%d matrix.', numel(defs));
    end

    N = size(review_coverage_mask, 1);
    source_mask = event_sets_to_mask(source_event_sets, defs, N, config);
    edited_mask = event_sets_to_mask(edited_event_sets, defs, N, config);
    round_review_mask = false(N, numel(label_names));
    for i = 1:numel(defs)
        label_index = find(strcmp(label_names, defs(i).type), 1);
        round_review_mask(:, label_index) = review_coverage_mask(:, i);
    end

    final_mask = source_mask;
    final_mask(round_review_mask) = edited_mask(round_review_mask);
    final_events = label_mask_to_events(final_mask, label_names, config.fs);
    % Sighs are whole breath identities, selected by peak coverage. Never
    % reconstruct their count from connected positive samples in a mask.
    sigh_index = find(strcmp(label_names, 'sigh'), 1);
    sigh_scope = round_review_mask(:, sigh_index);
    sigh_events = compose_sigh_events(source_event_sets, edited_event_sets, ...
        sigh_scope, N, config.fs);
    final_events = final_events(~strcmp({final_events.type}, 'sigh'));
    final_events = normalize_review_events({final_events, sigh_events}, config.fs);
    sigh_mask = events_to_time_mask(sigh_events, N, config);
    final_mask(:, sigh_index) = sigh_mask(:, sigh_index);
    final_event_sets = events_to_event_sets(final_events, defs);

    review_status = repmat({'unreviewed'}, 1, numel(label_names));
    changed_labels = {};
    for i = 1:numel(defs)
        label_index = find(strcmp(label_names, defs(i).type), 1);
        scope = round_review_mask(:, label_index);
        if ~any(scope)
            continue;
        end
        before = source_mask(scope, label_index);
        after = final_mask(scope, label_index);
        if isequal(before, after)
            review_status{label_index} = 'reviewed_accepted';
        else
            changed_labels{end+1} = defs(i).type; %#ok<AGROW>
            if any(before) && ~any(after)
                review_status{label_index} = 'reviewed_rejected';
            else
                review_status{label_index} = 'reviewed_edited';
            end
        end
    end

    metadata = normalize_metadata(metadata);
    review_round = struct( ...
        'round_id', metadata.round_id, ...
        'timestamp', metadata.timestamp, ...
        'reviewer_role', metadata.reviewer_role, ...
        'start_from', metadata.start_from, ...
        'source_review_round', metadata.source_review_round, ...
        'source_analysis_id', metadata.source_analysis_id, ...
        'events', {final_events}, ...
        'mask', logical(final_mask), ...
        'review_mask', logical(round_review_mask), ...
        'review_status', {review_status}, ...
        'changed_labels', {changed_labels}, ...
        'reviewer_id', metadata.reviewer_id, ...
        'notes', metadata.notes, ...
        'schema_version', 'manual_review_round_v1', ...
        'accepted_as_active', true);
end

function mask = event_sets_to_mask(event_sets, defs, N, config)
% EVENT_SETS_TO_MASK Normalize editable event fields into a canonical sample mask.

    parts = cell(1, numel(defs));
    for i = 1:numel(defs)
        parts{i} = normalize_review_events(empty_events(), config.fs);
        if isstruct(event_sets) && isfield(event_sets, defs(i).field) && ...
                ~isempty(event_sets.(defs(i).field))
            events = event_sets.(defs(i).field);
            for j = 1:numel(events)
                events(j).type = defs(i).type;
            end
            parts{i} = normalize_review_events(events, config.fs);
        end
    end
    events = normalize_review_events(parts, config.fs);
    mask = events_to_time_mask(events, N, config);
end

function events = compose_sigh_events(source, edited, scope, N, fs)
    before = sigh_events(source, fs);
    after = sigh_events(edited, fs);
    keep_before = ~peak_is_reviewed(before, scope, N);
    keep_after = peak_is_reviewed(after, scope, N);
    events = normalize_review_events({before(keep_before), after(keep_after)}, fs);
end

function events = sigh_events(sets, fs)
    events = normalize_review_events(empty_events(), fs);
    if isfield(sets, 'sigh'), events = normalize_review_events(sets.sigh, fs); end
end

function reviewed = peak_is_reviewed(events, scope, N)
    reviewed = false(numel(events), 1);
    for i = 1:numel(events)
        % New point events store the peak in start_idx=end_idx. Legacy breath
        % intervals retain their previous midpoint-based coverage convention.
        peak = round((events(i).start_idx + events(i).end_idx)/2);
        if peak >= 1 && peak <= N, reviewed(i) = scope(peak); end
    end
end

function event_sets = events_to_event_sets(events, defs)
% EVENTS_TO_EVENT_SETS Split canonical events into fields defined by defs.

    event_sets = struct();
    for i = 1:numel(defs)
        if isempty(events)
            event_sets.(defs(i).field) = empty_events();
        else
            keep = strcmp({events.type}, defs(i).type);
            event_sets.(defs(i).field) = events(keep);
        end
    end
end

function metadata = normalize_metadata(metadata)
% NORMALIZE_METADATA Fill and validate manual-review round metadata.
% Fields are round_id, timestamp, reviewer_role, start_from, source_review_round,
% source_analysis_id, reviewer_id, and notes.

    if nargin < 1 || isempty(metadata), metadata = struct(); end
    metadata = with_default(metadata, 'round_id', 1);
    metadata = with_default(metadata, 'timestamp', current_timestamp());
    metadata = with_default(metadata, 'reviewer_role', 'researcher');
    metadata = with_default(metadata, 'start_from', 'automatic');
    metadata = with_default(metadata, 'source_review_round', NaN);
    metadata = with_default(metadata, 'source_analysis_id', 'unknown');
    metadata = with_default(metadata, 'reviewer_id', '');
    metadata = with_default(metadata, 'notes', '');

    if ~isnumeric(metadata.round_id) || ~isscalar(metadata.round_id) || ...
            ~isfinite(metadata.round_id) || metadata.round_id < 1 || ...
            metadata.round_id ~= round(metadata.round_id)
        error('MAGMA:ManualReview:RoundId', 'round_id must be a positive integer.');
    end
    metadata.timestamp = char(string(metadata.timestamp));
    metadata.reviewer_role = char(string(metadata.reviewer_role));
    metadata.start_from = validatestring(char(string(metadata.start_from)), ...
        {'automatic', 'latest_reviewed'});
    metadata.source_analysis_id = char(string(metadata.source_analysis_id));
    metadata.reviewer_id = char(string(metadata.reviewer_id));
    metadata.notes = char(string(metadata.notes));
end

function value = current_timestamp()
% CURRENT_TIMESTAMP Return local wall-clock time as yyyy-MM-dd HH:mm:ss text.

    value = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
end

function source = with_default(source, field, value)
% WITH_DEFAULT Set a struct field only when absent or empty.

    if ~isfield(source, field) || isempty(source.(field))
        source.(field) = value;
    end
end
