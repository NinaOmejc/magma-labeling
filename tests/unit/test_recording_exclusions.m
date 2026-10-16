function tests = test_recording_exclusions
% Focused validation and skip checks; no recordings or detectors are run.
    tests = functiontests(localfunctions);
end

function testValidLists(testCase)
    verifyEqual(testCase, resolve_excluded_recordings(struct()), zeros(0, 2));
    verifyEqual(testCase, resolve_excluded_recordings(struct('exclude_recordings', [])), zeros(0, 2));
    pairs = [3 1; 3 2; 23 1; 0 4];
    verifyEqual(testCase, resolve_excluded_recordings(struct('exclude_recordings', pairs)), pairs);
    verifyEqual(testCase, resolve_excluded_recordings(struct('exclude_recordings', int32(pairs))), pairs);
end

function testInvalidLists(testCase)
    invalid = {[1 2 3], [1; 2], '23 1', {23, 1}, true(1, 2), ...
        [NaN 1], [Inf 1], [-1 1], [1.5 1], [1 0], [1 5], [1 1.5], [1+1i 1]};
    for k = 1:numel(invalid)
        config = struct(); config.exclude_recordings = invalid{k};
        verifyError(testCase, @() resolve_excluded_recordings(config), ...
            'MAGMA:Config:InvalidExcludedRecordings');
    end
end

function testRunnerSkipsBeforeLoading(testCase)
    [config, cleanup] = skip_config(); %#ok<ASGLU>
    config.exclude_recordings = [23 1; 23 2];
    output = evalc('run_magma(config);');
    verifyEqual(testCase, count(output, 'Skipping excluded recording:'), 2);
    verifyEmpty(testCase, dir(fullfile(config.path_results_out, 'Sub*')));
    saved = load(fullfile(config.path_results_out, 'analysis_configuration.mat'), 'config');
    verifyEqual(testCase, saved.config.subjects, 23);
    verifyEqual(testCase, saved.config.measurements, [1 2]);
end

function testOtherMeasurementRemainsEligible(testCase)
    [config, cleanup] = skip_config(); %#ok<ASGLU>
    config.exclude_recordings = [23 1];
    try
        run_magma(config);
        verifyFail(testCase, 'Expected the missing M2 input to be requested.');
    catch ex
        verifyTrue(testCase, contains(ex.message, 'Sub23_Pom2_DeTr_Norm.dat'));
    end
    verifyFalse(testCase, isfolder(fullfile(config.path_results_out, 'Sub23_M1')));
    verifyTrue(testCase, isfolder(fullfile(config.path_results_out, 'Sub23_M2')));
end

function [config, cleanup] = skip_config()
    root = tempname; mkdir(root);
    cleanup = onCleanup(@() remove_test_root(root));
    config = get_config_defaults();
    config.path_results_out = root;
    config.path_data_in = fullfile(root, 'no raw data');
    config.subjects = 23; config.measurements = [1 2];
    config.execution.mode = 'analyze';
end

function remove_test_root(root)
    assert(startsWith(root, tempdir) && ~strcmp(root, tempdir));
    rmdir(root, 's');
end
