function tests = test_absolute_respiratory_polarity
% Synthetic tests for the common physiological orientation of both belts.
    tests = functiontests(localfunctions);
end

function testAbsoluteFlagCanBeDisabledIndependently(testCase)
    [data,config] = dwell_fixture(-1,50);
    config.preprocessing.check_absolute_belt_polarity = false;
    [actual,result] = preprocess_data(data,config);
    verifyEqual(testCase,actual,data);
    verifyTrue(testCase,result.preprocessing.belt_polarity_qc.checked);
    verifyFalse(testCase,result.preprocessing.absolute_polarity_qc.absolute_polarity_checked);
end

function testAbsoluteFlagCanBeEnabledWithoutRelativeCheck(testCase)
    [data,config] = dwell_fixture(-1,50);
    config.preprocessing.check_relative_belt_polarity = false;
    [actual,result] = preprocess_data(data,config);
    verifyEqual(testCase,actual(:,1:2),-data(:,1:2));
    verifyFalse(testCase,result.preprocessing.belt_polarity_qc.checked);
    verifyTrue(testCase,result.preprocessing.absolute_polarity_qc.absolute_polarity_checked);
    verifyTrue(testCase,result.preprocessing.absolute_polarity_qc.absolute_polarity_flipped);
end

function testNarrowHighPeaksAreKept(testCase)
    [data, config] = dwell_fixture(1, 50);
    [actual, result] = preprocess_data(data, config);
    qc = result.preprocessing.absolute_polarity_qc;

    verifyEqual(testCase, actual, data);
    verifyEqual(testCase, qc.absolute_polarity_decision, 'kept');
    verifyFalse(testCase, qc.absolute_polarity_flipped);
    verifyLessThan(testCase, qc.shared_high_dwell_fraction, ...
        result.preprocessing.absolute_polarity.high_dwell_lower);
    verifyGreaterThanOrEqual(testCase, qc.shared_fraction_narrow_high, ...
        result.preprocessing.absolute_polarity.majority_threshold);
    verifyEqual(testCase, numel(qc.channels_used), 2);
end

function testBroadHighPeaksFlipDespiteMisleadingIERatio(testCase)
    [data, config] = dwell_fixture(-1, 50);

    [actual, result] = preprocess_data(data, config);
    qc = result.preprocessing.absolute_polarity_qc;
    final_cycles = extract_respiration_features(actual, result);

    verifyEqual(testCase, actual(:, 1:2), -data(:, 1:2));
    verifyEqual(testCase, qc.absolute_polarity_decision, 'flipped');
    verifyTrue(testCase, qc.absolute_polarity_flipped);
    verifyGreaterThan(testCase, qc.shared_high_dwell_fraction, ...
        result.preprocessing.absolute_polarity.high_dwell_upper);
    verifyGreaterThanOrEqual(testCase, qc.shared_fraction_broad_high, ...
        result.preprocessing.absolute_polarity.majority_threshold);
    verifyLessThan(testCase, qc.shared_ie_ratio, ...
        result.preprocessing.absolute_polarity.ratio_lower);
    verifyTrue(testCase, all(final_cycles.lungs.peak_val(2:end-1) > ...
        final_cycles.lungs.trough_val(1:end-1)));
end

function testRelativeCorrectionThenAbsoluteFlip(testCase)
    [data, config] = dwell_fixture(1, 50);
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

function testBroadHighPeaksNeedBreathMajority(testCase)
    [data, config] = dwell_fixture(-1, 50);
    [narrow_high, ~] = dwell_fixture(1, 50);
    start_narrow = 30 * 4 * config.fs + 1;
    data(start_narrow:end, 1:2) = narrow_high(start_narrow:end, 1:2);

    [actual, result] = preprocess_data(data, config);
    qc = result.preprocessing.absolute_polarity_qc;

    verifyEqual(testCase, actual, data);
    verifyEqual(testCase, qc.absolute_polarity_decision, 'ambiguous');
    verifyGreaterThan(testCase, qc.shared_high_dwell_fraction, ...
        result.preprocessing.absolute_polarity.high_dwell_upper);
    verifyLessThan(testCase, qc.shared_fraction_broad_high, ...
        result.preprocessing.absolute_polarity.majority_threshold);

    config.preprocessing.absolute_polarity.majority_threshold = 0.55;
    [flipped, relaxed] = preprocess_data(data, config);
    verifyEqual(testCase, flipped(:, 1:2), -data(:, 1:2));
    verifyEqual(testCase, ...
        relaxed.preprocessing.absolute_polarity_qc.absolute_polarity_decision, ...
        'flipped');
end
function testLungsFallbackWhenDiaphragmHasNoBreaths(testCase)
    [data, config] = polarity_fixture(0.25, 1, 50);
    data(:, 1) = -data(:, 1);
    data(:, 2) = NaN;

    [actual, result] = preprocess_data(data, config);
    qc = result.preprocessing.absolute_polarity_qc;

    verifyEqual(testCase, actual(:, 1), -data(:, 1));
    verifyTrue(testCase, all(isnan(actual(:, 2))));
    verifyEqual(testCase, qc.absolute_polarity_decision, 'flipped');
    verifyFalse(testCase, qc.channels_discordant);
    verifyEqual(testCase, qc.channels_used, {'lungs'});
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

function [data, config] = dwell_fixture(orientation_sign, n_cycles)
    [data, config] = polarity_fixture(0.25, 1, n_cycles);
    period = 4;
    t = (0:1/config.fs:(n_cycles * period - 1/config.fs))';
    phase = mod(t, period) / period;
    broad_high = nan(size(phase));
    rise = phase < 0.15;
    plateau = phase >= 0.15 & phase < 0.90;
    drop = phase >= 0.90;
    broad_high(rise) = -1 + 2 * phase(rise) / 0.15;
    broad_high(plateau) = 1 - 0.2 * (phase(plateau) - 0.15) / 0.75;
    broad_high(drop) = 0.8 - 1.8 * (phase(drop) - 0.90) / 0.10;
    data(:, 1:2) = orientation_sign * [-broad_high -broad_high];
end
function [data, config] = polarity_fixture(rise_fraction, relative_sign, n_cycles)
    config = make_test_config();
    config.fs = 20;
    config.verbosity = 0;
    config.data_columns = {'Resp-Lungs', 'Resp-Diaphragm', 'Auxiliary'};
    config = resolve_signal_channels(config);
    config.detrend.method = 'none';
    config.preprocessing.check_relative_belt_polarity = true;
    config.preprocessing.relative_belt_polarity_mode = 'auto';
    config.preprocessing.check_absolute_belt_polarity = true;
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

