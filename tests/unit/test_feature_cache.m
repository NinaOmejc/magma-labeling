function tests = test_feature_cache
% Test F for respiratory-cycle cache invalidation and reuse.
    tests = functiontests(localfunctions);
end

function testOldTwentyHertzCacheIsRejected(testCase)
    output_dir = tempname;
    mkdir(output_dir);
    cleanup_dir = onCleanup(@() rmdir(output_dir, 's'));
    config = make_test_config(output_dir);
    data = make_synthetic_master_data(10001, config.fs);

    resp_feat = sentinel_resp_feat(size(data,1));
    feature_cache_meta = struct( ...
        'cache_version', 5, ...
        'subject', config.subject, ...
        'measure', config.measure, ...
        'fs', 20, ...
        'n_samples', size(data,1), ...
        'data_columns', {config.data_columns});
    cache_file = fullfile(output_dir, config.sub_features_filename);
    save(cache_file, 'resp_feat', 'feature_cache_meta');

    actual = load_or_extract_respiratory_cycles(data, config);
    saved = load(cache_file, 'feature_cache_meta');

    verifyNotEqual(testCase, actual.lungs.peak_idx, resp_feat.lungs.peak_idx);
    verifyEqual(testCase, saved.feature_cache_meta.cache_version, 7);
    verifyEqual(testCase, saved.feature_cache_meta.fs, 200);
    verifyEqual(testCase, saved.feature_cache_meta.measurement, config.measure);
    verifyEqual(testCase, saved.feature_cache_meta.n_samples, size(data,1));
end

function testCompatibleMasterRateCacheIsReused(testCase)
    output_dir = tempname;
    mkdir(output_dir);
    cleanup_dir = onCleanup(@() rmdir(output_dir, 's'));
    config = make_test_config(output_dir);
    data = make_synthetic_master_data(10001, config.fs);

    expected = load_or_extract_respiratory_cycles(data, config);
    incompatible_signal = zeros(size(data));
    actual = load_or_extract_respiratory_cycles(incompatible_signal, config);

    verifyEqual(testCase, actual.lungs, expected.lungs);
    verifyEqual(testCase, actual.diaph, expected.diaph);
    verifyEqual(testCase, actual.provenance.review_status, ...
        expected.provenance.review_status);
    verifyFalse(testCase, expected.provenance.loaded_from_cache);
    verifyTrue(testCase, actual.provenance.loaded_from_cache);
end

function resp_feat = sentinel_resp_feat(n_samples)
    b = empty_respiration_feature('sentinel');
    b.ok = true;
    b.x0 = zeros(n_samples, 1);
    b.peak_idx = [1; 2; 3];
    b.peak_t = [0; 0.05; 0.10];
    b.peak_val = ones(3, 1);
    b.trough_idx = [1; 2];
    b.trough_t = [0; 0.05];
    b.trough_val = zeros(2, 1);
    b.amp = [1; 1; NaN];
    b.ibi = [0.05; 0.05];
    b.rr_bpm = [1200; 1200];
    resp_feat = struct('lungs', b, 'diaph', b);
end
