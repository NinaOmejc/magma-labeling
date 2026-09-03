function bundle = build_db_phenotype_evidence_bundle( ...
    weak_burden, weak_overlap, weak_evidence, ...
    reviewed_burden, reviewed_overlap, reviewed_evidence)
% build_db_phenotype_evidence_bundle
% Keep the same five prespecified profiles while distinguishing the label
% provenance used to derive them. External clinical values are placeholders
% only and remain explicitly unavailable.

    bundle = struct();
    bundle.version = 'magma_db_phenotype_evidence_bundle_v1';
    bundle.weak = build_db_phenotype_evidence( ...
        weak_burden, weak_overlap, weak_evidence, 'weak_labels');
    bundle.reviewed = build_db_phenotype_evidence( ...
        reviewed_burden, reviewed_overlap, reviewed_evidence, 'reviewed_labels');
    bundle.weak.annotation_scope = 'full_assessable_recording';
    bundle.weak.detector_evidence_scope = 'full_record_descriptive_evidence';
    bundle.reviewed.annotation_scope = 'explicitly_reviewed_and_assessable_regions';
    bundle.reviewed.detector_evidence_scope = ...
        'full_record_descriptive_evidence_not_manual_confidence';
    bundle.external_clinical_data = bundle.weak.external_clinical_data;
    bundle.provenance_note = [ ...
        'weak and reviewed profiles are descriptive signal-derived evidence; ' ...
        'external clinical data are not integrated and no profile is a diagnosis'];
end
