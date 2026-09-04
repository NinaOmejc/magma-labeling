function annotations = assemble_annotation_layers( ...
    automatic_event_sets, reviewed_event_sets, manual_edit_info, sigh_review, N, config)
% ASSEMBLE_ANNOTATION_LAYERS Perform the assemble annotation layers operation.
%
% Syntax:
%   annotations = assemble_annotation_layers(automatic_event_sets, reviewed_event_sets, manual_edit_info, sigh_review, N, config)
%
% Inputs:
%   automatic_event_sets - Input value `automatic_event_sets`.
%   reviewed_event_sets - Input value `reviewed_event_sets`.
%   manual_edit_info - Input value `manual_edit_info`.
%   sigh_review - Input value `sigh_review`.
%   N - Number of samples.
%   config - Pipeline configuration structure.
%
% Outputs:
%   annotations - Computed output value `annotations`.

    defs = manual_label_definitions();
    label_names = {config.labels.short};
    validate_label_order(label_names);

    automatic_parts = cell(1, numel(defs) + 1);
    for i = 1:numel(defs)
        automatic_parts{i} = field_events(automatic_event_sets, defs(i).field);
    end
    automatic_parts{end} = field_events(sigh_review, 'automatic_events');
    events_automatic = normalize_event_types_and_meta(merge_events(automatic_parts), config.fs);
    [mask_automatic, mask_names] = events_to_time_mask(events_automatic, N, config);
    if ~isequal(mask_names, label_names)
        error('MAGMA:Annotations:LabelOrder', ...
            'Automatic mask columns do not match the canonical label order.');
    end

    reviewed_fields = {};
    if isstruct(manual_edit_info) && isfield(manual_edit_info, 'reviewed_fields')
        reviewed_fields = cellstr(string(manual_edit_info.reviewed_fields));
    end
    has_generic_review = ~isempty(reviewed_fields);
    if isstruct(manual_edit_info) && isfield(manual_edit_info, ...
            'review_provenance') && ...
            isfield(manual_edit_info.review_provenance, 'latest_round_id')
        has_generic_review = has_generic_review || ...
            isfinite(manual_edit_info.review_provenance.latest_round_id);
    end
    has_sigh_review = isstruct(sigh_review) && ...
        isfield(sigh_review, 'reviewed') && sigh_review.reviewed;
    reviewed_parts = {};
    gold_review_mask = false(N, numel(label_names));
    review_status = repmat({'unreviewed'}, 1, numel(label_names));
    for i = 1:numel(defs)
        label_index = find(strcmp(label_names, defs(i).type), 1);
        if has_generic_review
            reviewed_parts{end+1} = field_events( ...
                reviewed_event_sets, defs(i).field); %#ok<AGROW>
        end
        coverage = generic_review_coverage( ...
            manual_edit_info, i, N, numel(defs));
        gold_review_mask(:, label_index) = coverage;
        if any(coverage)
            if isfield(manual_edit_info, 'status_by_label') && ...
                    isfield(manual_edit_info.status_by_label, defs(i).field)
                review_status{label_index} = ...
                    manual_edit_info.status_by_label.(defs(i).field);
            else
                review_status{label_index} = 'reviewed_edited';
            end
        end
    end

    sigh_index = find(strcmp(label_names, 'sigh'), 1);
    if has_sigh_review
        reviewed_parts{end+1} = field_events(sigh_review, 'reviewed_events');
        coverage = sigh_review_coverage(sigh_review, N);
        gold_review_mask(:, sigh_index) = coverage;
        if any(coverage)
            if isfield(sigh_review, 'status')
                review_status{sigh_index} = char(string(sigh_review.status));
            else
                review_status{sigh_index} = 'reviewed_edited';
            end
        end
    end

    working_events_reviewed = normalize_event_types_and_meta( ...
        merge_events(reviewed_parts), config.fs);
    mask_reviewed = events_to_time_mask(working_events_reviewed, N, config);
    events_reviewed = label_mask_to_events(mask_reviewed, label_names, config.fs);

    annotations = struct( ...
        'version', 'automatic_reviewed_annotations_v2', ...
        'label_names', {label_names}, ...
        'events_automatic', events_automatic, ...
        'mask_automatic', mask_automatic, ...
        'events_reviewed', events_reviewed, ...
        'mask_reviewed', mask_reviewed, ...
        'gold_review_mask', gold_review_mask, ...
        'review_status', {review_status}, ...
        'review_scope', 'explicitly_viewed_or_edited_regions_per_label');
    if isstruct(manual_edit_info) && isfield(manual_edit_info, 'review_history')
        annotations.review_history = manual_edit_info.review_history;
    else
        annotations.review_history = struct([]);
    end
    if isstruct(manual_edit_info) && isfield(manual_edit_info, 'review_provenance')
        annotations.review_provenance = manual_edit_info.review_provenance;
    else
        annotations.review_provenance = struct( ...
            'version', 'manual_review_provenance_v1', ...
            'latest_round_id', NaN, ...
            'latest_reviewer_role', 'none', ...
            'start_from', 'none', ...
            'source_review_round', NaN, ...
            'number_of_rounds', 0, ...
            'most_recent_round_id', NaN);
    end
end

function coverage = generic_review_coverage(info, index, N, n_labels)
% GENERIC_REVIEW_COVERAGE Perform the generic review coverage operation.
%
% Syntax:
%   coverage = generic_review_coverage(info, index, N, n_labels)
%
% Inputs:
%   info - Input value `info`.
%   index - Input value `index`.
%   N - Number of samples.
%   n_labels - Label identifier or label metadata.
%
% Outputs:
%   coverage - Computed output value `coverage`.

    coverage = false(N,1);
    if isfield(info, 'review_coverage_mask') && ...
            isequal(size(info.review_coverage_mask), [N n_labels])
        coverage = logical(info.review_coverage_mask(:,index));
    elseif isfield(info, 'review_scope') && ...
            strcmp(char(string(info.review_scope)), ...
                'full_record_per_explicitly_reviewed_label')
        coverage(:) = true;
    end
end

function coverage = sigh_review_coverage(info, N)
% SIGH_REVIEW_COVERAGE Perform the sigh review coverage operation.
%
% Syntax:
%   coverage = sigh_review_coverage(info, N)
%
% Inputs:
%   info - Input value `info`.
%   N - Number of samples.
%
% Outputs:
%   coverage - Computed output value `coverage`.

    coverage = false(N,1);
    if isfield(info, 'review_mask') && numel(info.review_mask) == N
        coverage = logical(info.review_mask(:));
    elseif isfield(info, 'review_scope') && startsWith( ...
            char(string(info.review_scope)), 'full_record')
        coverage(:) = true;
    end
end

function events = field_events(source, field)
% FIELD_EVENTS Perform the field events operation.
%
% Syntax:
%   events = field_events(source, field)
%
% Inputs:
%   source - Input value `source`.
%   field - Input value `field`.
%
% Outputs:
%   events - Event structure array.

    events = empty_events();
    if isstruct(source) && isfield(source, field) && ~isempty(source.(field))
        events = source.(field);
    end
end

function validate_label_order(label_names)
% VALIDATE_LABEL_ORDER Validate label order.
%
% Syntax:
%   validate_label_order(label_names)
%
% Inputs:
%   label_names - Label identifier or label metadata.

    expected = get_labels('short');
    if ~isequal(label_names, expected)
        error('MAGMA:Annotations:CanonicalLabels', ...
            'The Stage-6 annotation schema requires the frozen 11-label order.');
    end
end
