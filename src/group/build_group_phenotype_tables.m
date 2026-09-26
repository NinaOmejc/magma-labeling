function outputs = build_group_phenotype_tables(group_table, out_dir)
% BUILD_GROUP_PHENOTYPE_TABLES Write fixed-order cohort phenotype matrices.
% Values are read from each recording's authoritative numeric_summary struct;
% no feature scalar is recalculated here. Automatic and reviewed provenance are
% kept in separate raw, unscaled tables with aligned availability and coverage.

    schema = get_phenotype_feature_schema();
    if ~isfolder(out_dir), mkdir(out_dir); end
    n_recordings = height(group_table);
    n_features = schema.n_features;

    [recording_id, subject, measure, subject_group, analysis_id, result_files] = ...
        recording_metadata(group_table);
    auto = empty_layer(n_recordings, n_features);
    reviewed = empty_layer(n_recordings, n_features);

    for i = 1:n_recordings
        loaded = load_phenotypes(char(result_files(i)));
        auto = read_layer(auto, i, loaded, 'automatic', schema);
        reviewed = read_layer(reviewed, i, loaded, 'reviewed', schema);
    end

    identifiers = table(recording_id, subject, measure, subject_group, analysis_id);
    outputs = struct();
    outputs.summary_automatic = feature_table(identifiers, auto.values, schema);
    outputs.summary_reviewed = feature_table(identifiers, reviewed.values, schema);
    outputs.availability_automatic = feature_table( ...
        identifiers, double(auto.available), schema);
    outputs.availability_reviewed = feature_table( ...
        identifiers, double(reviewed.available), schema);
    outputs.coverage_automatic = feature_table( ...
        identifiers, auto.coverage, schema);
    outputs.coverage_reviewed = feature_table( ...
        identifiers, reviewed.coverage, schema);
    outputs.dictionary = feature_dictionary(schema);
    outputs.long = [long_table(identifiers, auto, schema, 'automatic'); ...
        long_table(identifiers, reviewed, schema, 'reviewed')];

    writetable(outputs.summary_automatic, fullfile(out_dir, ...
        'phenotype_summary_automatic.csv'));
    writetable(outputs.summary_reviewed, fullfile(out_dir, ...
        'phenotype_summary_reviewed.csv'));
    writetable(outputs.availability_automatic, fullfile(out_dir, ...
        'phenotype_availability_automatic.csv'));
    writetable(outputs.availability_reviewed, fullfile(out_dir, ...
        'phenotype_availability_reviewed.csv'));
    writetable(outputs.coverage_automatic, fullfile(out_dir, ...
        'phenotype_coverage_automatic.csv'));
    writetable(outputs.coverage_reviewed, fullfile(out_dir, ...
        'phenotype_coverage_reviewed.csv'));
    writetable(outputs.dictionary, fullfile(out_dir, ...
        'phenotype_dictionary.csv'));
    writetable(outputs.long, fullfile(out_dir, ...
        'phenotype_summary_long.csv'));

    phenotype_summary_automatic = outputs.summary_automatic;
    phenotype_summary_reviewed = outputs.summary_reviewed;
    phenotype_availability_automatic = outputs.availability_automatic;
    phenotype_availability_reviewed = outputs.availability_reviewed;
    phenotype_coverage_automatic = outputs.coverage_automatic;
    phenotype_coverage_reviewed = outputs.coverage_reviewed;
    phenotype_dictionary = outputs.dictionary;
    phenotype_summary_long = outputs.long;
    save(fullfile(out_dir, 'phenotype_summary.mat'), ...
        'phenotype_summary_automatic', ...
        'phenotype_summary_reviewed', ...
        'phenotype_availability_automatic', ...
        'phenotype_availability_reviewed', ...
        'phenotype_coverage_automatic', ...
        'phenotype_coverage_reviewed', ...
        'phenotype_dictionary', 'phenotype_summary_long');
end

function loaded = load_phenotypes(filename)
% LOAD_PHENOTYPES Avoid warnings for result files without the public field.

    contents = whos('-file', filename);
    if any(strcmp({contents.name}, 'phenotypes'))
        loaded = load(filename, 'phenotypes');
    else
        loaded = struct();
    end
end

function layer = empty_layer(n_recordings, n_features)
% EMPTY_LAYER Allocate fixed-width missing outputs for incomplete recordings.

    layer = struct( ...
        'values', nan(n_recordings, n_features), ...
        'available', false(n_recordings, n_features), ...
        'coverage', nan(n_recordings, n_features), ...
        'missing_reason', {repmat( ...
            {'numeric_summary_not_available_in_saved_recording'}, ...
            n_recordings, n_features)});
end

function layer = read_layer(layer, row, loaded, layer_name, schema)
% READ_LAYER Copy a validated saved numeric summary without recomputation.

    if ~isfield(loaded, 'phenotypes') || ...
            ~isstruct(loaded.phenotypes) || ...
            ~isfield(loaded.phenotypes, layer_name)
        return;
    end
    source = loaded.phenotypes.(layer_name);
    if ~isstruct(source) || ~isfield(source, 'numeric_summary')
        return;
    end
    summary = source.numeric_summary;
    validate_compact_phenotype_features(summary);
    if ~isequal(summary.feature_names, schema.feature_names)
        error('MAGMA:Group:PhenotypeFeatureOrder', ...
            'Saved numeric-summary order differs from the fixed schema.');
    end
    layer.values(row, :) = summary.values;
    layer.available(row, :) = summary.available;
    layer.coverage(row, :) = summary.coverage_fraction;
    layer.missing_reason(row, :) = reshape( ...
        cellstr(string(summary.missing_reason)), 1, []);
end

function T = feature_table(identifiers, values, schema)
% FEATURE_TABLE Append exactly 22 contiguous fixed-order feature columns.

    T = identifiers;
    for i = 1:schema.n_features
        T.(schema.feature_names{i}) = values(:, i);
    end
end

function T = feature_dictionary(schema)
% FEATURE_DICTIONARY Create the authoritative numeric-summary mapping.

    feature_index = (1:schema.n_features)';
    feature_name = string(schema.feature_names(:));
    display_name = string(schema.display_name(:));
    phenotype_group = string(schema.phenotype_group(:));
    feature_role = string(schema.feature_role(:));
    units = string(schema.units(:));
    source_description = string(schema.source_description(:));
    T = table(feature_index, feature_name, display_name, phenotype_group, ...
        feature_role, units, source_description);
end

function T = long_table(identifiers, layer, schema, annotation_layer)
% LONG_TABLE Create one tidy QC row per recording, layer, and feature.

    n = height(identifiers);
    N = schema.n_features;
    recording_id = repelem(identifiers.recording_id, N, 1);
    subject = repelem(identifiers.subject, N, 1);
    measure = repelem(identifiers.measure, N, 1);
    annotation_layer = repmat(string(annotation_layer), n * N, 1);
    feature_index = repmat((1:N)', n, 1);
    feature_name = repmat(string(schema.feature_names(:)), n, 1);
    phenotype_group = repmat(string(schema.phenotype_group(:)), n, 1);
    feature_role = repmat(string(schema.feature_role(:)), n, 1);
    value = reshape(layer.values.', [], 1);
    available = reshape(layer.available.', [], 1);
    coverage_fraction = reshape(layer.coverage.', [], 1);
    units = repmat(string(schema.units(:)), n, 1);
    missing_reason = string(reshape(layer.missing_reason.', [], 1));
    T = table(recording_id, subject, measure, annotation_layer, ...
        feature_index, feature_name, phenotype_group, feature_role, value, ...
        available, coverage_fraction, units, missing_reason);
end

function [recording_id, subject, measure, subject_group, analysis_id, files] = ...
    recording_metadata(group_table)
% RECORDING_METADATA Normalize identifiers shared by all cohort outputs.

    n = height(group_table);
    if n == 0
        recording_id = strings(0, 1);
        subject = zeros(0, 1);
        measure = zeros(0, 1);
        subject_group = strings(0, 1);
        analysis_id = strings(0, 1);
        files = strings(0, 1);
        return;
    end
    required = {'recording_id', 'subject', 'measure', 'subject_group', ...
        'analysis_id', 'result_file'};
    missing = required(~ismember(required, group_table.Properties.VariableNames));
    if ~isempty(missing)
        error('MAGMA:Group:MissingPhenotypeIdentifier', ...
            'Group summary lacks phenotype identifier(s): %s.', ...
            strjoin(missing, ', '));
    end
    recording_id = string(group_table.recording_id);
    subject = double(group_table.subject);
    measure = double(group_table.measure);
    subject_group = string(group_table.subject_group);
    analysis_id = string(group_table.analysis_id);
    files = string(group_table.result_file);
end
