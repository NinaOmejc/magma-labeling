function results = build_recording_results( ...
    config, resp_cycles, resp_ref, session_reference, ...
    resp_features, label_results)
% BUILD_RECORDING_RESULTS Package authoritative recording outputs for saving.
%
% Inputs:
%   config            - Final pipeline config with subject, measure, input_config,
%                       fs, and HDF5 provenance settings.
%   resp_cycles       - Extracted lung/diaphragm breath-cycle and provenance struct.
%   resp_ref          - Per-belt session/global amplitude references and QC.
%   session_reference - Protocol reference interval and half-open sample/time bounds.
%   resp_features     - Respiratory evidence on breath and analysis-grid levels.
%   label_results     - Final automatic/reviewed annotation products and summaries.
%
% Output:
%   results - Scalar recording-result struct with the following fields:
%     subject, measure - Numeric recording identifiers.
%     events_automatic, events_reviewed - Canonical event arrays by provenance.
%     mask_automatic, mask_reviewed - Nsample x Nlabel logical annotation matrices.
%     review_coverage_mask - Nsample x Nlabel explicit manual-review coverage.
%     review_status, review_scope - Per-label status text and coverage semantics.
%     review_history, review_provenance - Immutable rounds and active-round summary.
%     label_names - Canonical short names in mask-column order.
%     label_available, label_availability_reason - Automatic assessability by label.
%     label_assessable_mask, label_assessability_info - Nsample x Nlabel support and provenance.
%     label_reviewed_available, label_reviewed_availability_reason - Reviewed assessability.
%     label_reviewed_assessable_mask - Review-limited Nsample x Nlabel support.
%     resp_cycles, resp_ref, session_reference, resp_features - Scientific inputs above.
%     spo2_ref - Session SpO2 reference owned by desaturation diagnostics.
%     diagnostic_signals, detector_diagnostics - Exportable traces and detector-specific details.
%     label_burden_automatic, label_burden_reviewed - Per-label seconds, fractions, and counts.
%     label_overlap_summary_automatic, label_overlap_summary_reviewed - Prespecified pair overlaps.
%     label_evidence_summary_automatic, label_evidence_summary_reviewed - Descriptive label evidence.
%     db_phenotype_evidence - Automatic/reviewed phenotype evidence bundle.
%     event_boundary_info - Per-label event timing/localization provenance.
%     manual_label_edit, manual_sigh_review - Manual review outcomes and coverage.
%     input_config, config - Resolved input metadata and complete run configuration.
%     upstream_input_preprocessing - Text describing preprocessing before MAGMA.

    results = struct();
    results.subject = config.subject;
    results.measure = config.measure;
    results.events_automatic = label_results.events_automatic;
    results.mask_automatic = label_results.mask_automatic;
    results.events_reviewed = label_results.events_reviewed;
    results.mask_reviewed = label_results.mask_reviewed;
    results.review_coverage_mask = label_results.review_coverage_mask;
    results.review_status = label_results.review_status;
    results.review_scope = label_results.review_scope;
    results.review_history = label_results.review_history;
    results.review_provenance = label_results.review_provenance;
    results.label_names = label_results.label_names;
    results.label_available = label_results.available;
    results.label_availability_reason = label_results.availability_reason;
    results.label_assessable_mask = label_results.assessable_mask;
    results.label_assessability_info = label_results.assessability_info;
    results.label_reviewed_available = label_results.reviewed_available;
    results.label_reviewed_availability_reason = ...
        label_results.reviewed_availability_reason;
    results.label_reviewed_assessable_mask = ...
        label_results.reviewed_assessable_mask;
    results.resp_cycles = resp_cycles;
    results.resp_ref = resp_ref;
    results.session_reference = session_reference;
    results.spo2_ref = label_results.detector_diagnostics.desat.spo2_ref;
    results.resp_features = resp_features;
    results.diagnostic_signals = label_results.diagnostic_signals;
    results.detector_diagnostics = label_results.detector_diagnostics;
    results.label_burden_automatic = label_results.burden_automatic;
    results.label_burden_reviewed = label_results.burden_reviewed;
    results.label_overlap_summary_automatic = label_results.overlap_automatic;
    results.label_overlap_summary_reviewed = label_results.overlap_reviewed;
    results.label_evidence_summary_automatic = label_results.evidence_automatic;
    results.label_evidence_summary_reviewed = label_results.evidence_reviewed;
    results.db_phenotype_evidence = label_results.db_phenotype_evidence;
    results.event_boundary_info = label_results.event_boundary_info;
    results.manual_label_edit = label_results.manual_label_edit;
    results.manual_sigh_review = label_results.sigh_review;
    results.input_config = config.input_config;
    results.config = config;
    results.upstream_input_preprocessing = get_config_value( ...
        config, 'HDF5', 'upstream_input_preprocessing', ...
        'external / not fully documented');
end
