function tests = test_rea_local_resampling
% Test G for anti-aliased, ReA-local respiratory downsampling.
    tests = functiontests(localfunctions);
end

function testAntiAliasedLocalResamplingPreservesMasterInput(testCase)
    master_fs = 200;
    analysis_fs = 20;
    t = (0:10*master_fs-1)' / master_fs;
    lungs_master = sin(2*pi*0.25*t) + sin(2*pi*27*t);
    diaph_master = 0.8*sin(2*pi*0.25*t + 0.2) + sin(2*pi*27*t);
    lungs_before = lungs_master;
    diaph_before = diaph_master;

    [lungs_analysis, diaph_analysis, actual_fs] = ...
        resample_respiration_for_analysis(lungs_master, diaph_master, master_fs, analysis_fs);
    [aliased_probe, ~] = resample_respiration_for_analysis( ...
        sin(2*pi*27*t), zeros(size(t)), master_fs, analysis_fs);

    verifyEqual(testCase, lungs_master, lungs_before);
    verifyEqual(testCase, diaph_master, diaph_before);
    verifyEqual(testCase, actual_fs, analysis_fs, 'AbsTol', eps);
    verifyEqual(testCase, numel(lungs_analysis), numel(diaph_analysis));
    verifyLessThanOrEqual(testCase, ...
        abs((numel(lungs_analysis)-1)/actual_fs - (numel(lungs_master)-1)/master_fs), ...
        1/actual_fs);

    interior = aliased_probe(21:end-20);
    verifyLessThan(testCase, sqrt(mean(interior.^2)), 0.05);
end

function testReAMetricsMapBackToMasterDuration(testCase)
    config = make_test_config();
    config.baseline_sec = 10;
    config.baseline_location = 'first';
    n_samples = 12001;
    data = make_synthetic_master_data(n_samples, config.fs);
    data_before = data;

    rea = compute_respiratory_asynchrony_metrics(data, [], config);
    expected_grid = (0:config.grid_step_sec:(n_samples-1)/config.fs)';

    verifyEqual(testCase, data, data_before);
    verifyTrue(testCase, rea.valid_analysis, rea.error_message);
    verifyEqual(testCase, rea.master_fs, 200);
    verifyEqual(testCase, rea.master_n_samples, n_samples);
    verifyEqual(testCase, rea.analysis_fs, 20, 'AbsTol', eps);
    verifyEqual(testCase, rea.time_sec, expected_grid, 'AbsTol', eps);
    verifyEqual(testCase, size(rea.low_coherence_mask), size(expected_grid));
    verifyLessThanOrEqual(testCase, ...
        abs(rea.analysis_duration_sec - (n_samples-1)/config.fs), ...
        1/rea.analysis_fs);
end

function testMismatchedMasterLengthsAreRejected(testCase)
    verifyError(testCase, @() resample_respiration_for_analysis( ...
        zeros(100,1), zeros(99,1), 200, 20), ...
        'MAGMA:RespiratoryAsynchrony:LengthMismatch');
end
