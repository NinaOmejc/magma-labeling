function tests = test_lung_belt_exclusions
% Recording-specific tests for known missing lung-belt exclusions.
    tests = functiontests(localfunctions);
end

function testAffectedSubjectAndMeasurementAreIgnored(testCase)
    config = exclusion_test_config(7, 1);

    verifyTrue(testCase, is_lung_belt_ignored(config));
end

function testSameSubjectUnaffectedMeasurementIsNotIgnored(testCase)
    config = exclusion_test_config(7, 3);

    verifyFalse(testCase, is_lung_belt_ignored(config));
end

function testUnaffectedSubjectIsNotIgnored(testCase)
    config = exclusion_test_config(42, 1);

    verifyFalse(testCase, is_lung_belt_ignored(config));
end

function testReASkipsOnlyAffectedRecording(testCase)
    config = exclusion_test_config(7, 1);
    data = make_synthetic_master_data(4001, config.fs);
    session_reference = get_session_reference_interval(size(data,1), config);

    affected = compute_respiratory_asynchrony_metrics( ...
        data, [], session_reference, config);
    verifyFalse(testCase, affected.valid_analysis);
    verifyEqual(testCase, affected.skip_code, 2);

    config.measure = 3;
    session_reference = get_session_reference_interval(size(data,1), config);
    unaffected = compute_respiratory_asynchrony_metrics( ...
        data, [], session_reference, config);
    verifyTrue(testCase, unaffected.valid_analysis, unaffected.error_message);
    verifyEqual(testCase, unaffected.skip_code, 0);
end

function testRespiratoryReferenceAnalyzesLungInUnaffectedRecording(testCase)
    config = exclusion_test_config(7, 3);
    config.reference.resp.min_segment_breaths = 12;
    config.reference.resp.edge_window_sec = 300;
    peak_t = (0:119)' * 3;
    amp = 1 + 0.03 * sin((1:120)' * 0.4);
    resp_feat = struct( ...
        'lungs', struct('peak_t', peak_t, 'amp', amp), ...
        'diaph', struct('peak_t', [], 'amp', []));

    session_reference = get_session_reference_interval(400*config.fs, config);
    resp_ref = compute_respiratory_reference( ...
        resp_feat, session_reference, config);

    verifyFalse(testCase, is_lung_belt_ignored(config));
    verifyTrue(testCase, resp_ref.lungs.available);
    verifyEqual(testCase, resp_ref.lungs.n_valid_breaths, numel(peak_t));
    verifyEqual(testCase, resp_ref.lungs.mode, 'single');
end

function config = exclusion_test_config(subject, measurement)
    config = make_test_config();
    config.fs = 10;
    config.ReA.analysis_fs = 10;
    config.subject = subject;
    config.measure = measurement;
    config.problems.missing_lung_belt = [7 1; 7 2];
end
