function data = build_group_descriptive_tables(config, group_table, phenotypes)
% BUILD_GROUP_DESCRIPTIVE_TABLES Align saved cohort summaries by subject and measurement.
% No single-recording analysis or label/phenotype calculation occurs here.

    layer = lower(char(string(config.group.plot_layer)));
    if ~ismember(layer, {'automatic', 'reviewed'})
        error('MAGMA:Group:InvalidLayer', 'plot_layer must be automatic or reviewed.');
    end
    pair = double(config.group.paired_measurements(:)');
    if numel(pair) ~= 2 || any(~ismember(pair, 1:4)) || pair(1) == pair(2)
        error('MAGMA:Group:InvalidPair', 'paired_measurements must contain two distinct values from 1:4.');
    end
    schema = get_phenotype_feature_schema();
    labels = get_labels('short');
    out_dir = fullfile(config.path_results_out, 'group_analysis', 'descriptive_overview');
    if ~isfolder(out_dir), mkdir(out_dir); end

    subjects = zeros(0, 1);
    groups = strings(0, 1);
    if height(group_table) > 0
        subjects = unique(double(group_table.subject));
        subjects = subjects(isfinite(subjects));
        groups = strings(numel(subjects), 1);
        for s = 1:numel(subjects)
            row = find(group_table.subject == subjects(s), 1);
            groups(s) = string(group_table.subject_group(row));
        end
        rank = 3 * ones(numel(groups), 1);
        rank(groups == "Control") = 1;
        rank(groups == "Patient") = 2;
        [~, order] = sortrows([rank subjects]);
        subjects = subjects(order);
        groups = groups(order);
    end
    measures = double(config.group.measurements(:)');
    if isempty(measures)
        measures = unique(double(group_table.measure(:)))';
    end
    if any(~ismember(measures, 1:4)) || numel(unique(measures)) ~= numel(measures)
        error('MAGMA:Group:InvalidMeasurements', 'measurements must be distinct values from 1:4.');
    end

    ns = numel(subjects);
    nm = numel(measures);
    nl = numel(labels);
    nf = schema.n_features;
    label_values = nan(ns, nl, nm);
    label_available = false(ns, nl, nm);
    feature_values = nan(ns, nf, nm);
    feature_available = false(ns, nf, nm);
    recording_present = false(ns, nm);

    group_dir = fullfile(config.path_results_out, 'group_analysis');
    if nargin < 3
        saved = load(fullfile(group_dir, '_cache', 'group_analysis_data.mat'), 'cohort');
        phenotypes = saved.cohort.phenotypes;
    end
    phenotype = phenotypes.(['summary_' layer]);
    phenotype_availability = phenotypes.(['availability_' layer]);

    for s = 1:ns
        for m = 1:nm
            idx = find(group_table.subject == subjects(s) & group_table.measure == measures(m));
            if numel(idx) > 1
                error('MAGMA:Group:DuplicateRecording', 'Multiple saved results for Sub%d_M%d.', subjects(s), measures(m));
            end
            if isempty(idx), continue; end
            recording_present(s, m) = true;
            for l = 1:nl
                stem = ['label_' labels{l} '_'];
                field = [stem layer '_fraction'];
                avail_field = [stem 'available'];
                if ~ismember(field, group_table.Properties.VariableNames), continue; end
                value = double(group_table.(field)(idx));
                available = ismember(avail_field, group_table.Properties.VariableNames) && ...
                    logical(group_table.(avail_field)(idx));
                if strcmp(layer, 'reviewed')
                    coverage_field = [stem 'reviewed_coverage_fraction'];
                    available = available && ismember(coverage_field, group_table.Properties.VariableNames) && ...
                        group_table.(coverage_field)(idx) > 0;
                end
                if available && isfinite(value)
                    label_values(s, l, m) = value;
                    label_available(s, l, m) = true;
                end
            end
            pi = find(phenotype.subject == subjects(s) & phenotype.measure == measures(m));
            ai = find(phenotype_availability.subject == subjects(s) & ...
                phenotype_availability.measure == measures(m));
            if numel(pi) ~= 1 || numel(ai) ~= 1
                error('MAGMA:Group:PhenotypeAlignment', ...
                    'Phenotype rows do not align for Sub%d_M%d.', subjects(s), measures(m));
            end
            for f = 1:nf
                name = schema.feature_names{f};
                value = double(phenotype.(name)(pi));
                available = logical(phenotype_availability.(name)(ai));
                if available && isfinite(value)
                    feature_values(s, f, m) = value;
                    feature_available(s, f, m) = true;
                end
            end
        end
    end

    data = struct('out_dir', out_dir, 'layer', layer, 'pair', pair, ...
        'subjects', subjects, 'groups', groups, 'measures', measures, ...
        'labels', {labels}, 'schema', schema, 'label_values', label_values, ...
        'label_available', label_available, 'feature_values', feature_values, ...
        'feature_available', feature_available, 'recording_present', recording_present);
    data.label_summary = measurement_summary(label_values, measures, labels, ...
        repmat({'fraction'}, 1, nl), repmat({'physiological_label'}, 1, nl), ...
        repmat({'label'}, 1, nl));
    data.feature_summary = measurement_summary(feature_values, measures, ...
        schema.feature_names, schema.units, schema.phenotype_group, schema.feature_role);
    data.label_pairs = pair_details(data, label_values, label_available, labels, ...
        repmat({'fraction'}, 1, nl), 'label');
    data.feature_pairs = pair_details(data, feature_values, feature_available, ...
        schema.feature_names, schema.units, 'phenotype_feature');
    data.label_pair_summary = pair_summary(data.label_pairs, labels, ...
        repmat({'percentage_points'}, 1, nl), 'label');
    data.feature_pair_summary = pair_summary(data.feature_pairs, ...
        schema.feature_names, schema.units, 'phenotype_feature');
    metadata_source = "not provided";
    if isfield(config.group, 'metadata_source')
        metadata_source = string(config.group.metadata_source);
    elseif any(groups ~= "Unknown")
        metadata_source = "config.group lists";
    end
    source_file = "";
    if isfield(config.group, 'metadata_file')
        source_file = string(config.group.metadata_file);
    end
    row_source = repmat(metadata_source, ns, 1);
    row_source(groups == "Unknown" & metadata_source == "Questionnaire.grp") = ...
        "No matching questionnaire grp";
    data.group_mapping = table(subjects, groups, row_source, ...
        repmat(source_file, ns, 1), 'VariableNames', ...
        {'subject', 'subject_group', 'metadata_source', 'source_file'});
    data.valid_measurement_pairs = 0;
    ia = find(measures == pair(1), 1);
    ib = find(measures == pair(2), 1);
    if ~isempty(ia) && ~isempty(ib)
        data.valid_measurement_pairs = nnz(recording_present(:, ia) & recording_present(:, ib));
    end

    data.files = {fullfile(group_dir, 'group_summary.xlsx'), ...
        fullfile(group_dir, 'group_details.xlsx')};

    discovered = dir(fullfile(config.path_results_out, 'Sub*_M*', '*_results.mat'));
    discovered_subjects = nan(numel(discovered), 1);
    for i = 1:numel(discovered)
        match = regexp(discovered(i).name, '^Sub(\d+)_M\d+_results\.mat$', 'tokens', 'once');
        if ~isempty(match), discovered_subjects(i) = str2double(match{1}); end
    end
    discovered_subjects = unique(discovered_subjects(isfinite(discovered_subjects)));
    excluded = double(config.group.exclude_subjects(:));
    data.excluded_subjects = intersect(discovered_subjects, excluded);
    data.n_recordings = height(group_table);
    data.metadata_source = metadata_source;
    data.metadata_file = source_file;
    fprintf('Group analysis: %d subjects, %d recordings, %d measurements, %d excluded subjects, %d valid M%d-M%d recording pairs.\n', ...
        ns, data.n_recordings, numel(unique(measures( ...
        any(recording_present, 1)))), ...
        numel(data.excluded_subjects), data.valid_measurement_pairs, pair(1), pair(2));
end

function T = measurement_summary(values, measures, names, units, categories, roles)
    rows = cell(0, 12);
    for m = 1:numel(measures)
        for v = 1:numel(names)
            x = values(:, v, m);
            x = x(isfinite(x));
            [med, spread, p10, p25, p75, p90] = describe(x);
            rows(end+1, :) = {measures(m), string(names{v}), string(units{v}), ...
                string(categories{v}), string(roles{v}), numel(x), med, spread, ...
                p10, p25, p75, p90}; %#ok<AGROW>
        end
    end
    T = cell2table(rows, 'VariableNames', {'measurement', 'variable', ...
        'units', 'category', 'feature_role', 'n', 'median', 'iqr', ...
        'p10', 'p25', 'p75', 'p90'});
end

function T = pair_details(data, values, available, names, units, variable_type)
    ns = numel(data.subjects);
    nv = numel(names);
    ia = find(data.measures == data.pair(1), 1);
    ib = find(data.measures == data.pair(2), 1);
    x1 = nan(ns, nv);
    x2 = nan(ns, nv);
    a1 = false(ns, nv);
    a2 = false(ns, nv);
    if ~isempty(ia)
        x1 = values(:, :, ia);
        a1 = available(:, :, ia);
    end
    if ~isempty(ib)
        x2 = values(:, :, ib);
        a2 = available(:, :, ib);
    end
    valid = a1 & a2 & isfinite(x1) & isfinite(x2);
    delta = x2 - x1;
    if strcmp(variable_type, 'label'), delta = 100 .* delta; end
    delta(~valid) = nan;
    subject = repelem(data.subjects(:), nv, 1);
    subject_group = repelem(data.groups(:), nv, 1);
    measurement_1 = repmat(data.pair(1), ns*nv, 1);
    measurement_2 = repmat(data.pair(2), ns*nv, 1);
    variable = repmat(string(names(:)), ns, 1);
    variable_type = repmat(string(variable_type), ns*nv, 1);
    value_units = repmat(string(units(:)), ns, 1);
    change_units = value_units;
    if all(variable_type == "label"), change_units(:) = "percentage_points"; end
    value_1 = reshape(x1.', [], 1);
    value_2 = reshape(x2.', [], 1);
    available_1 = reshape(a1.', [], 1);
    available_2 = reshape(a2.', [], 1);
    valid_pair = reshape(valid.', [], 1);
    change = reshape(delta.', [], 1);
    T = table(subject, subject_group, measurement_1, measurement_2, ...
        variable_type, variable, value_units, change_units, value_1, value_2, ...
        change, available_1, available_2, valid_pair);
end

function T = pair_summary(details, names, units, variable_type)
    rows = cell(0, 11);
    for v = 1:numel(names)
        keep = details.variable == string(names{v}) & details.valid_pair;
        x = details.change(keep);
        [med, spread, p10, p25, p75, p90] = describe(x);
        rows(end+1, :) = {string(variable_type), string(names{v}), ...
            string(units{v}), numel(x), med, spread, p10, p25, p75, p90, ...
            nnz(details.variable == string(names{v}))}; %#ok<AGROW>
    end
    T = cell2table(rows, 'VariableNames', {'variable_type', 'variable', ...
        'change_units', 'valid_pair_n', 'median_change', 'iqr_change', ...
        'p10_change', 'p25_change', 'p75_change', 'p90_change', 'subject_n'});
end

function [med, spread, p10, p25, p75, p90] = describe(x)
    med = nan; spread = nan; p10 = nan; p25 = nan; p75 = nan; p90 = nan;
    if isempty(x), return; end
    q = prctile(x, [10 25 75 90]);
    med = median(x);
    p10 = q(1); p25 = q(2); p75 = q(3); p90 = q(4);
    spread = p75 - p25;
end

