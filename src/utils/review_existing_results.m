function [results, cancelled] = review_existing_results(data, existing, config)
% REVIEW_EXISTING_RESULTS Add a review round without rerunning analysis.
% cancelled is true for X; results then remains the unchanged existing struct.

    cancelled = false;
    required = {'events_automatic', 'mask_automatic', 'label_names', ...
        'label_available', 'label_availability_reason', ...
        'label_assessable_mask', 'resp_cycles', 'resp_features', ...
        'spo2_ref', 'detector_diagnostics', 'label_burden_automatic', ...
        'label_overlap_summary_automatic', 'label_evidence_summary_automatic', ...
        'analysis_id','analysis_recording_observations','analysis_respiratory_artifact_revision','phenotypes'};
    missing = required(~isfield(existing, required));
    if ~isempty(missing)
        error('MAGMA:Execution:InvalidAutomaticResults', ...
            'Existing automatic result is missing: %s.', strjoin(missing, ', '));
    end
    if ~isequal(cellstr(string(existing.label_names)), get_labels('short'))
        error('MAGMA:Execution:InvalidAutomaticResults', ...
            'Existing automatic result does not use the canonical label order.');
    end
    if size(existing.mask_automatic, 1) ~= size(data, 1)
        error('MAGMA:Execution:SignalLengthMismatch', ...
            'Existing automatic results and the review signal have different lengths.');
    end
    if (isfield(existing, 'subject') && existing.subject ~= config.subject) || ...
            (isfield(existing, 'measure') && existing.measure ~= config.measure) || ...
            (isfield(existing, 'config') && isfield(existing.config, 'fs') && ...
             existing.config.fs ~= config.fs)
        error('MAGMA:Execution:AutomaticResultMismatch', ...
            'Existing automatic results do not match the requested recording or sampling rate.');
    end

    config.execution.analysis_id = existing.analysis_id;
    automatic_event_sets = split_automatic_events(existing.events_automatic);
    [reviewed_event_sets, manual_edit_info] = manual_edit_label_events( ...
        data, existing.resp_cycles, config, automatic_event_sets);
    if isfield(manual_edit_info, 'cancelled') && manual_edit_info.cancelled
        results = existing;
        cancelled = true;
        return;
    end
    annotations = assemble_annotation_layers(automatic_event_sets, ...
        reviewed_event_sets, manual_edit_info, size(data, 1), config);

    results = existing;
    results.respiratory_artifact_state = respiratory_artifact_checkpoint('load',config);
    results.resp_cycles = migrate_respiratory_artifacts(results.resp_cycles,size(data,1),results.respiratory_artifact_state);
    results.events_reviewed = annotations.events_reviewed;
    results.mask_reviewed = annotations.mask_reviewed;
    results.review_coverage_mask = annotations.review_coverage_mask;
    results.review_status = annotations.review_status;
    results.review_scope = annotations.review_scope;
    results.review_history = annotations.review_history;
    results.review_provenance = annotations.review_provenance;
    results.manual_label_edit = manual_edit_info;
    results.recording_observations = manual_edit_info.recording_observations;

    % Current automatic evidence and summaries are immutable during review.
    [reviewed_assessable, reviewed_available, reviewed_reason] = ...
        compute_reviewed_label_availability(existing.label_available, ...
            existing.label_availability_reason, ...
            existing.label_assessable_mask, annotations.review_coverage_mask);
    results.label_reviewed_assessable_mask = reviewed_assessable;
    results.label_reviewed_available = reviewed_available;
    results.label_reviewed_availability_reason = reviewed_reason;
    results.label_burden_reviewed = compute_recording_label_burden( ...
        annotations.mask_reviewed, existing.label_names, reviewed_available, ...
        annotations.events_reviewed, config.fs, reviewed_assessable);
    results.label_overlap_summary_reviewed = compute_label_overlap_summary( ...
        annotations.mask_reviewed, existing.label_names, reviewed_available, ...
        config.fs, reviewed_assessable, annotations.events_reviewed);
    results.label_evidence_summary_reviewed = build_label_evidence_summary( ...
        existing.label_names, reviewed_available, reviewed_reason, data, ...
        existing.resp_features, existing.spo2_ref, ...
        existing.detector_diagnostics, results.label_burden_reviewed, config, ...
        annotations.mask_reviewed, annotations.events_reviewed, ...
        reviewed_assessable);
    results.phenotypes = build_db_phenotype_evidence_bundle( ...
        results.label_burden_automatic, ...
        results.label_overlap_summary_automatic, ...
        results.label_evidence_summary_automatic, ...
        results.label_burden_reviewed, ...
        results.label_overlap_summary_reviewed, ...
        results.label_evidence_summary_reviewed);
    results.phenotypes = attach_thoracic_excursion_phenotype(results.phenotypes, results);
    results.phenotypes.automatic = existing.phenotypes.automatic;
    results = attach_review_phenotypes(results);
    results.analysis_id = config.execution.analysis_id;
    % The saved configuration describes the immutable automatic analysis.
    % Reviewer identity and source analysis are carried by the review round.
    if ~isfield(results, 'config') || isempty(results.config)
        results.config = config;
    end
end

function event_sets = split_automatic_events(events)
% SPLIT_AUTOMATIC_EVENTS Convert canonical events to unified review fields.

    defs = manual_label_definitions();
    event_sets = struct();
    if isempty(events)
        event_types = {};
    else
        event_types = canonicalize_label_names({events.type});
    end
    for i = 1:numel(defs)
        if isempty(events)
            event_sets.(defs(i).field) = empty_events();
        else
            selected = events(strcmp(event_types, defs(i).type));
            for j = 1:numel(selected)
                selected(j).type = defs(i).type;
            end
            event_sets.(defs(i).field) = selected(:);
        end
    end
end
