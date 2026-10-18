function tests = test_thoracic_observation
% Small synthetic persistence, evidence, and GUI commit/cancel checks.
    tests = functiontests(localfunctions);
end

function testMirrorsIdentityReversalAndRollback(testCase)
    [config, cleanup] = fixture(); %#ok<ASGLU>
    subject = config.subject; measure = config.measure;
    mask_automatic = true(4, 11);
    result_file = fullfile(config.sub_results_path, config.sub_results_filename);
    save(result_file, 'subject', 'measure', 'mask_automatic');
    marker = 'preserve reviewed landmarks';
    cache_file = fullfile(config.sub_results_path, config.sub_features_filename);
    save(cache_file, 'marker');
    hdf5 = fullfile(config.sub_results_path, sprintf('Sub%d_M%d_results.h5', subject, measure));
    h5create(hdf5, '/sentinel', [1 1]); h5write(hdf5, '/sentinel', 42);
    initial = recording_observation('load', config);
    verifyEqual(testCase, initial.status, 'not_assessed');
    observed = recording_observation('set', config, true, 'manual_label_gui', 0);
    verifyTrue(testCase, observed.pending_reanalysis);
    verifyEqual(testCase, observed.annotation_source, 'manual_label_gui');
    verifyEqual(testCase, observed.scope, 'recording');
    verifyNotEmpty(testCase, observed.timestamp);
    verifyEqual(testCase, load(result_file).mask_automatic, mask_automatic);
    verifyEqual(testCase, load(cache_file).marker, marker);
    assert_mirrors(testCase, config, observed, hdf5);
    other = config; other.measure = 2;
    other.sub_results_filename = 'Sub999_M2_results.mat';
    other.sub_features_filename = 'Sub999_M2_features.mat';
    verifyEqual(testCase, recording_observation('load', other).status, 'not_assessed');
    verifyError(testCase, @() recording_observation('set', config, false, 'manual_label_gui', 0), ...
        'MAGMA:Observation:ChangedDuringReview');

    review_file = fullfile(config.sub_results_path, 'review.mat');
    original = 77; save(review_file, 'original');
    callback = @(value) fail_review_save(review_file, value);
    verifyError(testCase, @() recording_observation('set', config, false, ...
        'manual_label_gui', observed.revision, callback, review_file), 'MAGMA:Tests:SaveFailure');
    verifyEqual(testCase, load(review_file).original, 77);
    assert_mirrors(testCase, config, observed, hdf5);
    cleared = recording_observation('set', config, false, 'manual_label_gui', observed.revision);
    verifyEqual(testCase, cleared.status, 'not_observed');
    verifyTrue(testCase, cleared.pending_reanalysis);
    assert_mirrors(testCase, config, cleared, hdf5);
    verifyEqual(testCase, h5read(hdf5, '/sentinel'), 42);
end

function testFlagExcludesThoracicButPreservesAbdomenAndRawTrace(testCase)
    [config, cleanup] = fixture(); %#ok<ASGLU>
    config.fs = 20;
    config.reference.pre_start_min = 0; config.reference.pre_end_min = 0.5;
    t = (0:1199)'/config.fs;
    data = zeros(numel(t), 6);
    data(:,4) = 0.000001*sin(2*pi*0.25*t); data(:,6) = sin(2*pi*0.25*t);
    before = data;
    config.recording_observations = recording_observation('set', config, true, 'respiration_feature_gui', 0);
    cycles = load_or_extract_respiratory_cycles(data, config);
    verifyEmpty(testCase, cycles.lungs.peak_idx);
    verifyEqual(testCase, cycles.lungs.x0, data(:,4));
    verifyTrue(testCase, cycles.diaph.ok);
    abdomen = cycles.diaph;
    session = get_session_reference_interval(size(data,1), config);
    reference = compute_respiratory_reference(data, cycles, session, config);
    features = compute_respiratory_features(data, cycles, reference, config);
    verifyFalse(testCase, features.lungs.available);
    verifyFalse(testCase, features.lungs.ignored);
    verifyTrue(testCase, features.diaph.available);
    verifyFalse(testCase, features.thoracoabdominal_balance.available);
    [events, diagnostic] = detect_apnea(data, features, reference, config);
    verifyEmpty(testCase, events);
    verifyFalse(testCase, diagnostic.raw_excursion.lungs.valid);
    phase = compute_respiratory_phase_offset_metrics(data, cycles, config);
    verifyFalse(testCase, phase.available);
    verifyEqual(testCase, phase.availability_reason, 'minimal_thoracic_excursion');
    rea = compute_respiratory_asynchrony_metrics(data, cycles, session, config);
    verifyFalse(testCase, rea.valid_analysis);
    verifyEqual(testCase, rea.error_message, 'minimal_thoracic_excursion');
    config.periodic.eami.energy_win_sec = 10;
    eami = compute_eami_periodic_breathing(data, config);
    verifyFalse(testCase, eami.lungs.available);
    verifyTrue(testCase, eami.diaph.available);
    guyot = compute_guyot_periodic_breathing(data, cycles, config);
    verifyFalse(testCase, guyot.lungs.available);
    [oriented, ~, oriented_config] = correct_respiratory_belt_polarity(data, [], config, config.fs);
    verifyEqual(testCase, oriented, data);
    verifyEqual(testCase, oriented_config.preprocessing.belt_polarity_qc.reason, 'minimal_thoracic_excursion');
    [oriented, ~, oriented_config] = determine_absolute_respiratory_polarity(data, [], config, config.fs);
    verifyEqual(testCase, oriented(:,4), data(:,4));
    verifyEqual(testCase, oriented_config.preprocessing.absolute_polarity_qc.n_valid_breaths_lungs, 0);
    verifyEqual(testCase, data, before);
    config.recording_observations = recording_observation('set', config, false, ...
        'respiration_feature_gui', config.recording_observations.revision);
    restored = load_or_extract_respiratory_cycles(data, config);
    verifyEqual(testCase, restored.diaph, abdomen);
    verifyFalse(testCase, restored.provenance.thoracic_extraction_suppressed);
    verifyEqual(testCase, config.problems.missing_lung_belt, zeros(0,2));
end

function testFeatureGuiWorksWithNoPeaksAndCancelDoesNotSave(testCase)
    [config, cleanup] = fixture(); %#ok<ASGLU>
    data = zeros(40,6);
    lungs = empty_respiration_feature('lungs'); lungs.x0 = data(:,4);
    diaph = empty_respiration_feature('diaph'); diaph.x0 = data(:,6);
    driver = gui_driver(false, true, 'Reviewed');
    cleanup_timer = onCleanup(@() stop_driver(driver));
    [~, ~, accepted, observation] = manual_edit_respiration_features(data, lungs, diaph, config);
    verifyTrue(testCase, accepted);
    verifyEqual(testCase, driver.UserData.seen, false);
    verifyEqual(testCase, observation.status, 'observed');
    clear cleanup_timer;
    driver = gui_driver(true, false, 'Cancel');
    cleanup_timer = onCleanup(@() stop_driver(driver));
    [actual_lungs, ~, accepted] = manual_edit_respiration_features(data, lungs, diaph, config);
    verifyFalse(testCase, accepted);
    verifyEqual(testCase, driver.UserData.seen, true);
    verifyEqual(testCase, actual_lungs, lungs);
    verifyEqual(testCase, recording_observation('load', config).status, 'observed');
end

function testLabelGuiSharesFlagAndRecordsOnlyAcceptedChanges(testCase)
    [config, cleanup] = fixture(); %#ok<ASGLU>
    config.execution.mode = 'review_only';
    config.LabelEdit.reviewer_role = 'clinician';
    recording_observation('set', config, true, 'respiration_feature_gui', 0);
    cycles = struct('lungs', empty_respiration_feature('lungs'), 'diaph', empty_respiration_feature('diaph'));
    defs = manual_label_definitions(); sets = struct();
    for k = 1:numel(defs), sets.(defs(k).field) = empty_events(); end
    automatic_event = struct('type', 'rapid', 'start_idx', 4, 'end_idx', 6, ...
        'start_t', 3/config.fs, 'end_t', 6/config.fs, 'duration', 3/config.fs);
    sets.rapid = automatic_event;
    edited = sets; edited.rapid.end_idx = 14;
    edited.rapid.end_t = 14/config.fs; edited.rapid.duration = 11/config.fs;
    scope = false(40,numel(defs)); scope(:,strcmp({defs.field}, 'rapid')) = true;
    [prior_sets, prior_round] = create_manual_review_round(sets, edited, scope, config, ...
        struct('round_id', 1, 'timestamp', 'saved round', 'reviewer_role', 'researcher', ...
        'start_from', 'automatic', 'source_review_round', NaN));
    edit_file = seed_review(config, sets, prior_sets, prior_round, scope, defs);
    prior_checkpoint = load(edit_file);
    config.LabelEdit.start_from = 'latest_reviewed';
    driver = gui_driver(true, false, 'Cancel');
    cleanup_timer = onCleanup(@() stop_driver(driver));
    [~, info] = manual_edit_label_events(zeros(40,6), cycles, config, sets);
    verifyTrue(testCase, info.cancelled);
    verifyEqual(testCase, recording_observation('load', config).status, 'observed');
    verifyEqual(testCase, load(info.edit_file), prior_checkpoint);
    clear cleanup_timer;
    driver = gui_driver(true, false, 'Done');
    cleanup_timer = onCleanup(@() stop_driver(driver));
    [reviewed, info] = manual_edit_label_events(zeros(40,6), cycles, config, sets);
    verifyFalse(testCase, info.cancelled);
    verifyEqual(testCase, driver.UserData.seen, true);
    verifyEqual(testCase, reviewed, prior_sets);
    verifyEqual(testCase, numel(info.review_history), 2);
    verifyEqual(testCase, info.review_history(1), prior_round);
    verifyEqual(testCase, info.recording_observations.status, 'not_observed');
    verifyTrue(testCase, info.recording_observations.pending_reanalysis);
    verifyEqual(testCase, info.recording_observations.reviewer_role, 'clinician');
    change = info.review_history(end).recording_observation_change;
    verifyEqual(testCase, change.before.status, 'observed');
    verifyEqual(testCase, change.after.status, 'not_observed');
    checkpoint = load(info.edit_file);
    verifyEqual(testCase, checkpoint.manual_label_review_history, info.review_history);
end

function testPendingClearsOnlyForSavedFullAnalysisAtCurrentRevision(testCase)
    [config, cleanup] = fixture(); %#ok<ASGLU>
    previous = recording_observation('default', config);
    hdf5 = fullfile(config.sub_results_path, 'Sub999_M1_results.h5');
    h5create(hdf5, '/sentinel', [1 1]); h5write(hdf5, '/sentinel', 42);
    write_recording_observation_hdf5(hdf5, previous, previous);
    observed = recording_observation('set', config, true, 'manual_label_gui', 0);
    results = struct('analysis_recording_observations', previous, 'mask_automatic', true(4,11));
    save_recording_results(results, [], [], config);
    verifyTrue(testCase, recording_observation('load', config).pending_reanalysis);
    results.analysis_recording_observations = observed;
    config.execution.mode = 'review_only';
    save_recording_results(results, [], [], config);
    verifyTrue(testCase, recording_observation('load', config).pending_reanalysis);
    config.execution.mode = 'analyze';
    save_recording_results(results, [], [], config);
    current = recording_observation('load', config);
    verifyFalse(testCase, current.pending_reanalysis);
    verifyEmpty(testCase, current.affected_labels);
    saved = load(fullfile(config.sub_results_path, config.sub_results_filename));
    verifyEqual(testCase, saved.recording_observations, current);
    verifyEqual(testCase, saved.mask_automatic, results.mask_automatic);
    % Disabled HDF5 export leaves its older computed outputs explicitly stale.
    payload = read_hdf5_text(hdf5, '/observations/recording_json');
    payload = jsondecode(payload{1});
    verifyFalse(testCase, payload.current.pending_reanalysis);
    verifyTrue(testCase, payload.derived_results_pending_reanalysis);
    verifyEqual(testCase, h5read(hdf5, '/sentinel'), 42);
end

function testInterruptedUpdateRequiresRecoveryAndMissingBeltPolicyIsPreserved(testCase)
    [config, cleanup] = fixture(); %#ok<ASGLU>
    config.problems.missing_lung_belt = [config.subject config.measure];
    verifyError(testCase, @() recording_observation('set', config, true, ...
        'manual_label_gui', 0), 'MAGMA:Observation:MissingBelt');
    verifyTrue(testCase, is_lung_belt_ignored(config));
    config.problems.missing_lung_belt = zeros(0,2);
    old_observation = recording_observation('set', config, true, 'manual_label_gui', 0);
    journal = fullfile(config.sub_results_path, 'Sub999_M1_recording_observations.mat.pending.mat');
    review_file = ''; review_backup = ''; review_existed = false;
    save(journal, 'old_observation', 'review_file', 'review_backup', 'review_existed');
    verifyError(testCase, @() recording_observation('load', config), 'MAGMA:Observation:IncompleteUpdate');
    recovered = recording_observation('recover', config);
    verifyEqual(testCase, recovered, old_observation);
    verifyEqual(testCase, recording_observation('load', config), old_observation);
    verifyFalse(testCase, isfile(journal));
end

function filename = seed_review(config, automatic, active, history, coverage, defs)
    manual_label_automatic_event_sets = automatic;
    manual_label_event_sets = active;
    manual_label_review_mask = coverage;
    manual_label_review_history = history;
    manual_label_active_round_id = history.round_id;
    manual_label_review_provenance = struct();
    manual_label_edit_meta = struct('version', 5, 'schema_version', 5, ...
        'subject', config.subject, 'measure', config.measure, ...
        'n_samples', size(coverage,1), 'fs', config.fs, ...
        'label_names', {{defs.type}}, 'active_round_id', history.round_id);
    filename = fullfile(config.sub_results_path, sprintf('Sub%d_M%d%s', ...
        config.subject, config.measure, config.LabelEdit.filename_suffix));
    save(filename, 'manual_label_automatic_event_sets', 'manual_label_event_sets', ...
        'manual_label_review_mask', 'manual_label_review_history', ...
        'manual_label_active_round_id', 'manual_label_review_provenance', 'manual_label_edit_meta');
end

function [config, cleanup] = fixture()
    folder = tempname; mkdir(folder);
    cleanup = onCleanup(@() remove_fixture(folder));
    config = make_test_config(folder);
    config.fs = 10;
    config.sub_results_filename = 'Sub999_M1_results.mat';
    config.sub_features_filename = 'Sub999_M1_features.mat';
    config.resp.manual_control = false;
    config.resp.smooth_sec = 0;
    config.HDF5.enabled = false;
    config.verbosity = 0;
end

function assert_mirrors(testCase, config, value, hdf5)
    result = load(fullfile(config.sub_results_path, config.sub_results_filename));
    cache = load(fullfile(config.sub_results_path, config.sub_features_filename));
    verifyEqual(testCase, result.recording_observations, value);
    verifyEqual(testCase, cache.recording_observations, value);
    text = read_hdf5_text(hdf5, '/observations/recording_json');
    payload = jsondecode(text{1});
    verifyEqual(testCase, payload.current.status, value.status);
    verifyEqual(testCase, payload.current.revision, value.revision);
    verifyEqual(testCase, payload.current.pending_reanalysis, value.pending_reanalysis);
end

function history = fail_review_save(filename, value)
    save(filename, 'value');
    error('MAGMA:Tests:SaveFailure', 'Simulated checkpoint-save failure.');
    history = []; %#ok<UNRCH>
end

function driver = gui_driver(expected, target, button)
    driver = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.1, ...
        'UserData', struct('seen', NaN, 'ticks', 0), ...
        'TimerFcn', @(source,~) drive_gui(source, expected, target, button));
    start(driver);
end

function drive_gui(driver, expected, target, button)
    state = driver.UserData; state.ticks = state.ticks + 1; driver.UserData = state;
    control = findall(0, 'Tag', 'minimal_thoracic_excursion');
    if isempty(control), return; end
    control = control(1); fig = ancestor(control, 'figure');
    if state.ticks > 100, stop(driver); close(fig); return; end
    if ~strcmp(button, 'Cancel')
        finish = findall(fig, 'Style', 'pushbutton', 'String', button);
        if isempty(finish), return; end
    end
    state.seen = logical(get(control, 'Value')); driver.UserData = state;
    if state.seen ~= expected || ~strcmp(get(control, 'Enable'), 'on')
        stop(driver); close(fig); return; % Fail the outer assertions without hanging uiwait.
    end
    set(control, 'Value', target); callback = get(control, 'Callback'); callback(control, []);
    stop(driver);
    if strcmp(button, 'Cancel')
        close(fig);
    else
        callback = get(finish(1), 'Callback'); callback(finish(1), []);
    end
end

function stop_driver(driver)
    if isvalid(driver), stop(driver); delete(driver); end
    controls = findall(0, 'Tag', 'minimal_thoracic_excursion');
    for k = 1:numel(controls), delete(ancestor(controls(k), 'figure')); end
end

function remove_fixture(folder)
    assert(startsWith(folder, tempdir) && ~strcmp(folder, tempdir));
    rmdir(folder, 's');
end
