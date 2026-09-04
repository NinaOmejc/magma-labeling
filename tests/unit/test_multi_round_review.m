function tests = test_multi_round_review
% Deterministic tests for staged manual review without opening the GUI.
    tests = functiontests(localfunctions);
end

function testResearcherThenClinicianCompositionAndCoverage(testCase)
    config = review_config();
    defs = manual_label_definitions();
    N = 100;
    automatic = empty_event_sets(defs);
    automatic.rapid = indexed_event('rapid', 11, 20, config.fs);
    automatic_before = automatic;

    researcher_edits = automatic;
    researcher_edits.rapid = indexed_event('rapid', 11, 30, config.fs);
    researcher_edits.deep = indexed_event('deep', 61, 70, config.fs);
    researcher_scope = false(N, numel(defs));
    researcher_scope(:, strcmp({defs.field}, 'rapid')) = true;
    researcher_scope(:, strcmp({defs.field}, 'deep')) = true;
    researcher_meta = struct('round_id', 1, ...
        'timestamp', '2026-01-01T10:00:00Z', ...
        'reviewer_role', 'researcher', 'start_from', 'automatic', ...
        'source_review_round', NaN);
    [researcher_state, round1] = create_manual_review_round( ...
        automatic, researcher_edits, researcher_scope, config, researcher_meta);

    clinician_edits = researcher_state;
    clinician_edits.rapid = indexed_event('rapid', 21, 30, config.fs);
    clinician_edits.deep = empty_events(); % Outside the clinician scope: ignored.
    clinician_scope = false(N, numel(defs));
    clinician_scope(11:20, strcmp({defs.field}, 'rapid')) = true;
    clinician_meta = struct('round_id', 2, ...
        'timestamp', '2026-01-02T10:00:00Z', ...
        'reviewer_role', 'clinician', 'start_from', 'latest_reviewed', ...
        'source_review_round', 1);
    [clinician_state, round2] = create_manual_review_round( ...
        researcher_state, clinician_edits, clinician_scope, config, clinician_meta);

    rapid = strcmp({config.labels.short}, 'rapid');
    deep = strcmp({config.labels.short}, 'deep');
    verifyEqual(testCase, automatic, automatic_before);
    verifyTrue(testCase, all(round1.mask(11:30, rapid)));
    verifyTrue(testCase, all(round1.mask(61:70, deep)));
    verifyFalse(testCase, any(round2.mask(11:20, rapid)));
    verifyTrue(testCase, all(round2.mask(21:30, rapid)));
    verifyTrue(testCase, all(round2.mask(61:70, deep)), ...
        'Values outside the clinician scope must be inherited from round 1.');
    verifyTrue(testCase, all(round1.review_mask(:, rapid)));
    verifyTrue(testCase, all(round1.review_mask(:, deep)));
    verifyEqual(testCase, find(round2.review_mask(:, rapid)), (11:20)');
    verifyFalse(testCase, any(round2.review_mask(:, deep)));
    verifyEqual(testCase, round1.reviewer_role, 'researcher');
    verifyEqual(testCase, round1.start_from, 'automatic');
    verifyEqual(testCase, round2.reviewer_role, 'clinician');
    verifyEqual(testCase, round2.start_from, 'latest_reviewed');
    verifyEqual(testCase, round2.source_review_round, 1);
    verifyEqual(testCase, clinician_state.deep, researcher_state.deep);

    history = [round1; round2];
    verifyEqual(testCase, history(1).mask, round1.mask, ...
        'Appending a later round must not rewrite earlier history.');
    verifyEqual(testCase, history(1).review_mask, round1.review_mask);
end

function testActiveLayerUsesNewestValuesButOnlyNewestCoverage(testCase)
    config = review_config();
    defs = manual_label_definitions();
    N = 80;
    automatic = empty_event_sets(defs);
    first_edits = automatic;
    first_edits.deep = indexed_event('deep', 51, 60, config.fs);
    first_scope = false(N, numel(defs));
    first_scope(:, strcmp({defs.field}, 'deep')) = true;
    [first_state, round1] = create_manual_review_round(automatic, first_edits, ...
        first_scope, config, struct('round_id', 1, ...
        'timestamp', 'round-1', 'reviewer_role', 'researcher', ...
        'start_from', 'automatic', 'source_review_round', NaN));

    second_edits = first_state;
    second_edits.rapid = indexed_event('rapid', 10, 20, config.fs);
    second_scope = false(N, numel(defs));
    second_scope(10:20, strcmp({defs.field}, 'rapid')) = true;
    [active_sets, round2] = create_manual_review_round(first_state, second_edits, ...
        second_scope, config, struct('round_id', 2, ...
        'timestamp', 'round-2', 'reviewer_role', 'expert', ...
        'start_from', 'latest_reviewed', 'source_review_round', 1));

    status = status_struct(round2.review_status, defs, {config.labels.short});
    manual = struct('reviewed_fields', {{'rapid'}}, ...
        'status_by_label', status, ...
        'review_coverage_mask', second_scope, ...
        'review_history', [round1; round2], ...
        'review_provenance', struct('version', 'manual_review_provenance_v1', ...
        'latest_round_id', 2, 'latest_reviewer_role', 'expert', ...
        'start_from', 'latest_reviewed', 'source_review_round', 1, ...
        'number_of_rounds', 2, 'most_recent_round_id', 2));
    annotations = assemble_annotation_layers(automatic, active_sets, manual, ...
        empty_sigh_review(), N, config);

    rapid = strcmp(annotations.label_names, 'rapid');
    deep = strcmp(annotations.label_names, 'deep');
    verifyEqual(testCase, annotations.mask_weak, ...
        events_to_time_mask(normalize_event_types_and_meta(empty_events()), N, config));
    verifyTrue(testCase, all(annotations.mask_reviewed(10:20, rapid)));
    verifyTrue(testCase, all(annotations.mask_reviewed(51:60, deep)));
    verifyEqual(testCase, find(annotations.gold_review_mask(:, rapid)), (10:20)');
    verifyFalse(testCase, any(annotations.gold_review_mask(:, deep)));
    verifyEqual(testCase, annotations.review_history(1).mask, round1.mask);
    verifyEqual(testCase, annotations.review_provenance.latest_round_id, 2);
end

function testReviewedNegativeDiffersFromUnreviewedWithinRound(testCase)
    config = review_config();
    defs = manual_label_definitions();
    N = 40;
    source = empty_event_sets(defs);
    source.rapid = indexed_event('rapid', 5, 15, config.fs);
    edited = source;
    edited.rapid = empty_events();
    scope = false(N, numel(defs));
    scope(5:10, strcmp({defs.field}, 'rapid')) = true;
    [~, round_info] = create_manual_review_round(source, edited, scope, ...
        config, struct('round_id', 1, 'timestamp', 'fixed', ...
        'reviewer_role', 'clinician', 'start_from', 'automatic', ...
        'source_review_round', NaN));
    rapid = strcmp({config.labels.short}, 'rapid');
    verifyTrue(testCase, round_info.review_mask(7, rapid));
    verifyFalse(testCase, round_info.mask(7, rapid));
    verifyFalse(testCase, round_info.review_mask(30, rapid));
    verifyFalse(testCase, round_info.mask(30, rapid));
    verifyEqual(testCase, round_info.review_status{rapid}, 'reviewed_rejected');
end

function testSavedLatestReviewedStateLoadsWithoutChangingAutomatic(testCase)
    output_dir = tempname;
    mkdir(output_dir);
    cleanup = onCleanup(@() rmdir(output_dir, 's'));
    config = review_config();
    config.path_results_out = output_dir;
    config.sub_results_path = output_dir;
    config.LabelEdit.apply_saved_edits = true;
    config.LabelEdit.start_from = 'latest_reviewed';
    defs = manual_label_definitions();
    N = 50;
    automatic = empty_event_sets(defs);
    automatic.rapid = indexed_event('rapid', 5, 10, config.fs);
    automatic_before = automatic;
    researcher_edits = automatic;
    researcher_edits.rapid = indexed_event('rapid', 5, 20, config.fs);
    scope = false(N, numel(defs));
    scope(:,strcmp({defs.field}, 'rapid')) = true;
    [active_sets, round1] = create_manual_review_round(automatic, ...
        researcher_edits, scope, config, struct('round_id', 1, ...
        'timestamp', '2026-01-01T00:00:00Z', ...
        'reviewer_role', 'researcher', 'start_from', 'automatic', ...
        'source_review_round', NaN));

    manual_label_weak_event_sets = automatic;
    manual_label_event_sets = active_sets;
    manual_label_review_mask = scope;
    manual_label_review_history = round1;
    manual_label_active_round_id = 1;
    manual_label_review_provenance = struct();
    manual_label_edit_meta = struct('version', 5, 'schema_version', 5, ...
        'subject', config.subject, 'measure', config.measure, ...
        'n_samples', N, 'fs', config.fs, ...
        'label_names', {{defs.type}}, 'active_round_id', 1);
    edit_file = fullfile(output_dir, sprintf('Sub%d_M%d%s', ...
        config.subject, config.measure, config.LabelEdit.filename_suffix));
    save(edit_file, 'manual_label_weak_event_sets', ...
        'manual_label_event_sets', 'manual_label_review_mask', ...
        'manual_label_review_history', 'manual_label_active_round_id', ...
        'manual_label_review_provenance', 'manual_label_edit_meta');

    [loaded, info] = manual_edit_label_events(zeros(N,6), config, automatic);
    verifyEqual(testCase, automatic, automatic_before);
    verifyEqual(testCase, loaded.rapid.start_idx, 5);
    verifyEqual(testCase, loaded.rapid.end_idx, 20);
    verifyNotEqual(testCase, loaded.rapid.end_idx, automatic.rapid.end_idx);
    verifyEqual(testCase, info.review_provenance.latest_round_id, 1);
    verifyEqual(testCase, info.review_provenance.latest_reviewer_role, 'researcher');
    verifyEqual(testCase, info.review_history(1).mask, round1.mask);
    verifyEqual(testCase, info.loaded_schema_version, 5);
end

function testLatestReviewedRequiresAnExistingReview(testCase)
    output_dir = tempname;
    mkdir(output_dir);
    cleanup = onCleanup(@() rmdir(output_dir, 's'));
    config = review_config();
    config.path_results_out = output_dir;
    config.sub_results_path = output_dir;
    config.LabelEdit.manual_control = true;
    config.LabelEdit.start_from = 'latest_reviewed';
    defs = manual_label_definitions();
    verifyError(testCase, @() manual_edit_label_events( ...
        zeros(20,6), config, empty_event_sets(defs)), ...
        'MAGMA:ManualLabelEdit:MissingLatestReviewed');
end

function config = review_config()
    config = make_test_config();
    config.fs = 1;
end

function sets = empty_event_sets(defs)
    sets = struct();
    for i = 1:numel(defs)
        sets.(defs(i).field) = empty_events();
    end
end

function event = indexed_event(type, start_idx, end_idx, fs)
    event = struct('type', type, 'start_idx', start_idx, 'end_idx', end_idx, ...
        'start_t', (start_idx - 1) / fs, 'end_t', end_idx / fs, ...
        'duration', (end_idx - start_idx + 1) / fs);
end

function status = status_struct(values, defs, label_names)
    status = struct();
    for i = 1:numel(defs)
        status.(defs(i).field) = values{strcmp(label_names, defs(i).type)};
    end
end

function review = empty_sigh_review()
    review = struct('reviewed', false, 'status', 'unreviewed', ...
        'weak_events', empty_events(), 'reviewed_events', empty_events());
end
