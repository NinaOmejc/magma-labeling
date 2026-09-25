function validate_compact_phenotype_features(compact)
% VALIDATE_COMPACT_PHENOTYPE_FEATURES Enforce the fixed numeric-summary contract.

    schema = get_phenotype_feature_schema();
    required = {'version', 'schema_version', 'n_features', ...
        'feature_names', 'values', 'available', 'coverage_fraction', ...
        'missing_reason', 'phenotype_group', 'feature_role', 'units'};
    if ~isstruct(compact) || ~isscalar(compact)
        error('MAGMA:PhenotypeFeatures:InvalidCompactFeatures', ...
            'compact_features must be a scalar struct.');
    end
    missing = required(~isfield(compact, required));
    if ~isempty(missing)
        error('MAGMA:PhenotypeFeatures:InvalidCompactFeatures', ...
            'compact_features is missing: %s.', strjoin(missing, ', '));
    end
    if compact.n_features ~= schema.n_features
        error('MAGMA:PhenotypeFeatures:InvalidCompactFeatures', ...
            'compact_features.n_features must equal %d.', schema.n_features);
    end
    if ~strcmp(char(string(compact.schema_version)), schema.version)
        error('MAGMA:PhenotypeFeatures:InvalidCompactFeatures', ...
            'compact_features.schema_version does not match the fixed schema.');
    end
    if ~isequal(reshape(cellstr(string(compact.feature_names)), 1, []), ...
            schema.feature_names)
        error('MAGMA:PhenotypeFeatures:InvalidCompactFeatures', ...
            'compact feature names/order do not match the fixed schema.');
    end
    if ~isa(compact.values, 'double') || ...
            ~isequal(size(compact.values), [1 schema.n_features])
        error('MAGMA:PhenotypeFeatures:InvalidCompactFeatures', ...
            'compact values must be a double 1-by-%d vector.', schema.n_features);
    end
    if ~islogical(compact.available) || ...
            ~isequal(size(compact.available), [1 schema.n_features])
        error('MAGMA:PhenotypeFeatures:InvalidCompactFeatures', ...
            'compact available must be a logical 1-by-%d vector.', schema.n_features);
    end
    if ~isa(compact.coverage_fraction, 'double') || ...
            ~isequal(size(compact.coverage_fraction), [1 schema.n_features])
        error('MAGMA:PhenotypeFeatures:InvalidCompactFeatures', ...
            'compact coverage_fraction must be a double 1-by-%d vector.', ...
            schema.n_features);
    end
    text_fields = {'missing_reason', 'phenotype_group', 'feature_role', 'units'};
    expected = {[], schema.phenotype_group, schema.feature_role, schema.units};
    for i = 1:numel(text_fields)
        actual = reshape(cellstr(string(compact.(text_fields{i}))), 1, []);
        if numel(actual) ~= schema.n_features
            error('MAGMA:PhenotypeFeatures:InvalidCompactFeatures', ...
                '%s must have %d aligned entries.', ...
                text_fields{i}, schema.n_features);
        end
        if ~isempty(expected{i}) && ~isequal(actual, expected{i})
            error('MAGMA:PhenotypeFeatures:InvalidCompactFeatures', ...
                '%s does not match the fixed schema.', text_fields{i});
        end
    end
    if any(compact.available & ~isfinite(compact.values))
        error('MAGMA:PhenotypeFeatures:InvalidCompactFeatures', ...
            'Available compact feature values must be finite.');
    end
    if any(~compact.available & isfinite(compact.values))
        error('MAGMA:PhenotypeFeatures:InvalidCompactFeatures', ...
            'Finite compact values must be marked available.');
    end
end
