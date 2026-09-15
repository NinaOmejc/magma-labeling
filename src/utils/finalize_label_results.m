function out = finalize_label_results( ...
    data, resp_cycles, resp_features, session_reference, ...
    detections, sigh_review, config) %#ok<INUSD>
% FINALIZE_LABEL_RESULTS Finalize automatic and reviewed label annotations.
%
% Detector outputs enter through detections and are frozen before manual
% interval review. This function owns annotation assembly, availability,
% summaries, phenotype evidence, and compact candidate events.
%
% Inputs:
%   data              - Nsample x Nchannel preprocessed signal matrix.
%   resp_cycles       - Extracted belt cycles used by downstream review/evidence.
%   resp_features     - Breath-level and analysis-grid respiratory evidence.
%   session_reference - Common physiological reference interval metadata.
%   detections        - Struct with per-label automatic event sets, detector
%                       candidate events, and compact diagnostics.
%   sigh_review       - Automatic/reviewed sigh events and review coverage.
%   config            - Sampling, labels, review, and detector settings.
%
% Output:
%   out - Scalar finalized-label struct. label_names fixes column order;
%         events_automatic/events_reviewed and mask_automatic/mask_reviewed
%         hold canonical events and Nsample x Nlabel states; review_coverage_mask,
%         review_status, review_scope, review_history, and review_provenance
%         preserve manual review. available/availability_reason and
%         assessable_mask/assessability_info describe automatic assessability;
%         reviewed_available/reviewed_availability_reason and
%         reviewed_assessable_mask restrict it to reviewed samples.
%         detector_diagnostics retains unique evidence;
%         burden_automatic/burden_reviewed, overlap_automatic/overlap_reviewed,
%         and evidence_automatic/evidence_reviewed summarize each provenance.
%         db_phenotype_evidence bundles phenotype summaries; candidate_events
%         retains genuine pre-final intervals; manual_label_edit and sigh_review retain
%         the two manual-review outcomes.

    automatic_event_sets = detections.events;
    candidate_events = canonical_candidate_event_sets( ...
        detections.candidate_events);
    spo2_ref = detections.spo2_ref;
    N = size(data, 1);

    [reviewed_event_sets, manual_label_edit] = ...
        manual_edit_label_events(data, config, automatic_event_sets);
    annotations = assemble_annotation_layers( ...
        automatic_event_sets, reviewed_event_sets, manual_label_edit, ...
        sigh_review, N, config);

    label_names = annotations.label_names;
    [available, availability_reason] = compute_label_availability( ...
        label_names, resp_features, detections.diagnostics.desat, ...
        detections.diagnostics.async, detections.diagnostics.apnea, ...
        detections.diagnostics.sigh, detections.diagnostics.csr);
    [assessable_mask, assessability_info] = compute_label_assessable_mask( ...
        data, label_names, available, detections.diagnostics.async, ...
        resp_features.time_sec, config);
    detector_diagnostics = detections.diagnostics;

    burden_automatic = compute_recording_label_burden( ...
        annotations.mask_automatic, label_names, available, ...
        annotations.events_automatic, config.fs, assessable_mask);
    overlap_automatic = compute_label_overlap_summary( ...
        annotations.mask_automatic, label_names, available, ...
        config.fs, assessable_mask);
    evidence_automatic = build_label_evidence_summary( ...
        label_names, available, availability_reason, data, resp_features, ...
        spo2_ref, detector_diagnostics, burden_automatic, config);

    [reviewed_assessable_mask, reviewed_available, ...
        reviewed_availability_reason] = compute_reviewed_label_availability( ...
            available, availability_reason, assessable_mask, ...
            annotations.review_coverage_mask);
    burden_reviewed = compute_recording_label_burden( ...
        annotations.mask_reviewed, label_names, reviewed_available, ...
        annotations.events_reviewed, config.fs, reviewed_assessable_mask);
    overlap_reviewed = compute_label_overlap_summary( ...
        annotations.mask_reviewed, label_names, reviewed_available, ...
        config.fs, reviewed_assessable_mask);
    evidence_reviewed = build_label_evidence_summary( ...
        label_names, reviewed_available, reviewed_availability_reason, ...
        data, resp_features, spo2_ref, detector_diagnostics, ...
        burden_reviewed, config);

    db_phenotype_evidence = build_db_phenotype_evidence_bundle( ...
        burden_automatic, overlap_automatic, evidence_automatic, ...
        burden_reviewed, overlap_reviewed, evidence_reviewed);

    out = struct();
    out.label_names = label_names;
    out.events_automatic = annotations.events_automatic;
    out.mask_automatic = annotations.mask_automatic;
    out.events_reviewed = annotations.events_reviewed;
    out.mask_reviewed = annotations.mask_reviewed;
    out.review_coverage_mask = annotations.review_coverage_mask;
    out.review_status = annotations.review_status;
    out.review_scope = annotations.review_scope;
    out.review_history = annotations.review_history;
    out.review_provenance = annotations.review_provenance;
    out.available = available;
    out.availability_reason = availability_reason;
    out.assessable_mask = assessable_mask;
    out.assessability_info = assessability_info;
    out.reviewed_available = reviewed_available;
    out.reviewed_availability_reason = reviewed_availability_reason;
    out.reviewed_assessable_mask = reviewed_assessable_mask;
    out.candidate_events = candidate_events;
    out.spo2_ref = spo2_ref;
    out.detector_diagnostics = detector_diagnostics;
    out.burden_automatic = burden_automatic;
    out.burden_reviewed = burden_reviewed;
    out.overlap_automatic = overlap_automatic;
    out.overlap_reviewed = overlap_reviewed;
    out.evidence_automatic = evidence_automatic;
    out.evidence_reviewed = evidence_reviewed;
    out.db_phenotype_evidence = db_phenotype_evidence;
    out.manual_label_edit = manual_label_edit;
    out.sigh_review = sigh_review;
end

function sets = canonical_candidate_event_sets(input_sets)
% CANONICAL_CANDIDATE_EVENT_SETS Enforce one compact array per frozen label.

    labels = get_labels('short');
    sets = struct();
    expected = fieldnames(empty_candidate_events());
    for i = 1:numel(labels)
        label = labels{i};
        if isstruct(input_sets) && isfield(input_sets, label)
            candidates = input_sets.(label);
        else
            candidates = empty_candidate_events();
        end
        if ~isempty(candidates) && ~isequal(fieldnames(candidates), expected)
            error('MAGMA:CandidateEvents:InvalidSchema', ...
                'candidate_events.%s does not use the compact schema.', label);
        end
        sets.(label) = candidates;
    end
end
