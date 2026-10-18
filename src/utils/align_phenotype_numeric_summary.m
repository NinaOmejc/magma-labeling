function summary = align_phenotype_numeric_summary(summary)
% ALIGN_PHENOTYPE_NUMERIC_SUMMARY Pad a legacy copy; never rewrite its source.
    validate_compact_phenotype_features(summary);
    schema = get_phenotype_feature_schema();
    if summary.n_features == schema.n_features, return; end
    count = summary.n_features;
    summary.values(count+1:schema.n_features) = NaN;
    summary.available(count+1:schema.n_features) = false;
    summary.coverage_fraction(count+1:schema.n_features) = NaN;
    summary.missing_reason(count+1:schema.n_features) = {'not_computed_in_legacy_summary'};
    summary.version = 'magma_phenotype_numeric_summary_v4';
    summary.schema_version = schema.version; summary.n_features = schema.n_features;
    for field = {'feature_names','phenotype_group','feature_role','units'}
        summary.(field{1}) = schema.(field{1});
    end
end
