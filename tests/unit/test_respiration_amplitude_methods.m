function tests = test_respiration_amplitude_methods
% Deterministic tests for alternative breath-level amplitude definitions.
    tests = functiontests(localfunctions);
end

function testTroughIndexingAndNumericalValues(testCase)
    config = amplitude_test_config('expiratory');
    [x, peak_idx] = simple_waveform();

    b = recompute_respiration_breath_fields(struct(), x, peak_idx, config);

    verifyEqual(testCase, b.trough_idx, [2; 4; 6]);
    verifyEqual(testCase, b.trough_val, [1; 2; 0]);
    verifyEqual(testCase, b.amp_exp, [4; 6; 6; NaN]);
    verifyEqual(testCase, b.amp_insp, [NaN; 7; 4; 9]);
    verifyEqual(testCase, b.amp_sym, [NaN; 6.5; 5; NaN]);
    verifyEqual(testCase, b.amp_sym(2:3), ...
        (b.amp_insp(2:3) + b.amp_exp(2:3)) / 2);
    verifyEqual(testCase, b.trough_overrides, zeros(0, 3));
end

function testManualTroughMovementRecomputesOnlyAmplitudeFields(testCase)
    config = amplitude_test_config('expiratory');
    [x, peak_idx] = override_waveform();
    automatic = recompute_respiration_breath_fields(struct(), x, peak_idx, config);

    moved = set_respiration_trough_override(automatic, 1, 5, 3, config);

    verifyEqual(testCase, moved.trough_idx, [3; 7; 11]);
    verifyEqual(testCase, moved.trough_t, [2; 6; 10]);
    verifyEqual(testCase, moved.trough_val, [6; 1; 0]);
    verifyEqual(testCase, moved.trough_overrides, [1 5 3]);
    verifyEqual(testCase, moved.amp_exp, [4; 10; 12; NaN]);
    verifyEqual(testCase, moved.amp_insp, [NaN; 5; 11; 13]);
    verifyEqual(testCase, moved.amp_sym, [NaN; 7.5; 11.5; NaN]);
    verifyEqual(testCase, moved.amp, moved.amp_exp);
    verifyEqual(testCase, moved.peak_idx, automatic.peak_idx);
    verifyEqual(testCase, moved.peak_t, automatic.peak_t);
    verifyEqual(testCase, moved.peak_val, automatic.peak_val);
    verifyEqual(testCase, moved.ibi, automatic.ibi);
    verifyEqual(testCase, moved.rr_bpm, automatic.rr_bpm);
    verifyEqual(testCase, moved.rr_mean_bpm, automatic.rr_mean_bpm);
    verifyEqual(testCase, moved.rr_std_bpm, automatic.rr_std_bpm);
end

function testEqualHeightRelocationChangesTimingNotAmplitude(testCase)
    config = amplitude_test_config('symmetric');
    [x, peak_idx] = override_waveform();
    x(3) = x(2);
    automatic = recompute_respiration_breath_fields(struct(), x, peak_idx, config);

    moved = set_respiration_trough_override(automatic, 1, 5, 3, config);

    verifyEqual(testCase, moved.trough_idx, [3; 7; 11]);
    verifyEqual(testCase, moved.trough_t(1), 2);
    verifyEqual(testCase, moved.trough_val, automatic.trough_val);
    verifyEqual(testCase, moved.amp_exp, automatic.amp_exp);
    verifyEqual(testCase, moved.amp_insp, automatic.amp_insp);
    verifyEqual(testCase, moved.amp_sym, automatic.amp_sym);
    verifyEqual(testCase, moved.amp, automatic.amp);
    verifyTrue(testCase, ...
        respiration_breath_landmarks_changed(automatic, moved));
end

function testOverridesSurviveUnrelatedPeakAndAmplitudeMethodChanges(testCase)
    config = amplitude_test_config('expiratory');
    [x, peak_idx] = override_waveform();
    b = recompute_respiration_breath_fields(struct(), x, peak_idx, config);
    b = set_respiration_trough_override(b, 1, 5, 3, config);

    with_unrelated_peak = recompute_respiration_breath_fields( ...
        b, x, [peak_idx; 11], config);
    verifyEqual(testCase, with_unrelated_peak.trough_overrides, [1 5 3]);
    verifyEqual(testCase, with_unrelated_peak.trough_idx(1), 3);

    config.resp.amp_method = 'inspiratory';
    reselected = recompute_respiration_breath_fields( ...
        with_unrelated_peak, x, with_unrelated_peak.peak_idx, config);
    verifyEqual(testCase, reselected.trough_overrides, [1 5 3]);
    verifyEqual(testCase, reselected.trough_idx(1), 3);
    verifyEqual(testCase, reselected.amp, reselected.amp_insp);
end

function testConflictingPeakEditInvalidatesOnlyAffectedOverride(testCase)
    config = amplitude_test_config('expiratory');
    [x, peak_idx] = override_waveform();
    b = recompute_respiration_breath_fields(struct(), x, peak_idx, config);
    b = set_respiration_trough_override(b, 1, 5, 3, config);
    b = set_respiration_trough_override(b, 9, 13, 10, config);

    edited = recompute_respiration_breath_fields( ...
        b, x, [peak_idx; 11], config);

    verifyEqual(testCase, edited.trough_overrides, [1 5 3]);
    verifyEqual(testCase, edited.trough_idx(1), 3);
    verifyFalse(testCase, any(all(edited.trough_overrides(:, 1:2) == [9 13], 2)));
end

function testResetRestoresAutomaticTroughOnlyForSelectedPair(testCase)
    config = amplitude_test_config('expiratory');
    [x, peak_idx] = override_waveform();
    automatic = recompute_respiration_breath_fields(struct(), x, peak_idx, config);
    b = set_respiration_trough_override(automatic, 1, 5, 3, config);
    b = set_respiration_trough_override(b, 9, 13, 10, config);

    reset = reset_respiration_trough_override(b, 1, 5, config);

    verifyEqual(testCase, reset.trough_idx(1), automatic.trough_idx(1));
    verifyEqual(testCase, reset.trough_val(1), automatic.trough_val(1));
    verifyEqual(testCase, reset.trough_overrides, [9 13 10]);
    verifyEqual(testCase, reset.trough_idx(3), 10);
end

function testInvalidManualTroughPlacementsAreRejected(testCase)
    config = amplitude_test_config('expiratory');
    [x, peak_idx] = override_waveform();
    b = recompute_respiration_breath_fields(struct(), x, peak_idx, config);

    verifyError(testCase, ...
        @() set_respiration_trough_override(b, 1, 5, 1, config), ...
        'MAGMA:Respiration:TroughOutsidePeakPair');
    x(3) = NaN;
    b.x0 = x;
    verifyError(testCase, ...
        @() set_respiration_trough_override(b, 1, 5, 3, config), ...
        'MAGMA:Respiration:InvalidTroughSample');
    verifyError(testCase, ...
        @() set_respiration_trough_override(b, 1, 9, 3, config), ...
        'MAGMA:Respiration:TroughPeakPairChanged');
end

function testLegacyBeltWithoutOverridesRecomputesUnchanged(testCase)
    config = amplitude_test_config('expiratory');
    [x, peak_idx] = simple_waveform();
    legacy = struct('basename', 'legacy');

    actual = recompute_respiration_breath_fields(legacy, x, peak_idx, config);

    verifyEqual(testCase, actual.trough_idx, [2; 4; 6]);
    verifyEqual(testCase, actual.amp_exp, [4; 6; 6; NaN]);
    verifyEqual(testCase, actual.trough_overrides, zeros(0, 3));
    without_optional_field = rmfield(actual, 'trough_overrides');
    verifyFalse(testCase, respiration_breath_landmarks_changed( ...
        without_optional_field, actual));
end

function testBoundaryNaNsAreNotSubstituted(testCase)
    config = amplitude_test_config('expiratory');
    [x, peak_idx] = simple_waveform();

    b = recompute_respiration_breath_fields(struct(), x, peak_idx, config);

    verifyTrue(testCase, isnan(b.amp_exp(end)));
    verifyTrue(testCase, isnan(b.amp_insp(1)));
    verifyTrue(testCase, isnan(b.amp_sym(1)));
    verifyTrue(testCase, isnan(b.amp_sym(end)));
    verifyTrue(testCase, all(isfinite(b.amp_exp(1:end-1))));
    verifyTrue(testCase, all(isfinite(b.amp_insp(2:end))));
    verifyTrue(testCase, all(isfinite(b.amp_sym(2:end-1))));
end

function testSelectedAmplitudeMatchesConfiguredMethod(testCase)
    [x, peak_idx] = simple_waveform();
    methods = {'expiratory', 'inspiratory', 'symmetric'};
    fields = {'amp_exp', 'amp_insp', 'amp_sym'};

    for i = 1:numel(methods)
        config = amplitude_test_config(methods{i});
        b = recompute_respiration_breath_fields(struct(), x, peak_idx, config);
        verifyEqual(testCase, b.amp, b.(fields{i}));
    end
end

function testDefaultExpiratoryReproducesCurrentCalculation(testCase)
    config = amplitude_test_config('expiratory');
    config.resp = rmfield(config.resp, 'amp_method');
    [x, peak_idx] = simple_waveform();

    b = recompute_respiration_breath_fields(struct(), x, peak_idx, config);
    previous_result = [b.peak_val(1:end-1) - b.trough_val; NaN];
    default_config = get_config_defaults();

    verifyEqual(testCase, b.amp, previous_result);
    verifyEqual(testCase, b.amp, b.amp_exp);
    verifyEqual(testCase, default_config.resp.amp_method, 'expiratory');
end

function testInvalidMethodRaisesClearError(testCase)
    config = amplitude_test_config('not-a-method');
    [x, peak_idx] = simple_waveform();

    verifyError(testCase, ...
        @() recompute_respiration_breath_fields(struct(), x, peak_idx, config), ...
        'MAGMA:Respiration:InvalidAmplitudeMethod');
end

function testAmplitudeFieldsExistWhenExtractionFails(testCase)
    config = amplitude_test_config('symmetric');
    b = recompute_respiration_breath_fields(struct(), zeros(5, 1), 3, config);
    empty_b = empty_respiration_feature('lungs');

    verifyTrue(testCase, all(isfield(b, ...
        {'amp', 'amp_exp', 'amp_insp', 'amp_sym'})));
    verifyTrue(testCase, all(isfield(empty_b, ...
        {'amp', 'amp_exp', 'amp_insp', 'amp_sym'})));
    verifyTrue(testCase, all(isnan([b.amp; b.amp_exp; b.amp_insp; b.amp_sym])));
end

function config = amplitude_test_config(method)
    config = struct();
    config.fs = 1;
    config.resp = struct( ...
        'trough_method', 'min', ...
        'trough_prct', 5, ...
        'amp_method', method);
end

function [x, peak_idx] = simple_waveform()
    x = [5; 1; 8; 2; 6; 0; 9];
    peak_idx = [1; 3; 5; 7];
end

function [x, peak_idx] = override_waveform()
    x = [10; 2; 6; 7; 11; 4; 1; 4; 12; 5; 0; 5; 13];
    peak_idx = [1; 5; 9; 13];
end
