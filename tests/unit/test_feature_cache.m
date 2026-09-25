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
    verifyEqual(testCase, saved.feature_cache_meta.cache_version, 9);
    verifyEqual(testCase, saved.feature_cache_meta.fs, 200);
    verifyEqual(testCase, saved.feature_cache_meta.measurement, config.measure);
    verifyEqual(testCase, saved.feature_cache_meta.n_samples, size(data,1));
    verifyEqual(testCase, saved.feature_cache_meta.amp_method, ...
        resolve_respiration_amplitude_method(config));
    verifyTrue(testCase, isfield(saved.feature_cache_meta, ...
        'belt_polarity_checked'));
    verifyTrue(testCase, isfield(saved.feature_cache_meta, ...
        'diaphragm_polarity_flipped'));
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

function testAmplitudeMethodChangeReselectsWithoutLosingReviewedBreaths(testCase)
    output_dir = tempname;
    mkdir(output_dir);
    cleanup_dir = onCleanup(@() rmdir(output_dir, 's'));
    n_samples = 40;
    data = zeros(n_samples, 2);
    config = struct( ...
        'subject', 999, ...
        'measure', 1, ...
        'fs', 10, ...
        'data_columns', {{'Resp-Lungs', 'Resp-Diaphragm'}}, ...
        'sub_results_path', output_dir, ...
        'sub_features_filename', 'test_features.mat', ...
        'path_results_out', output_dir, ...
        'overwrite_features', false, ...
        'resp', struct('amp_method', 'expiratory'));
    reviewed_belt = reviewed_cache_belt(n_samples);
    reviewed_belt.trough_overrides = [5 15 10];
    resp_cycles = struct( ...
        'lungs', reviewed_belt, ...
        'diaph', reviewed_belt, ...
        'provenance', struct( ...
            'review_status', 'manual_reviewed_edited', ...
            'manual_review_performed', true, ...
            'manual_edits_made', true, ...
            'loaded_from_cache', false));
    feature_cache_meta = struct( ...
        'cache_version', 9, ...
        'subject', config.subject, ...
        'measurement', config.measure, ...
        'fs', config.fs, ...
        'n_samples', n_samples, ...
        'data_columns', {config.data_columns}, ...
        'amp_method', 'expiratory', ...
        'belt_polarity_checked', false, ...
        'diaphragm_polarity_flipped', false);
    reviewed = resp_cycles;
    cache_file = fullfile(output_dir, config.sub_features_filename);
    save(cache_file, 'resp_cycles', 'feature_cache_meta');

    config.resp.amp_method = 'inspiratory';
    inspiratory = load_or_extract_respiratory_cycles(data, config);
    saved = load(cache_file, 'feature_cache_meta');

    verifyTrue(testCase, inspiratory.provenance.loaded_from_cache);
    verifyEqual(testCase, inspiratory.provenance.review_status, ...
        'manual_reviewed_edited');
    verifyTrue(testCase, inspiratory.provenance.manual_review_performed);
    verifyTrue(testCase, inspiratory.provenance.manual_edits_made);
    verifyEqual(testCase, inspiratory.lungs.peak_idx, reviewed.lungs.peak_idx);
    verifyEqual(testCase, inspiratory.lungs.trough_idx, reviewed.lungs.trough_idx);
    verifyEqual(testCase, inspiratory.lungs.trough_overrides, ...
        reviewed.lungs.trough_overrides);
    verifyEqual(testCase, inspiratory.lungs.amp, inspiratory.lungs.amp_insp);
    verifyEqual(testCase, inspiratory.lungs.amp_exp, reviewed.lungs.amp_exp);
    verifyEqual(testCase, inspiratory.lungs.amp_sym, reviewed.lungs.amp_sym);
    verifyEqual(testCase, saved.feature_cache_meta.amp_method, 'inspiratory');
    verifyTrue(testCase, isfield(saved.feature_cache_meta, ...
        'amplitude_reselected_on'));
end

function testLegacyCacheWithoutTroughOverridesRetainsReviewedPeaks(testCase)
    output_dir = tempname;
    mkdir(output_dir);
    cleanup_dir = onCleanup(@() rmdir(output_dir, 's'));
    n_samples = 40;
    data = zeros(n_samples, 2);
    config = struct( ...
        'subject', 999, ...
        'measure', 1, ...
        'fs', 10, ...
        'data_columns', {{'Resp-Lungs', 'Resp-Diaphragm'}}, ...
        'sub_results_path', output_dir, ...
        'sub_features_filename', 'legacy_features.mat', ...
        'path_results_out', output_dir, ...
        'overwrite_features', false, ...
        'resp', struct('amp_method', 'expiratory'));
    legacy_belt = rmfield(reviewed_cache_belt(n_samples), 'trough_overrides');
    resp_cycles = struct( ...
        'lungs', legacy_belt, ...
        'diaph', legacy_belt, ...
        'provenance', struct( ...
            'review_status', 'manual_reviewed_edited', ...
            'manual_review_performed', true, ...
            'manual_edits_made', true, ...
            'loaded_from_cache', false));
    feature_cache_meta = struct( ...
        'cache_version', 9, ...
        'subject', config.subject, ...
        'measurement', config.measure, ...
        'fs', config.fs, ...
        'n_samples', n_samples, ...
        'data_columns', {config.data_columns}, ...
        'amp_method', 'expiratory', ...
        'belt_polarity_checked', false, ...
        'diaphragm_polarity_flipped', false);
    cache_file = fullfile(output_dir, config.sub_features_filename);
    save(cache_file, 'resp_cycles', 'feature_cache_meta');

    loaded = load_or_extract_respiratory_cycles(data, config);

    verifyTrue(testCase, loaded.provenance.loaded_from_cache);
    verifyEqual(testCase, loaded.lungs.peak_idx, legacy_belt.peak_idx);
    verifyEqual(testCase, loaded.lungs.trough_idx, legacy_belt.trough_idx);
    verifyFalse(testCase, isfield(loaded.lungs, 'trough_overrides'));
end

function testVersionEightPrePolarityCacheIsRejected(testCase)
    output_dir = tempname;
    mkdir(output_dir);
    cleanup_dir = onCleanup(@() rmdir(output_dir, 's'));
    config = make_test_config(output_dir);
    data = make_synthetic_master_data(10001, config.fs);

    resp_cycles = load_or_extract_respiratory_cycles(data, config);
    cache_file = fullfile(output_dir, config.sub_features_filename);
    cached = load(cache_file);
    feature_cache_meta = cached.feature_cache_meta;
    feature_cache_meta.cache_version = 8;
    feature_cache_meta = rmfield(feature_cache_meta, ...
        {'belt_polarity_checked', 'diaphragm_polarity_flipped'});
    save(cache_file, 'resp_cycles', 'feature_cache_meta');

    recomputed = load_or_extract_respiratory_cycles(data, config);
    saved = load(cache_file, 'feature_cache_meta');

    verifyFalse(testCase, recomputed.provenance.loaded_from_cache);
    verifyEqual(testCase, saved.feature_cache_meta.cache_version, 9);
    verifyFalse(testCase, saved.feature_cache_meta.belt_polarity_checked);
    verifyFalse(testCase, saved.feature_cache_meta.diaphragm_polarity_flipped);
end

function testPolarityConventionMismatchInvalidatesCache(testCase)
    output_dir = tempname;
    mkdir(output_dir);
    cleanup_dir = onCleanup(@() rmdir(output_dir, 's'));
    config = make_test_config(output_dir);
    config.preprocessing.belt_polarity_qc = struct( ...
        'checked', true, 'flipped', false);
    data = make_synthetic_master_data(10001, config.fs);
    load_or_extract_respiratory_cycles(data, config);

    config.preprocessing.belt_polarity_qc.flipped = true;
    recomputed = load_or_extract_respiratory_cycles(data, config);
    cache_file = fullfile(output_dir, config.sub_features_filename);
    saved = load(cache_file, 'feature_cache_meta');

    verifyFalse(testCase, recomputed.provenance.loaded_from_cache);
    verifyTrue(testCase, saved.feature_cache_meta.belt_polarity_checked);
    verifyTrue(testCase, saved.feature_cache_meta.diaphragm_polarity_flipped);
end

function b = reviewed_cache_belt(n_samples)
    b = empty_respiration_feature('reviewed');
    b.x0 = zeros(n_samples, 1);
    b.peak_idx = [5; 15; 25; 35];
    b.peak_t = (b.peak_idx - 1) / 10;
    b.peak_val = [2; 3; 4; 5];
    b.trough_idx = [10; 20; 30];
    b.trough_t = (b.trough_idx - 1) / 10;
    b.trough_val = [0.5; 1; 1.5];
    b.amp_exp = [1.5; 2; 2.5; NaN];
    b.amp_insp = [NaN; 2.5; 3; 3.5];
    b.amp_sym = [NaN; 2.25; 2.75; NaN];
    b.amp = b.amp_exp;
    b.ibi = diff(b.peak_idx) / 10;
    b.rr_bpm = 60 ./ b.ibi;
    b.ok = true;
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
    b.amp_exp = [1; 1; NaN];
    b.amp_insp = [NaN; 1; 1];
    b.amp_sym = [NaN; 1; NaN];
    b.ibi = [0.05; 0.05];
    b.rr_bpm = [1200; 1200];
    resp_feat = struct('lungs', b, 'diaph', b);
end
