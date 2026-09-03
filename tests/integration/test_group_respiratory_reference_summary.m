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
    % Historical v2 names deliberately exercise semantic (not positional)
    % migration into the v3 group columns.
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
    verifyEqual(testCase, group_table.label_deep_duration_sec, 40/200, 'AbsTol', eps);
    verifyEqual(testCase, group_table.label_deep_fraction, 0.40, 'AbsTol', eps);
    verifyEqual(testCase, group_table.label_deep_available, 1);
    verifyEqual(testCase, group_table.label_thoracic_available, 0);
    verifyTrue(testCase, isnan(group_table.label_thoracic_duration_sec));
    verifyTrue(testCase, isnan(group_table.label_thoracic_fraction));
    verifyTrue(testCase, isnan(group_table.events_thoracic_count));
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
    verifyEqual(testCase, group_table.label_deep_available, 1);
    verifyEqual(testCase, group_table.label_deep_duration_sec, 0);
    verifyEqual(testCase, group_table.label_deep_fraction, 0);
    verifyEqual(testCase, group_table.label_thoracic_available, 1);
    verifyEqual(testCase, group_table.label_thoracic_duration_sec, 0);
    verifyEqual(testCase, group_table.label_thoracic_fraction, 0);
    verifyEqual(testCase, group_table.events_thoracic_count, 0);
    verifyEqual(testCase, string(group_table.label_schema_version), ...
        "independent_labels_v3_11class");
end

function testLegacyEventsAndRejectedRunsUseSemanticIdentityAndIndices(testCase)
    results_root = tempname;
    subject_dir = fullfile(results_root, 'Sub8_M1');
    mkdir(subject_dir);
    cleanup_dir = onCleanup(@() rmdir(results_root, 's'));

    current = get_config();
    subject = 8;
    measure = 1;
    label_names = {current.labels.short};
    label_available = true(1,11);
    mask_weak = false(20,11);
    config = struct('fs',10);
    events_weak = struct('type','rapidB','start_idx',1,'end_idx',10, ...
        'start_t',50,'end_t',60,'duration',999);
    record = struct('label','rapidB','detector','detect_rapid_breathing', ...
        'belt','lungs','boundary_method','test', ...
        'candidate_start_t',0,'candidate_end_t',31, ...
        'localized_start_t',1,'localized_end_t',29, ...
        'localized_duration_sec',28,'final_min_duration_sec',30, ...
        'passes_final_min_duration',false, ...
        'rejection_reason','localized_duration_below_minimum', ...
        'uncertainty_sec',1,'evidence_source','reviewed_breathwise_rr_bpm');
    event_boundary_info = struct('version','test','rapidB',struct('events',record));
    save(fullfile(subject_dir,'Sub8_M1_labels.mat'), 'subject','measure', ...
        'label_names','label_available','mask_weak','events_weak', ...
        'event_boundary_info','config');

    build_group_label_table(results_root);
    event_table = readtable(fullfile(results_root,'group_analysis', ...
        'cohort_event_durations.csv'),'TextType','string');
    verifyEqual(testCase,event_table.label,"rapid");
    verifyEqual(testCase,event_table.duration_sec,1,'AbsTol',eps);
    boundary_table = readtable(fullfile(results_root,'group_analysis', ...
        'cohort_localized_boundary_qc.csv'),'TextType','string');
    verifyEqual(testCase,boundary_table.label,"rapid");
    verifyEqual(testCase,boundary_table.localized_duration_sec,28);
    verifyEqual(testCase,boundary_table.duration_shortfall_sec,2);
    qc_data = load(fullfile(results_root,'group_analysis','cohort_qc_summary.mat'));
    rapid_row = qc_data.cohort_qc.by_label.label == "rapid";
    verifyEqual(testCase, ...
        qc_data.cohort_qc.by_label.rejected_localized_run_count(rapid_row),1);
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
