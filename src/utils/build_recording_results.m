function results = build_recording_results( ...
    config, resp_cycles, resp_ref, session_reference, ...
    spo2_ref, resp_features, label_results)
% BUILD_RECORDING_RESULTS Package authoritative recording outputs for saving.

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
    results.spo2_ref = spo2_ref;
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
