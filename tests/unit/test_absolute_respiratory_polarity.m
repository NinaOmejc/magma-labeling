function tests = test_absolute_respiratory_polarity
% Synthetic tests for the common physiological orientation of both belts.
    tests = functiontests(localfunctions);
end

function testFastRiseSlowDecayIsKept(testCase)
    [data, config] = polarity_fixture(0.25, 1, 50);
    [actual, result] = preprocess_data(data, config);
    qc = result.preprocessing.absolute_polarity_qc;

    verifyEqual(testCase, actual, data);
    verifyEqual(testCase, qc.absolute_polarity_decision, 'kept');
    verifyFalse(testCase, qc.absolute_polarity_flipped);
    verifyLessThan(testCase, qc.ie_ratio_combined, 0.90);
    verifyGreaterThanOrEqual(testCase, qc.n_valid_breaths_lungs, 10);
    verifyGreaterThanOrEqual(testCase, qc.n_valid_breaths_diaphragm, 10);
    verifyEqual(testCase, numel(qc.channels_used), 2);
end

function testUpsideDownBeltsFlipAndFinalLandmarksAreRedetected(testCase)
    [data, config] = polarity_fixture(0.25, 1, 50);
    data(:, [1 2]) = -data(:, [1 2]);

    [actual, result] = preprocess_data(data, config);
    qc = result.preprocessing.absolute_polarity_qc;
    final_cycles = extract_respiration_features(actual, result);

    verifyEqual(testCase, actual(:, 1:2), -data(:, 1:2));
    verifyEqual(testCase, qc.absolute_polarity_decision, 'flipped');
    verifyTrue(testCase, qc.absolute_polarity_flipped);
    verifyGreaterThan(testCase, qc.ie_ratio_combined, 1.10);
    verifyTrue(testCase, all(final_cycles.lungs.peak_val(2:end-1) > ...
        final_cycles.lungs.trough_val(1:end-1)));
end

function testRelativeCorrectionThenAbsoluteFlip(testCase)
    [data, config] = polarity_fixture(0.25, 1, 50);
    data(:, 1) = -data(:, 1);
    [actual, result] = preprocess_data(data, config);

    verifyTrue(testCase, result.preprocessing.belt_polarity_qc.flipped);
    verifyTrue(testCase, ...
        result.preprocessing.absolute_polarity_qc.absolute_polarity_flipped);
    verifyEqual(testCase, actual(:, 1), -data(:, 1));
    verifyEqual(testCase, actual(:, 2), data(:, 2));
end

function testSymmetricWaveformIsAmbiguous(testCase)
    [data, config] = polarity_fixture(0.50, 1, 50);
    [actual, result] = preprocess_data(data, config);

    verifyEqual(testCase, actual, data);
    verifyEqual(testCase, ...
        result.preprocessing.absolute_polarity_qc.absolute_polarity_decision, ...
        'ambiguous');
    verifyGreaterThanOrEqual(testCase, ...
        result.preprocessing.absolute_polarity_qc.ie_ratio_combined, 0.90);
    verifyLessThanOrEqual(testCase, ...
        result.preprocessing.absolute_polarity_qc.ie_ratio_combined, 1.10);
end

function testInsufficientLandmarksLeaveSignalsUnchanged(testCase)
    [data, config] = polarity_fixture(0.25, 1, 4);
    [actual, result] = preprocess_data(data, config);

    verifyEqual(testCase, actual, data);
    verifyEqual(testCase, ...
        result.preprocessing.absolute_polarity_qc.absolute_polarity_decision, ...
        'insufficient_data');
    verifyFalse(testCase, ...
        result.preprocessing.absolute_polarity_qc.absolute_polarity_flipped);
end

function testOneUsableBeltDeterminesResult(testCase)
    [data, config] = polarity_fixture(0.25, 1, 50);
    data(:, 1) = NaN;
    data(:, 2) = -data(:, 2);
    [actual, result] = preprocess_data(data, config);
    qc = result.preprocessing.absolute_polarity_qc;

    verifyTrue(testCase, all(isnan(actual(:, 1))));
    verifyEqual(testCase, actual(:, 2), -data(:, 2));
    verifyEqual(testCase, qc.channels_used, {'diaph'});
    verifyTrue(testCase, qc.absolute_polarity_flipped);
    verifyEqual(testCase, qc.n_valid_breaths_lungs, 0);
end

function [data, config] = polarity_fixture(rise_fraction, relative_sign, n_cycles)
    config = make_test_config();
    config.fs = 20;
    config.verbosity = 0;
    config.data_columns = {'Resp-Lungs', 'Resp-Diaphragm', 'Auxiliary'};
    config = resolve_signal_channels(config);
    config.detrend.method = 'none';
    config.preprocessing.check_belt_polarity = true;
    config.preprocessing.absolute_polarity.enabled = true;
    config.resp.qc.enabled = false;

    period = 4;
    t = (0:1/config.fs:(n_cycles * period - 1/config.fs))';
    phase = mod(t, period) / period;
    y = nan(size(t));
    rising = phase < rise_fraction;
    y(rising) = -1 + 2 * phase(rising) / rise_fraction;
    y(~rising) = 1 - 2 * (phase(~rising) - rise_fraction) / ...
        (1 - rise_fraction);
    data = [y relative_sign * y 20 + zeros(size(y))];
end

