function bundle = build_db_phenotype_evidence_bundle( ...
    automatic_burden, automatic_overlap, automatic_evidence, ...
    reviewed_burden, reviewed_overlap, reviewed_evidence)
% BUILD_DB_PHENOTYPE_EVIDENCE_BUNDLE Build parallel automatic/reviewed profiles.
% Each input triplet is label burden, overlap, and detector-evidence summary for
% one annotation layer. bundle fields are version; automatic and reviewed
% phenotype evidence with explicit annotation/detector scopes; shared placeholder
% external_clinical_data; and a provenance/interpretation note.

    bundle = struct();
    bundle.version = 'magma_db_phenotype_evidence_bundle_v1';
    bundle.automatic = build_db_phenotype_evidence( ...
        automatic_burden, automatic_overlap, automatic_evidence, 'automatic_labels');
    bundle.reviewed = build_db_phenotype_evidence( ...
        reviewed_burden, reviewed_overlap, reviewed_evidence, 'reviewed_labels');
    bundle.automatic.annotation_scope = 'full_assessable_recording';
    bundle.automatic.detector_evidence_scope = 'full_record_descriptive_evidence';
    bundle.reviewed.annotation_scope = 'explicitly_reviewed_and_assessable_regions';
    bundle.reviewed.detector_evidence_scope = ...
        'full_record_descriptive_evidence_not_manual_confidence';
    bundle.external_clinical_data = bundle.automatic.external_clinical_data;
    bundle.provenance_note = [ ...
        'automatic and reviewed profiles are descriptive signal-derived evidence; ' ...
        'external clinical data are not integrated and no profile is a diagnosis'];
end
