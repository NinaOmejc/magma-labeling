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
    mask = false(100, 1);
    label_names = {'shallowB'};
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
end

function resp_ref = synthetic_saved_reference()
    lungs = struct( ...
        'end_to_start_ratio', 0.60, ...
        'change_detected', true, ...
        'change_t', 420, ...
        'change_ratio', 0.58, ...
        'quality', 'good');
    diaph = struct( ...
        'end_to_start_ratio', 0.62, ...
        'change_detected', true, ...
        'change_t', 426, ...
        'change_ratio', 0.60, ...
        'quality', 'good');
    resp_ref = struct('lungs', lungs, 'diaph', diaph, ...
        'change_pattern', 'both_similar');
end
