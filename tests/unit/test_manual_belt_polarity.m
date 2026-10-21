function tests = test_manual_belt_polarity
% Synthetic command-line decisions; never prompt an automated test runner.
    tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    testCase.TestData.original_path = path;
    folder = tempname;
    mkdir(folder);
    testCase.TestData.input_folder = folder;
    fid = fopen(fullfile(folder, 'input.m'), 'w');
    cleanup_file = onCleanup(@() fclose(fid));
    fprintf(fid, '%s\n', ...
        'function answer = input(prompt, format)', ...
        'global MAGMA_POLARITY_TEST_INPUTS MAGMA_POLARITY_TEST_PROMPTS', ...
        'assert(strcmp(format, ''s''), ''Input must be read as text.'');', ...
        'MAGMA_POLARITY_TEST_PROMPTS{end+1} = prompt;', ...
        'if isempty(MAGMA_POLARITY_TEST_INPUTS)', ...
        '    error(''MAGMA:Test:UnexpectedInput'', ''Unexpected polarity prompt.'');', ...
        'end', ...
        'answer = MAGMA_POLARITY_TEST_INPUTS{1};', ...
        'MAGMA_POLARITY_TEST_INPUTS(1) = [];', ...
        'end');
    clear cleanup_file;
    addpath(folder, '-begin');
end

function teardownOnce(testCase)
    path(testCase.TestData.original_path);
    clear input;
    rmdir(testCase.TestData.input_folder, 's');
    clear global MAGMA_POLARITY_TEST_INPUTS MAGMA_POLARITY_TEST_PROMPTS;
end

function setup(~)
    global MAGMA_POLARITY_TEST_INPUTS MAGMA_POLARITY_TEST_PROMPTS;
    MAGMA_POLARITY_TEST_INPUTS = {};
    MAGMA_POLARITY_TEST_PROMPTS = {};
end

function testMissingModeDefaultsToManualAndFlipsOnlyThoracicDataAndTrend(testCase)
    [raw, config] = fixture();
    config.preprocessing = rmfield(config.preprocessing, 'relative_belt_polarity_mode');
    config.detrend.method = 'hpfilter';
    baseline = config;
    baseline.preprocessing.check_relative_belt_polarity = false;
    [unchanged, ~, trend] = preprocess_data(raw, baseline);
    queue_input('1');
    output = evalc('[actual, result, actual_trend] = preprocess_data(raw, config);');

    verifyEqual(testCase, actual(:,2), -unchanged(:,2));
    verifyEqual(testCase, actual_trend(:,2), -trend(:,2));
    verifyEqual(testCase, actual(:,[1 3 4]), unchanged(:,[1 3 4]));
    verifyTrue(testCase, isequaln(actual_trend(:,[1 3 4]), trend(:,[1 3 4])));
    verifyTrue(testCase, result.preprocessing.belt_polarity_qc.thoracic_polarity_flipped);
    verifyFalse(testCase, result.preprocessing.belt_polarity_qc.diaphragm_polarity_flipped);
    verifyEqual(testCase, result.preprocessing.belt_polarity_qc.corrected_belt, 'Resp-Lungs');
    verifyTrue(testCase, contains(output, 'Recording: Sub86_M1'));
    verifyTrue(testCase, contains(output, 'paradoxical respiratory movement'));
    verifyEqual(testCase, prompt_count(), 1);
end

function testFlipOnlyAbdominalDataAndTrend(testCase)
    [raw, config] = fixture();
    config.detrend.method = 'hpfilter';
    baseline = config;
    baseline.preprocessing.check_relative_belt_polarity = false;
    [unchanged, ~, trend] = preprocess_data(raw, baseline);
    queue_input('2');
    evalc('[actual, result, actual_trend] = preprocess_data(raw, config);');

    verifyEqual(testCase, actual(:,4), -unchanged(:,4));
    verifyEqual(testCase, actual_trend(:,4), -trend(:,4));
    verifyEqual(testCase, actual(:,1:3), unchanged(:,1:3));
    verifyTrue(testCase, isequaln(actual_trend(:,1:3), trend(:,1:3)));
    verifyEqual(testCase, result.preprocessing.belt_polarity_qc.manual_choice, 2);
    verifyFalse(testCase, result.preprocessing.belt_polarity_qc.thoracic_polarity_flipped);
    verifyTrue(testCase, result.preprocessing.belt_polarity_qc.diaphragm_polarity_flipped);
end

function testKeepBothBelts(testCase)
    [raw, config] = fixture();
    queue_input('0');
    evalc('[actual, result] = preprocess_data(raw, config);');
    verifyEqual(testCase, actual, raw);
    verifyFalse(testCase, result.preprocessing.belt_polarity_qc.flipped);
    verifyEqual(testCase, result.preprocessing.belt_polarity_qc.reason, 'manual_keep_both');
end

function testInvalidChoicesRepeatWithoutEvaluatingExpressions(testCase)
    [raw, config] = fixture();
    queue_input('', 'x', '1+1', '[1 2]', 'NaN', '-1', '4', '1.5', ' 2 ');
    output = evalc('[actual, result] = preprocess_data(raw, config);');
    verifyEqual(testCase, prompt_count(), 9);
    verifyEqual(testCase, count(output, 'Invalid choice.'), 8);
    verifyEqual(testCase, result.preprocessing.belt_polarity_qc.manual_choice, 2);
    verifyEqual(testCase, actual(:,4), -raw(:,4));
end

function testDeferredDecisionStopsDirectPreprocessing(testCase)
    [raw, config] = fixture();
    queue_input('3');
    verifyError(testCase, @() preprocess_data(raw, config), ...
        'MAGMA:Respiration:PolarityReviewDeferred');
end

function testDisabledCheckDoesNotPromptOrValidateUnusedMode(testCase)
    [raw, config] = fixture();
    config.preprocessing.check_relative_belt_polarity = false;
    config.preprocessing.relative_belt_polarity_mode = 'unused';
    [actual, result] = preprocess_data(raw, config);
    verifyEqual(testCase, actual, raw);
    verifyFalse(testCase, result.preprocessing.belt_polarity_qc.checked);
    verifyEqual(testCase, prompt_count(), 0);
end

function testAlignedTransientWeakAndShortInputsDoNotPrompt(testCase)
    [raw, config] = fixture();
    aligned = raw;
    aligned(:,4) = -aligned(:,4);
    transient = aligned;
    transient(1201:1500,4) = -transient(1201:1500,4);
    weak = raw;
    t = (0:size(raw,1)-1)' / config.fs;
    weak(:,4) = sin(2*pi*0.37*t);
    examples = {aligned, transient, weak, raw(1:600,:)};
    for i = 1:numel(examples)
        [actual, result] = preprocess_data(examples{i}, config);
        verifyEqual(testCase, actual, examples{i});
        verifyFalse(testCase, result.preprocessing.belt_polarity_qc.flipped);
    end
    verifyEqual(testCase, prompt_count(), 0);
end

function testInvalidModeHasClearError(testCase)
    [raw, config] = fixture();
    for mode = {'invalid', 1, ["manual" "auto"]}
        config.preprocessing.relative_belt_polarity_mode = mode{1};
        verifyError(testCase, @() preprocess_data(raw, config), ...
            'MAGMA:Config:InvalidBeltPolarityMode');
    end
end

function testEachPersistentCorrelationConditionIsRequiredBeforePrompting(testCase)
    [raw, config] = fixture();
    t = raw(:,1);
    weak_inverse = raw;
    weak_inverse(:,4) = -0.6*sin(2*pi*0.23*t) + 0.8*sin(2*pi*0.37*t);
    [actual, result] = preprocess_data(weak_inverse, config);
    qc = result.preprocessing.belt_polarity_qc;
    verifyEqual(testCase, actual, weak_inverse);
    verifyGreaterThan(testCase, qc.median_window_corr, -0.65);
    verifyEqual(testCase, qc.negative_window_fraction, 1);

    sparse_inverse = raw;
    sparse_inverse(t >= 120,4) = sin(2*pi*0.37*t(t >= 120));
    [actual, result] = preprocess_data(sparse_inverse, config);
    qc = result.preprocessing.belt_polarity_qc;
    verifyEqual(testCase, actual, sparse_inverse);
    verifyGreaterThanOrEqual(testCase, qc.n_informative_windows, 3);
    verifyLessThanOrEqual(testCase, qc.median_window_corr, -0.65);
    verifyLessThan(testCase, qc.informative_window_fraction, 0.60);

    inconsistent_inverse = raw;
    inconsistent_inverse(t >= 210,4) = -raw(t >= 210,4);
    [actual, result] = preprocess_data(inconsistent_inverse, config);
    qc = result.preprocessing.belt_polarity_qc;
    verifyEqual(testCase, actual, inconsistent_inverse);
    verifyLessThanOrEqual(testCase, qc.median_window_corr, -0.65);
    verifyGreaterThanOrEqual(testCase, qc.informative_window_fraction, 0.60);
    verifyLessThan(testCase, qc.negative_window_fraction, 0.80);
    verifyEqual(testCase, prompt_count(), 0);
end

function testSameRunReprocessingReusesManualDecision(testCase)
    [raw, config] = fixture();
    queue_input('1');
    evalc('[expected, config] = preprocess_data(raw, config);');
    [actual, result] = preprocess_data(raw, config, config.preprocessing.belt_polarity_qc);
    verifyEqual(testCase, actual, expected);
    verifyEqual(testCase, result.preprocessing.belt_polarity_qc.manual_choice, 1);
    verifyEqual(testCase, prompt_count(), 1);
end

function testCacheCannotUndoManualKeepOrThoracicFlip(testCase)
    [raw, config] = fixture();
    root = tempname; mkdir(root);
    cleanup = onCleanup(@() rmdir(root, 's'));
    config.path_results_out = root;
    config.sub_results_path = root;
    feature_cache_meta = struct('cache_version',9,'subject',86,'measurement',1, ...
        'fs',config.fs,'n_samples',size(raw,1),'data_columns',{config.data_columns}, ...
        'belt_polarity_checked',true,'diaphragm_polarity_flipped',true);
    filename = fullfile(root, config.sub_features_filename);
    save(filename, 'feature_cache_meta');
    original = read_bytes(filename);
    for choice = [0 1]
        queue_input(num2str(choice));
        evalc('[actual, result] = preprocess_data(raw, config);');
        verifyEqual(testCase, actual(:,4), raw(:,4));
        verifyEqual(testCase, actual(:,2), (1-2*(choice==1))*raw(:,2));
        verifyEqual(testCase, result.preprocessing.belt_polarity_qc.manual_choice, choice);
    end
    verifyEqual(testCase, read_bytes(filename), original);
    feature_cache_meta.diaphragm_polarity_flipped = false;
    feature_cache_meta.absolute_polarity_flipped = true;
    save(filename, 'feature_cache_meta');
    original = read_bytes(filename);
    queue_input('0');
    evalc('actual = preprocess_data(raw, config);');
    verifyEqual(testCase, actual, raw);
    verifyEqual(testCase, read_bytes(filename), original);
    config.preprocessing.check_relative_belt_polarity = false;
    feature_cache_meta.absolute_polarity_flipped = false;
    feature_cache_meta.diaphragm_polarity_flipped = true;
    save(filename, 'feature_cache_meta');
    original = read_bytes(filename);
    verifyEqual(testCase, preprocess_data(raw, config), raw);
    verifyEqual(testCase, read_bytes(filename), original);
end

function testThoracicCorrectionIsSavedAndMatchedSeparatelyInCache(testCase)
    [raw, config] = fixture();
    root = tempname; mkdir(root);
    cleanup = onCleanup(@() rmdir(root, 's'));
    config.path_results_out = root;
    config.sub_results_path = root;
    queue_input('1');
    evalc('[data, config] = preprocess_data(raw, config);');
    load_or_extract_respiratory_cycles(data, config);
    filename = fullfile(root, config.sub_features_filename);
    cached = load(filename);
    verifyTrue(testCase, cached.feature_cache_meta.thoracic_polarity_flipped);
    verifyFalse(testCase, cached.feature_cache_meta.diaphragm_polarity_flipped);
    reused = load_or_extract_respiratory_cycles(data, config);
    verifyTrue(testCase, reused.provenance.loaded_from_cache);

    cached.resp_cycles.provenance.manual_review_performed = true;
    cached.resp_cycles.provenance.manual_edits_made = false;
    cached.resp_cycles.provenance.review_status = 'manual_reviewed_unchanged';
    save(filename, '-struct', 'cached');
    original = read_bytes(filename);
    queue_input('2');
    evalc('[other_data, other_config] = preprocess_data(raw, config);');
    verifyError(testCase, @() load_or_extract_respiratory_cycles(other_data, other_config), ...
        'MAGMA:Respiration:ReviewedFeatureCacheMismatch');
    verifyEqual(testCase, read_bytes(filename), original);
end

function testDeferSkipsRecordingsAndPreservesSavedFiles(testCase)
    [raw, config] = fixture();
    root = tempname; mkdir(root);
    cleanup = onCleanup(@() rmdir(root, 's'));
    config.path_results_out = root;
    config.path_data_in = root;
    config.input_filename_pattern = 'synthetic.dat';
    writematrix(raw, fullfile(root, 'synthetic.dat'), 'Delimiter', ' ');
    config.subjects = 86;
    config.measurements = [1 2];
    config.exclude_recordings = [];
    config.overwrite_results = true;
    config.overwrite_features = true;
    folder = fullfile(root, 'Sub86_M1'); mkdir(folder);
    result_file = fullfile(folder, 'Sub86_M1_results.mat');
    recording_results('save', result_file, struct('subject',86,'measure',1,'config',config));
    cache_file = fullfile(folder, 'Sub86_M1_features.mat');
    sentinel = 'keep this cache'; save(cache_file, 'sentinel');
    before_result = read_bytes(result_file);
    before_cache = read_bytes(cache_file);
    queue_input('3', '3');
    evalc('run_magma(config);');
    verifyEqual(testCase, prompt_count(), 2);
    verifyEqual(testCase, read_bytes(result_file), before_result);
    verifyEqual(testCase, read_bytes(cache_file), before_cache);
    verifyFalse(testCase, isfile(fullfile(root,'Sub86_M2','Sub86_M2_results.mat')));
    verifyFalse(testCase, isfile(fullfile(root,'Sub86_M2','Sub86_M2_features.mat')));

    config.measurements = 1;
    config.execution.mode = 'review';
    queue_input('3');
    evalc('run_magma(config);');
    verifyEqual(testCase, read_bytes(result_file), before_result);
    verifyEqual(testCase, read_bytes(cache_file), before_cache);
end

function [raw, config] = fixture()
    config = make_test_config();
    config.subject = 86; config.measure = 1;
    config.fs = 10; config.verbosity = 0;
    config.data_columns = {'Auxiliary','Resp-Lungs','SpO2','Resp-Diaphragm'};
    config = resolve_signal_channels(config);
    config.detrend.method = 'none';
    config.preprocessing.check_relative_belt_polarity = true;
    config.preprocessing.relative_belt_polarity_mode = 'manual';
    config.preprocessing.check_absolute_belt_polarity = false;
    t = (0:2999)' / config.fs;
    breath = sin(2*pi*0.23*t) + 0.18*sin(2*pi*0.46*t+0.2);
    baseline = 0.2*sin(2*pi*0.003*t);
    raw = [t breath+baseline 96+zeros(size(t)) -breath-baseline];
end

function queue_input(varargin)
    global MAGMA_POLARITY_TEST_INPUTS;
    MAGMA_POLARITY_TEST_INPUTS = varargin;
end

function n = prompt_count()
    global MAGMA_POLARITY_TEST_PROMPTS;
    n = numel(MAGMA_POLARITY_TEST_PROMPTS);
end

function bytes = read_bytes(filename)
    fid = fopen(filename, 'rb');
    cleanup = onCleanup(@() fclose(fid));
    bytes = fread(fid, Inf, '*uint8');
end
