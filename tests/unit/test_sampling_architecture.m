function tests = test_sampling_architecture
% Tests A-E and H for the native/master sampling architecture.
    tests = functiontests(localfunctions);
end

function testPreprocessingPreservesDimensions(testCase)
    config = make_test_config();
    config.detrend.method = 'none';
    data_raw = make_synthetic_master_data(2001, config.fs);

    [data, config_out] = preprocess_data(data_raw, config);

    verifySize(testCase, data, size(data_raw));
    verifyEqual(testCase, config_out.fs, 200);
end

function testMasterSamplingRateAndTimes(testCase)
    config = make_test_config();
    config.detrend.method = 'none';
    data_raw = make_synthetic_master_data(1234, config.fs);

    [~, config_out] = preprocess_data(data_raw, config);
    expected_t = (0:size(data_raw,1)-1)' / 200;

    verifyEqual(testCase, config_out.fs, 200);
    removed_rate_field = ['new_' 'fs'];
    verifyFalse(testCase, isfield(config_out, removed_rate_field));
    verifyEqual(testCase, config_out.times, expected_t, 'AbsTol', 10*eps(expected_t(end)));
end

function testNonRespiratoryChannelsRemainExactlyAligned(testCase)
    config = make_test_config();
    config.detrend.method = 'hpfilter';
    config.detrend.do_plot = false;
    data_raw = make_synthetic_master_data(8001, config.fs);

    data = preprocess_data(data_raw, config);

    verifyEqual(testCase, data(:, [1 2 3 5]), data_raw(:, [1 2 3 5]));
    verifySize(testCase, data, size(data_raw));
end

function testOnlyConfiguredRespiratoryChannelIsDetrended(testCase)
    config = make_test_config();
    config.detrend.method = 'hpfilter';
    config.detrend.signals = {'Resp-Lungs'};
    config.detrend.do_plot = false;
    data_raw = make_synthetic_master_data(8001, config.fs);

    data = preprocess_data(data_raw, config);

    verifyGreaterThan(testCase, norm(data(:,4) - data_raw(:,4)), 1e-6);
    verifyEqual(testCase, data(:,6), data_raw(:,6));
    verifyEqual(testCase, data(:, [1 2 3 5]), data_raw(:, [1 2 3 5]));
    verifySize(testCase, data, size(data_raw));
end

function testSampleIndexToTimeConventionAndManualRecompute(testCase)
    config = make_test_config();
    config.resp.trough_method = 'min';
    x = sin(2*pi*0.5*(0:999)'/config.fs);

    initial_idx = [1; 201; 401; 601; 801];
    b = recompute_respiration_breath_fields(struct(), x, initial_idx, config);
    verifyEqual(testCase, b.peak_t, (initial_idx - 1) / config.fs, 'AbsTol', eps);
    verifyEqual(testCase, b.trough_t, (b.trough_idx - 1) / config.fs, 'AbsTol', eps);

    edited_idx = [1; 251; 501; 751; 951];
    b = recompute_respiration_breath_fields(b, x, edited_idx, config);
    verifyEqual(testCase, b.peak_t, (edited_idx - 1) / config.fs, 'AbsTol', eps);
    verifyEqual(testCase, b.ibi, diff(edited_idx) / config.fs, 'AbsTol', eps);

    config.resp.smooth_sec = 0;
    config.resp.min_peak_dist_sec = 1;
    config.resp.min_peak_prom = 0.1;
    config.resp.min_peak_height = -1;
    extracted = extract_respiration_feature(x, config, 'test');
    verifyEqual(testCase, extracted.peak_t, ...
        (extracted.peak_idx - 1) / config.fs, 'AbsTol', eps);
end

function testBrokenLungBeltPreservesMasterIndexing(testCase)
    config = make_test_config();
    config.subject = 1;
    config.problems.missing_lung_belt = [1 1];
    config.detrend.method = 'none';
    data_raw = make_synthetic_master_data(10001, config.fs);
    data_raw(:, config.channels.lungs_idx) = 0;

    data = preprocess_data(data_raw, config);
    resp_feat = extract_respiration_features(data, config);
    session_reference = get_session_reference_interval(size(data,1), config);
    rea = compute_respiratory_asynchrony_metrics( ...
        data, resp_feat, session_reference, config);

    verifySize(testCase, data, size(data_raw));
    verifyFalse(testCase, resp_feat.lungs.ok);
    verifyTrue(testCase, resp_feat.diaph.ok);
    verifyFalse(testCase, rea.valid_analysis);
    verifyEqual(testCase, rea.skip_code, 2);
    verifyEqual(testCase, rea.master_n_samples, size(data,1));
    verifyLessThanOrEqual(testCase, rea.time_sec(end), (size(data,1)-1)/config.fs);
end
