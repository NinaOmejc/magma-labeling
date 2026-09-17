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
    default_config = get_config();

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
