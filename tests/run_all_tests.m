function results = run_all_tests()
% run_all_tests  Run all deterministic, non-interactive repository tests.

    tests_root = fileparts(mfilename('fullpath'));
    repo_root = fileparts(tests_root);
    original_path = path;
    cleanup_path = onCleanup(@() path(original_path));

    addpath(genpath(fullfile(repo_root, 'src')));
    addpath(genpath(tests_root));

    suite = testsuite(tests_root, 'IncludeSubfolders', true);
    runner = matlab.unittest.TestRunner.withTextOutput;
    results = runner.run(suite);

    if any([results.Failed])
        error('MAGMA:TestsFailed', '%d of %d tests failed.', ...
            nnz([results.Failed]), numel(results));
    end
end
