function tests = test_example_pipeline_smoke
% Test I: non-interactive preprocessing and breath extraction smoke test.
    tests = functiontests(localfunctions);
end

function testExampleRecordingRunsAtMasterRate(testCase)
    this_file = mfilename('fullpath');
    repo_root = fileparts(fileparts(fileparts(this_file)));
    example_file = fullfile(repo_root, 'example_data', ...
        'ECG1_ECG2_SpO2_RespL_BP_RespD_fs200_Sub42_Pom1_DeTr_Norm.dat');
    assumeTrue(testCase, isfile(example_file), 'Example recording is not available.');

    output_dir = tempname;
    mkdir(output_dir);
    cleanup_dir = onCleanup(@() rmdir(output_dir, 's'));
    config = make_test_config(output_dir);
    config.subject = 42;
    config.measure = 1;
    config.overwrite_features = true;

    n_rows = 120 * config.fs;
    data_raw = read_first_rows(example_file, numel(config.data_columns), n_rows);
    verifyEqual(testCase, size(data_raw,2), numel(config.data_columns));

    [data, config] = preprocess_data(data_raw, config);
    resp_feat = load_or_extract_respiratory_features(data, config);

    verifySize(testCase, data, size(data_raw));
    verifyEqual(testCase, config.fs, 200);
    removed_rate_field = ['new_' 'fs'];
    verifyFalse(testCase, isfield(config, removed_rate_field));
    verifyEqual(testCase, numel(resp_feat.lungs.x0), size(data_raw,1));
    verifyEqual(testCase, numel(resp_feat.diaph.x0), size(data_raw,1));
end

function data = read_first_rows(filename, n_columns, n_rows)
    fid = fopen(filename, 'r');
    if fid < 0
        error('Could not open example recording: %s', filename);
    end
    cleanup_file = onCleanup(@() fclose(fid));
    format = repmat('%f', 1, n_columns);
    values = textscan(fid, format, n_rows, 'CollectOutput', true);
    data = values{1};
end
