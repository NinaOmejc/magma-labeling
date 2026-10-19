function tests = test_group_descriptive_overview
% Synthetic saved-result integration tests; no raw recordings or detectors.
    tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    repo = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    addpath(genpath(fullfile(repo, 'src')));
    testCase.TestData.repo = repo;
end

function testAutomaticDiscoveryPairingAndFigures(testCase)
    [root, cleanup] = saved_cohort(); %#ok<ASGLU>
    config = cohort_config(root);
    before = result_file_info(root);
    group_table = build_group_label_table(config);
    data = build_group_descriptive_tables(config, group_table);
    verifyEqual(testCase, height(group_table), 6);
    verifyEqual(testCase, data.subjects, [2; 1; 3; 5]);
    verifyEqual(testCase, data.groups, ["Control";"Patient";"Unknown";"Unknown"]);
    verifyEqual(testCase, data.excluded_subjects, 4);
    verifyEqual(testCase, data.valid_measurement_pairs, 2);
    verifyEqual(testCase, data.schema.feature_names, ...
        get_phenotype_feature_schema().feature_names);
    verifyEqual(testCase, data.label_values(1, 4, 1), 0);
    verifyEqual(testCase, data.label_values(1, 4, 2), 0);
    verifyTrue(testCase, isnan(data.label_values(1, 9, 2)));
    verifyFalse(testCase, data.label_available(1, 9, 2));
    verifyTrue(testCase, isnan(data.feature_values(1, 11, 2)));
    verifyTrue(testCase, isnan(data.label_values(3, 4, 2)));
    verifyTrue(testCase, isnan(data.label_values(4, 4, 1)));

    rapid = data.label_pairs.variable == "rapid";
    sub1 = rapid & data.label_pairs.subject == 1;
    sub2 = rapid & data.label_pairs.subject == 2;
    verifyEqual(testCase, data.label_pairs.change(sub1), 30, 'AbsTol', 1e-10);
    verifyEqual(testCase, data.label_pairs.change(sub2), 0);
    verifyEqual(testCase, data.label_pair_summary.valid_pair_n( ...
        data.label_pair_summary.variable == "rapid"), 2);
    verifyEqual(testCase, data.feature_pair_summary.valid_pair_n( ...
        data.feature_pair_summary.variable == "db_thoracic_dominant_fraction"), 1);
    verifyFalse(testCase, data.label_pairs.valid_pair( ...
        rapid & data.label_pairs.subject == 3));

    label_histograms = plot_group_label_histograms(config, data);
    count_table = label_histograms.counts;
    rapid_m1 = count_table.label == "rapid" & count_table.measurement == 1;
    verifyEqual(testCase, count_table.positive_n(rapid_m1), 1);
    verifyEqual(testCase, count_table.assessed_zero_n(rapid_m1), 2);
    bins = label_histograms.bins;
    verifyEqual(testCase, sum(bins.subject_n( ...
        bins.label == "rapid" & bins.measurement == 1)), 3);
    group_histograms = plot_group_stratified_histograms(config, data);
    verifyEqual(testCase, numel(group_histograms.figures), 3);
    verifyTrue(testCase, all(cellfun(@isfile, group_histograms.figures)));
    verifyTrue(testCase, isfile(fullfile(data.out_dir, ...
        'group_label_burden_histograms_automatic_Control_Patient.png')));
    control_counts = group_histograms.counts(group_histograms.counts.cohort == "Control", :);
    patient_counts = group_histograms.counts(group_histograms.counts.cohort == "Patient", :);
    verifyEqual(testCase, control_counts.positive_n( ...
        control_counts.label == "rapid" & control_counts.measurement == 1), 0);
    verifyEqual(testCase, patient_counts.positive_n( ...
        patient_counts.label == "rapid" & patient_counts.measurement == 1), 1);
    data.label_histograms = label_histograms;
    data.group_histograms = group_histograms;
    data.manifest = build_group_descriptive_manifest(config, data);
    cached = load(fullfile(root, 'group_analysis', '_cache', 'group_analysis_data.mat'));
    data.files = write_group_workbooks(root, group_table, cached.cohort, data);
    verifyTrue(testCase, isfile(label_histograms.distribution_figure));
    verifyTrue(testCase, all(cellfun(@isfile, data.files)));
    verifyEqual(testCase, numel(dir(fullfile(data.out_dir, '*.png'))), 4);
    verifyEmpty(testCase, dir(fullfile(root, 'group_analysis', '**', '*.csv')));
    verifyFalse(testCase, isfolder(fullfile(root, 'group_analysis', 'diagnostic_overview')));
    exported = readtable(data.files{2}, 'Sheet', 'Label_counts', 'TextType', 'string');
    verifyEqual(testCase, height(exported), height(count_table)+height(group_histograms.counts));
    verifyEqual(testCase, exported.positive_n( ...
        exported.cohort == "All" & exported.label == "rapid" & exported.measurement == 1), 1);
    pairs = readtable(data.files{2}, 'Sheet', 'Paired_changes', 'TextType', 'string');
    verifyEqual(testCase, height(pairs), height(data.label_pairs)+height(data.feature_pairs));
    verifyTrue(testCase, isnan(pairs.change(pairs.subject == 3 & pairs.variable == "rapid")));
    verifyEqual(testCase, before, result_file_info(root));
end

function testReviewedScopeAlternativePairAndFilters(testCase)
    [root, cleanup] = saved_cohort(); %#ok<ASGLU>
    config = cohort_config(root);
    config.group.subjects = 1;
    config.group.measurements = [1 2];
    config.group.plot_layer = 'reviewed';
    group_table = build_group_label_table(config);
    data = build_group_descriptive_tables(config, group_table);
    verifyEqual(testCase, data.subjects, 1);
    verifyEqual(testCase, data.label_values(1, 4, 1), 0.5);
    verifyTrue(testCase, isnan(data.label_values(1, 4, 2)));
    verifyFalse(testCase, data.label_pairs.valid_pair( ...
        data.label_pairs.variable == "rapid"));
    verifyTrue(testCase, isnan(data.feature_values(1, 2, 1)));
    verifyEqual(testCase, data.feature_values(1, 1, 1), 0.75);

    config.group.plot_layer = 'automatic';
    config.group.measurements = [3 4];
    config.group.paired_measurements = [3 4];
    group_table = build_group_label_table(config);
    data = build_group_descriptive_tables(config, group_table);
    verifyEqual(testCase, data.valid_measurement_pairs, 1);
    verifyEqual(testCase, data.label_pairs.change( ...
        data.label_pairs.variable == "rapid"), 40, 'AbsTol', 1e-10);
end

function testQuestionnaireGroupParser(testCase)
    cells = {'', 'General'; 'Sub_code', 'grp'; ...
        'Sub2', 0; 'Sub1', 1; 'Sub3', ''; 'Sub2', 0};
    metadata = parse_group_subject_metadata(cells);
    verifyEqual(testCase, metadata.control_subjects, 2);
    verifyEqual(testCase, metadata.patient_subjects, 1);
    cells{end, 2} = 1;
    verifyError(testCase, @() parse_group_subject_metadata(cells), ...
        'MAGMA:Group:ConflictingMetadata');
end

function testMainGroupRunsFromSavedResults(testCase)
    [root, cleanup] = saved_cohort(); %#ok<ASGLU>
    config = cohort_config(root);
    before = result_file_info(root);
    run(fullfile(testCase.TestData.repo, 'src', 'main_group.m'));
    verifyEqual(testCase, descriptive.n_recordings, 6);
    verifyEqual(testCase, descriptive.valid_measurement_pairs, 2);
    verifyEqual(testCase, numel(dir(fullfile(root, 'group_analysis', '*.xlsx'))), 2);
    manifest = readtable(descriptive.files{2}, 'Sheet', 'Manifest', 'TextType', 'string');
    verifyEqual(testCase, height(manifest), 6);
    verifyTrue(testCase, all(isfile(manifest.generated_path)));
    verifyEqual(testCase, before, result_file_info(root));
end

function testNoPlotsReviewedLayerAndWorkbookRefresh(testCase)
    [root, cleanup] = saved_cohort(); %#ok<ASGLU>
    config = cohort_config(root);
    config.group.plot_label_histograms = false;
    config.group.plot_stratified_histograms = false;
    run(fullfile(testCase.TestData.repo, 'src', 'main_group.m'));
    verifyEmpty(testCase, dir(fullfile(root, 'group_analysis', '**', '*.png')));
    writecell({'stale'}, descriptive.files{2}, 'Sheet', 'Stale_sheet');
    config.group.subjects = 1;
    config.group.plot_layer = 'reviewed';
    config.group.plot_label_histograms = true;
    config.group.plot_stratified_histograms = true;
    run(fullfile(testCase.TestData.repo, 'src', 'main_group.m'));
    verifyEmpty(testCase, dir(fullfile(root, 'group_analysis', '**', '*.png')));
    verifyFalse(testCase, any(sheetnames(descriptive.files{2}) == "Stale_sheet"));
    verifyFalse(testCase, any(sheetnames(descriptive.files{2}) == "Label_bins"));
    recordings = readtable(descriptive.files{2}, 'Sheet', 'Recordings');
    verifyEqual(testCase, height(recordings), 2);
    summary = readtable(descriptive.files{1}, 'Sheet', 'Descriptive', 'TextType', 'string');
    verifyTrue(testCase, all(summary.annotation_layer == "reviewed"));
end

function testRecordingExclusionPreservesOtherMeasurements(testCase)
    [root, cleanup] = saved_cohort(); %#ok<ASGLU>
    config = cohort_config(root);
    config.exclude_recordings = [1 1; 3 1];
    % Excluded files must be filtered before loading, even when unreadable.
    excluded_file = fullfile(root, 'Sub1_M1', 'Sub1_M1_results.mat');
    fid = fopen(excluded_file, 'w'); fwrite(fid, 'excluded test fixture'); fclose(fid);
    [group_table, cohort] = build_group_label_table(config, false);
    verifyEqual(testCase, height(group_table), 4);
    verifyFalse(testCase, any(ismember([group_table.subject group_table.measure], ...
        config.exclude_recordings, 'rows')));
    verifyTrue(testCase, any(group_table.subject == 1 & group_table.measure == 2));
    data = build_group_descriptive_tables(config, group_table, cohort.phenotypes);
    verifyEqual(testCase, data.recording_present(data.subjects == 1, :), [false true]);
    verifyEqual(testCase, data.valid_measurement_pairs, 1);
end

function config = cohort_config(root)
    config = get_config_defaults();
    config.path_results_out = root;
    config.exclude_recordings = [];
    config.make_figs_visible = 'off';
    config.plot_format = 'png';
    config.group.subjects = [];
    config.group.measurements = [1 2];
    config.group.exclude_subjects = 4;
    config.group.control_subjects = 2;
    config.group.patient_subjects = 1;
    config.group.paired_measurements = [1 2];
end

function [root, cleanup] = saved_cohort()
    root = tempname;
    mkdir(root);
    cleanup = onCleanup(@() rmdir(root, 's'));
    specs = [1 1 2; 1 2 5; 2 1 0; 2 2 0; ...
        3 1 0; 5 2 0; 4 1 9; 1 3 1; 1 4 5];
    schema = get_phenotype_feature_schema();
    for k = 1:size(specs, 1)
        subject = specs(k, 1);
        measure = specs(k, 2);
        rapid_count = specs(k, 3);
        folder = fullfile(root, sprintf('Sub%d_M%d', subject, measure));
        mkdir(folder);
        label_names = get_labels('short');
        label_available = true(1, 11);
        mask_automatic = false(10, 11);
        mask_automatic(1:rapid_count, 4) = true;
        if subject == 2 && measure == 2
            label_available(9) = false;
        end
        label_assessable_mask = repmat(label_available, 10, 1);
        review_coverage_mask = false(10, 11);
        mask_reviewed = false(10, 11);
        if subject == 1 && measure == 1
            review_coverage_mask(1:4, 4) = true;
            mask_reviewed(1:2, 4) = true;
        end
        config = struct('fs', 10);
        automatic = compact(schema, [subject/10 + measure/100 + (1:22)/1000, 0.5, 0]);
        automatic.values(1) = rapid_count/10;
        if subject == 2 && measure == 2
            automatic.available(11:13) = false;
            automatic.values(11:13) = nan;
            automatic.coverage_fraction(11:13) = 0;
        end
        reviewed = compact(schema, nan(1, 24));
        reviewed.available(:) = false;
        reviewed.coverage_fraction(:) = 0;
        if subject == 1 && measure == 1
            reviewed.values(1) = 0.75;
            reviewed.available(1) = true;
            reviewed.coverage_fraction(1) = 0.4;
        end
        phenotypes = struct('automatic', struct('numeric_summary', automatic), ...
            'reviewed', struct('numeric_summary', reviewed));
        result_file = fullfile(folder, sprintf('Sub%d_M%d_results.mat', subject, measure));
        save_result_fixture(result_file, 'subject', 'measure', 'label_names', ...
            'label_available', 'label_assessable_mask', 'mask_automatic', ...
            'mask_reviewed', 'review_coverage_mask', 'config', 'phenotypes');
    end
end

function value = compact(schema, values)
    available = isfinite(values);
    value = struct('version', 'magma_phenotype_numeric_summary_v4', ...
        'schema_version', schema.version, 'n_features', schema.n_features, ...
        'feature_names', {schema.feature_names}, 'values', double(values), ...
        'available', logical(available), ...
        'coverage_fraction', double(available), ...
        'missing_reason', {repmat({''}, 1, schema.n_features)}, ...
        'phenotype_group', {schema.phenotype_group}, ...
        'feature_role', {schema.feature_role}, 'units', {schema.units});
end

function info = result_file_info(root)
    files = dir(fullfile(root, 'Sub*_M*', '*_results.mat'));
    info = sortrows(table(string({files.name})', [files.bytes]', ...
        [files.datenum]', 'VariableNames', {'name','bytes','datenum'}));
end
