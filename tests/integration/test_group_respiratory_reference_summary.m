function tests = test_group_respiratory_reference_summary
% Verify the existing group table exposes the compact Phase 2A diagnostics.
    tests = functiontests(localfunctions);
end

function testSavedRespiratoryReferenceIsSummarized(testCase)
    results_root = tempname;
    subject_dir = fullfile(results_root, 'Sub5_M2');
    mkdir(subject_dir);
    cleanup_dir = onCleanup(@() rmdir(results_root, 's'));

    subject = 5;
    measure = 2;
    mask = false(100, 2);
    mask(21:60, 2) = true;
    label_names = {'shallowB', 'deepB'};
    config = struct('fs', 200);
    resp_ref = synthetic_saved_reference();
    save(fullfile(subject_dir, 'Sub5_M2_labels.mat'), ...
        'subject', 'measure', 'mask', 'label_names', 'config', 'resp_ref');

    group_table = build_group_label_table(results_root);

    verifyEqual(testCase, height(group_table), 1);
    verifyEqual(testCase, group_table.subject, 5);
    verifyEqual(testCase, group_table.measurement, 2);
    verifyEqual(testCase, group_table.lungs_start_end_ratio, 0.60, 'AbsTol', eps);
    verifyEqual(testCase, group_table.lungs_change_detected, 1);
    verifyEqual(testCase, group_table.lungs_change_t, 420);
    verifyEqual(testCase, group_table.lungs_change_ratio, 0.58, 'AbsTol', eps);
    verifyEqual(testCase, string(group_table.lungs_quality), "good");
    verifyEqual(testCase, string(group_table.diaph_quality), "good");
    verifyEqual(testCase, string(group_table.change_pattern), "both_similar");
    verifyEqual(testCase, group_table.lungs_session_reference_raw_units, 1.1, 'AbsTol', eps);
    verifyEqual(testCase, group_table.lungs_global_reference_raw_units, 0.9, 'AbsTol', eps);
    verifyEqual(testCase, group_table.lungs_global_to_session_ratio, 0.9/1.1, 'AbsTol', eps);
    verifyEqual(testCase, string(group_table.lungs_reference_quality), "step_candidate");
    verifyEqual(testCase, string(group_table.lungs_reference_action), "retain_data_no_correction");
    verifyEqual(testCase, group_table.label_deepB_duration_sec, 40/200, 'AbsTol', eps);
    verifyEqual(testCase, group_table.label_deepB_fraction, 0.40, 'AbsTol', eps);
    verifyEqual(testCase, group_table.label_deepB_available, 1);
    verifyEqual(testCase, group_table.label_thorDomB_available, 0);
    verifyTrue(testCase, isnan(group_table.label_thorDomB_duration_sec));
    verifyTrue(testCase, isnan(group_table.label_thorDomB_fraction));
    verifyTrue(testCase, isnan(group_table.events_thorDomB_count));
    verifyEqual(testCase, string(group_table.label_schema_version), "legacy_unspecified");

    dictionary_file = fullfile(results_root, 'group_analysis', ...
        'group_measure_comparability.csv');
    verifyTrue(testCase, isfile(dictionary_file));
    dictionary = readtable(dictionary_file, 'Delimiter', ',', ...
        'TextType', 'string', 'VariableNamingRule', 'preserve');
    verifyTrue(testCase, any(dictionary.measure_family == "respiratory_rate" & ...
        dictionary.comparability == "absolute_comparable_across_subjects"));
    verifyTrue(testCase, any(dictionary.measure_family == "belt_amplitude_ratio" & ...
        dictionary.comparability == "within_record_normalized"));
    verifyTrue(testCase, any(dictionary.measure_family == "thoracic_to_abdominal_ratio" & ...
        dictionary.comparability == "within_record_normalized"));
    verifyTrue(testCase, any(dictionary.measure_family == "raw_belt_amplitude" & ...
        dictionary.comparability == "not_safely_comparable_across_subjects"));
end

function testAssessedZeroLabelsRemainDistinctFromUnavailable(testCase)
    results_root = tempname;
    subject_dir = fullfile(results_root, 'Sub42_M3');
    mkdir(subject_dir);
    cleanup_dir = onCleanup(@() rmdir(results_root, 's'));

    current = get_config();
    subject = 42;
    measure = 3;
    mask = false(100, numel(current.labels));
    label_names = {current.labels.short};
    label_available = true(1, numel(label_names));
    label_schema_version = current.label_schema_version;
    config = struct('fs', 10);
    save(fullfile(subject_dir, 'Sub42_M3_labels.mat'), ...
        'subject', 'measure', 'mask', 'label_names', 'label_available', ...
        'label_schema_version', 'config');

    group_table = build_group_label_table(results_root);
    verifyEqual(testCase, group_table.label_deepB_available, 1);
    verifyEqual(testCase, group_table.label_deepB_duration_sec, 0);
    verifyEqual(testCase, group_table.label_deepB_fraction, 0);
    verifyEqual(testCase, group_table.label_thorDomB_available, 1);
    verifyEqual(testCase, group_table.label_thorDomB_duration_sec, 0);
    verifyEqual(testCase, group_table.label_thorDomB_fraction, 0);
    verifyEqual(testCase, group_table.events_thorDomB_count, 0);
    verifyEqual(testCase, string(group_table.label_schema_version), ...
        "independent_labels_v2_11class");
end

function resp_ref = synthetic_saved_reference()
    lungs = struct( ...
        'session', struct('value', 1.1, 'n_breaths', 80, 'available', true), ...
        'global', struct('value', 0.9, 'n_breaths', 300, 'available', true), ...
        'global_to_session_ratio', 0.9/1.1, ...
        'reference_quality', 'step_candidate', ...
        'reference_action', 'retain_data_no_correction', ...
        'end_to_start_ratio', 0.60, ...
        'change_detected', true, ...
        'change_t', 420, ...
        'change_ratio', 0.58, ...
        'quality', 'good');
    diaph = struct( ...
        'session', struct('value', 0.8, 'n_breaths', 82, 'available', true), ...
        'global', struct('value', 0.75, 'n_breaths', 302, 'available', true), ...
        'global_to_session_ratio', 0.75/0.8, ...
        'reference_quality', 'good', ...
        'reference_action', 'retain_data_no_correction', ...
        'end_to_start_ratio', 0.62, ...
        'change_detected', true, ...
        'change_t', 426, ...
        'change_ratio', 0.60, ...
        'quality', 'good');
    resp_ref = struct('lungs', lungs, 'diaph', diaph, ...
        'change_pattern', 'both_similar');
end
