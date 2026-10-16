function tests = test_png_export
% Lightweight tests: synthetic figures/data and temporary folders only.
    tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    testCase.TestData.root = tempname;
    mkdir(testCase.TestData.root);
end

function teardownOnce(testCase)
    root = testCase.TestData.root;
    assert(startsWith(root, tempdir) && ~strcmp(root, tempdir));
    rmdir(root, 's');
end

function testStringPathsThroughLoader(testCase)
    config = get_config_defaults();
    config.path_results_out = string(fullfile(testCase.TestData.root, 'string output'));
    config.path_data_in = string(fullfile(testCase.TestData.root, 'string input'));
    mkdir(config.path_data_in);
    config.subject = 42; config.measure = 1;
    config.input_filename_pattern = 'synthetic_Sub{subject}_M{measure}.dat';
    config.plot_raw_data = false;
    filename = fullfile(config.path_data_in, 'synthetic_Sub42_M1.dat');
    writematrix(zeros(10, numel(config.data_columns)), filename, 'Delimiter', 'tab');
    [data, actual, do_analysis] = load_raw_data(config);
    verifyTrue(testCase, do_analysis);
    verifySize(testCase, data, [10 numel(config.data_columns)]);
    verifyEqual(testCase, actual.sub_results_path, ...
        fullfile(config.path_results_out, 'Sub42_M1'));
    verifyTrue(testCase, isfolder(actual.sub_results_path));
    verifyEmpty(testCase, dir(fullfile(actual.sub_results_path, 'tp*')));
end

function testSpaceAndUnicodeDiagnosticPreservesExistingTarget(testCase)
    config = struct('path_results_out', fullfile(testCase.TestData.root, ...
        ['PNG space ' char([382 233])]));
    folder = fullfile(config.path_results_out, 'Sub42_M1');
    mkdir(folder);
    filename = fullfile(folder, 'Sub42_M1_shallow_breathing.png');
    fid = fopen(filename, 'w'); fwrite(fid, 'DO NOT REPLACE'); fclose(fid);
    before = dir(folder);
    captured_log = evalc('report = diagnose_png_export(config, 42, 1);');
    verifyTrue(testCase, report.output.write_ok);
    verifyTrue(testCase, report.temp.write_ok);
    verifyTrue(testCase, report.target_openable);
    verifyNumElements(testCase, report.tests, 4);
    verifyTrue(testCase, all([report.tests.ok]));
    verifyEqual(testCase, fileread(filename), 'DO NOT REPLACE');
    after = dir(folder);
    verifyEqual(testCase, {after.name}, {before.name});
end

function testBadOutputStillTestsTempdir(testCase)
    blocked = fullfile(testCase.TestData.root, 'file instead of folder');
    fid = fopen(blocked, 'w'); fwrite(fid, 'keep'); fclose(fid);
    config = struct('path_results_out', blocked, 'plot_dpi', 80);
    captured_log = evalc('report = diagnose_png_export(config, 42, 1);');
    verifyFalse(testCase, report.output.mkdir_ok);
    verifyFalse(testCase, report.output.write_ok);
    temp_tests = strcmp({report.tests.folder}, tempdir);
    verifyEqual(testCase, nnz(temp_tests), 2);
    verifyTrue(testCase, all([report.tests(temp_tests).ok]));
    verifyFalse(testCase, any([report.tests(~temp_tests).ok]));
    verifyEqual(testCase, fileread(blocked), 'keep');
    verifyError(testCase, @() ensure_output_directory(blocked), ...
        'MAGMA:Output:CreateDirectoryFailed');
end

function testSaveFigureAndOriginalException(testCase)
    config = struct('sub_results_path', fullfile(testCase.TestData.root, 'saved figures'), ...
        'subject', 42, 'measure', 1, 'make_figs_visible', 'off', 'plot_dpi', 80);
    fig = figure('Visible', 'off'); plot(1:5);
    cleanup = onCleanup(@() close_if_open(fig));
    save_figure(config, 'shallow_breathing');
    filename = fullfile(config.sub_results_path, 'Sub42_M1_shallow_breathing.png');
    info = imfinfo(filename);
    verifyEqual(testCase, info.Format, 'png');
    verifyFalse(testCase, isgraphics(fig));

    destination = fullfile(config.sub_results_path, 'blocked.png');
    mkdir(destination);
    fig = figure('Visible', 'off'); plot(1:5);
    cleanup_failure = onCleanup(@() close_if_open(fig));
    try
        save_figure(config, 'shallow_breathing', false, destination);
        verifyFail(testCase, 'Expected export failure.');
    catch ex
        verifyEqual(testCase, ex.identifier, 'MAGMA:Plot:ExportFailed');
        verifyTrue(testCase, contains(ex.message, destination));
        verifyNotEmpty(testCase, ex.cause);
        verifyNotEmpty(testCase, ex.cause{1}.stack);
        verifyTrue(testCase, isgraphics(fig));
    end
end

function close_if_open(fig)
    if isgraphics(fig), close(fig); end
end
