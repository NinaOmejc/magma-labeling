function tests = test_belt_polarity_preprocessing
% Deterministic tests for conservative recording-wide belt-polarity QC.
    tests = functiontests(localfunctions);
end

function testDisabledLeavesDataUnchanged(testCase)
    [data, config] = polarity_fixture(-1);
    config.preprocessing.check_belt_polarity = false;

    [actual, config_out] = preprocess_data(data, config);

    verifyEqual(testCase, actual, data);
    verifyFalse(testCase, config_out.preprocessing.belt_polarity_qc.checked);
    verifyEqual(testCase, ...
        config_out.preprocessing.belt_polarity_qc.reason, 'disabled');
end

function testAlignedBeltsAreNotFlipped(testCase)
    [data, config] = polarity_fixture(1);

    [actual, config_out] = preprocess_data(data, config);

    verifyEqual(testCase, actual, data);
    verifyTrue(testCase, config_out.preprocessing.belt_polarity_qc.checked);
    verifyFalse(testCase, config_out.preprocessing.belt_polarity_qc.flipped);
    verifyEqual(testCase, config_out.preprocessing.belt_polarity_qc.reason, ...
        'no_clear_global_polarity_inversion');
end

function testPersistentlyInvertedDiaphragmIsFlipped(testCase)
    [data, config] = polarity_fixture(-1);

    [actual, config_out] = preprocess_data(data, config);
    qc = config_out.preprocessing.belt_polarity_qc;

    verifyEqual(testCase, actual(:, config.channels.lungs_idx), ...
        data(:, config.channels.lungs_idx));
    verifyEqual(testCase, actual(:, config.channels.diaph_idx), ...
        -data(:, config.channels.diaph_idx));
    verifyGreaterThan(testCase, corrcoef_value( ...
        actual(:, config.channels.lungs_idx), ...
        actual(:, config.channels.diaph_idx)), 0.90);
    verifyTrue(testCase, qc.flipped);
    verifyEqual(testCase, qc.reason, ...
        'persistent_strong_inverse_belt_polarity');
end

function testShortTransientInversionDoesNotFlipRecording(testCase)
    [data, config, t] = polarity_fixture(1);
    transient = t >= 120 & t < 150;
    data(transient, config.channels.diaph_idx) = ...
        -data(transient, config.channels.diaph_idx);

    [actual, config_out] = preprocess_data(data, config);

    verifyEqual(testCase, actual, data);
    verifyFalse(testCase, config_out.preprocessing.belt_polarity_qc.flipped);
end

function testWeakUnrelatedBeltsAreNotFlipped(testCase)
    [data, config, t] = polarity_fixture(1);
    data(:, config.channels.diaph_idx) = ...
        sin(2 * pi * 0.37 * t + 0.4) + 0.03 * cos(2 * pi * 0.11 * t);

    [actual, config_out] = preprocess_data(data, config);

    verifyEqual(testCase, actual, data);
    verifyFalse(testCase, config_out.preprocessing.belt_polarity_qc.flipped);
    verifyEqual(testCase, config_out.preprocessing.belt_polarity_qc.reason, ...
        'too_few_informative_windows');
end

function testExcludedLungBeltSkipsCorrection(testCase)
    [data, config] = polarity_fixture(-1);
    config.problems.missing_lung_belt = [config.subject config.measure];

    [actual, config_out] = preprocess_data(data, config);

    verifyEqual(testCase, actual, data);
    verifyEqual(testCase, config_out.preprocessing.belt_polarity_qc.reason, ...
        'lung_belt_marked_missing');
end

function testNonRespiratoryColumnsDimensionsAndTimesArePreserved(testCase)
    [data, config] = polarity_fixture(-1);
    non_respiratory = [1 3];

    [actual, config_out] = preprocess_data(data, config);

    verifyEqual(testCase, actual(:, non_respiratory), ...
        data(:, non_respiratory));
    verifySize(testCase, actual, size(data));
    verifyEqual(testCase, config_out.times, ...
        (0:size(data, 1)-1)' / config.fs);
end

function testNaNsRemainMissingAfterTemporaryInterpolation(testCase)
    [data, config] = polarity_fixture(-1);
    lung_missing = 401:475;
    diaph_missing = 1201:1300;
    data(lung_missing, config.channels.lungs_idx) = NaN;
    data(diaph_missing, config.channels.diaph_idx) = NaN;

    [actual, config_out] = preprocess_data(data, config);

    verifyTrue(testCase, all(isnan( ...
        actual(lung_missing, config.channels.lungs_idx))));
    verifyTrue(testCase, all(isnan( ...
        actual(diaph_missing, config.channels.diaph_idx))));
    verifyTrue(testCase, config_out.preprocessing.belt_polarity_qc.flipped);
end

function testDiaphragmTrendUsesCorrectedPolarity(testCase)
    [data, config] = polarity_fixture(-1);
    config.detrend.method = 'hpfilter';
    disabled = config;
    disabled.preprocessing.check_belt_polarity = false;

    [uncorrected, ~, uncorrected_trend] = preprocess_data(data, disabled);
    [corrected, config_out, corrected_trend] = preprocess_data(data, config);
    idx = config.channels.diaph_idx;

    verifyTrue(testCase, config_out.preprocessing.belt_polarity_qc.flipped);
    verifyEqual(testCase, corrected(:, idx), -uncorrected(:, idx));
    verifyEqual(testCase, corrected_trend(:, idx), ...
        -uncorrected_trend(:, idx));
end

function testSingleVectorSkipsCleanly(testCase)
    [data, config] = polarity_fixture(1);
    vector = data(:, config.channels.lungs_idx);

    [actual, config_out] = preprocess_data(vector, config);

    verifyEqual(testCase, actual, vector);
    verifyEqual(testCase, config_out.preprocessing.belt_polarity_qc.reason, ...
        'single_signal_input');
end

function [data, config, t] = polarity_fixture(relative_sign)
    rng(41, 'twister');
    config = make_test_config();
    config.fs = 10;
    config.verbosity = 0;
    config.data_columns = ...
        {'Auxiliary', 'Resp-Lungs', 'SpO2', 'Resp-Diaphragm'};
    config.detrend.method = 'none';
    config.detrend.signals = {'Resp-Lungs', 'Resp-Diaphragm'};
    config.detrend.do_plot = false;
    config.preprocessing.check_belt_polarity = true;
    config.problems.missing_lung_belt = zeros(0, 2);
    config = resolve_signal_channels(config);

    duration_sec = 300;
    t = (0:1/config.fs:(duration_sec - 1/config.fs))';
    respiratory = sin(2 * pi * 0.23 * t) + ...
        0.18 * sin(2 * pi * 0.46 * t + 0.2);
    lungs = respiratory + 0.02 * randn(size(t));
    diaph = relative_sign * respiratory + 0.02 * randn(size(t));
    auxiliary = (1:numel(t))';
    spo2 = 96 + 0.1 * sin(2 * pi * 0.01 * t);
    data = [auxiliary lungs spo2 diaph];
end

function r = corrcoef_value(x, y)
    valid = isfinite(x) & isfinite(y);
    x = x(valid) - mean(x(valid));
    y = y(valid) - mean(y(valid));
    r = sum(x .* y) / sqrt(sum(x .^ 2) * sum(y .^ 2));
end
