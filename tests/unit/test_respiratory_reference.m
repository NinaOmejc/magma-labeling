function tests = test_respiratory_reference
% Phase 2A tests for diagnostic respiratory amplitude reference stability.
    tests = functiontests(localfunctions);
end

function testStationaryAmplitudesUseSingleReference(testCase)
    config = reference_test_config();
    [t, amp] = stationary_series(120, 1.0, 0.04);
    resp_ref = compute_respiratory_reference(make_resp_feat(t, amp, t, 0.8*amp), config);

    verifyFalse(testCase, resp_ref.lungs.change_detected);
    verifyEqual(testCase, resp_ref.lungs.mode, 'single');
    verifyEqual(testCase, resp_ref.lungs.quality, 'good');
    verifyEqual(testCase, resp_ref.lungs.n_valid_breaths, 120);
    verifyEqual(testCase, resp_ref.lungs.end_to_start_ratio, 1, 'AbsTol', 0.08);
    verifyEqual(testCase, resp_ref.change_pattern, 'none');
end

function testClearDownwardStepIsDetected(testCase)
    config = reference_test_config();
    [t, amp] = step_series(120, 60, 1.0, 0.55);
    resp_ref = compute_respiratory_reference(make_resp_feat(t, amp, [], []), config);
    belt = resp_ref.lungs;

    verifyTrue(testCase, belt.change_detected);
    verifyEqual(testCase, belt.mode, 'change_candidate');
    verifyLessThanOrEqual(testCase, abs(belt.change_breath_idx - 61), 1);
    verifyLessThanOrEqual(testCase, abs(belt.change_t - t(61)), 3);
    verifyEqual(testCase, belt.change_ratio, 0.55, 'AbsTol', 0.06);
    verifyGreaterThan(testCase, belt.cost_improvement, config.resp_ref.min_cost_improvement);
end

function testClearUpwardStepIsDetected(testCase)
    config = reference_test_config();
    [t, amp] = step_series(120, 60, 0.65, 1.25);
    resp_ref = compute_respiratory_reference(make_resp_feat(t, amp, [], []), config);
    belt = resp_ref.lungs;

    verifyTrue(testCase, belt.change_detected);
    verifyLessThanOrEqual(testCase, abs(belt.change_breath_idx - 61), 1);
    verifyEqual(testCase, belt.change_ratio, 1.25/0.65, 'AbsTol', 0.12);
    verifyGreaterThan(testCase, belt.step_sharpness, 0.8);
    verifyTrue(testCase, belt.persistence_ok);
end

function testNoisyStationaryAmplitudesDoNotFalseTrigger(testCase)
    config = reference_test_config();
    t = (0:119)' * 3;
    k = (1:120)';
    amp = 1 + 0.10*sin(0.73*k) + 0.05*cos(0.31*k);
    resp_ref = compute_respiratory_reference(make_resp_feat(t, amp, [], []), config);

    verifyFalse(testCase, resp_ref.lungs.change_detected);
    verifyLessThan(testCase, resp_ref.lungs.edge_change_frac, config.resp_ref.change_trigger_frac);
    verifyEqual(testCase, resp_ref.lungs.quality, 'good');
end

function testGradualDriftIsNotAcceptedAsSharpStep(testCase)
    config = reference_test_config();
    t = (0:139)' * 3;
    k = (1:140)';
    amp = linspace(1.0, 0.50, 140)' .* (1 + 0.01*sin(0.6*k));
    resp_ref = compute_respiratory_reference(make_resp_feat(t, amp, [], []), config);
    belt = resp_ref.lungs;

    verifyTrue(testCase, belt.edge_change_triggered);
    verifyFalse(testCase, belt.change_detected);
    verifyEqual(testCase, belt.mode, 'single');
    verifyEqual(testCase, belt.quality, 'gradual_or_complex');
    verifyLessThan(testCase, belt.step_sharpness, 0.60);
end

function testTooFewBreathsReturnsInsufficientData(testCase)
    config = reference_test_config();
    t = (0:14)' * 3;
    amp = ones(size(t));
    resp_ref = compute_respiratory_reference(make_resp_feat(t, amp, [], []), config);

    verifyTrue(testCase, resp_ref.lungs.available);
    verifyFalse(testCase, resp_ref.lungs.change_detected);
    verifyEqual(testCase, resp_ref.lungs.mode, 'insufficient_data');
    verifyEqual(testCase, resp_ref.lungs.quality, 'insufficient_data');
    verifyEqual(testCase, resp_ref.lungs.n_valid_breaths, 15);
end

function testBrokenLungBeltLeavesDiaphragmAnalyzable(testCase)
    config = reference_test_config();
    config.subject = 1;
    config.problems.subjects_with_broken_lung_belt = 1;
    [t, lungs_amp] = step_series(120, 60, 1.0, 0.5);
    [~, diaph_amp] = step_series(120, 60, 0.8, 1.2);
    resp_ref = compute_respiratory_reference( ...
        make_resp_feat(t, lungs_amp, t, diaph_amp), config);

    verifyFalse(testCase, resp_ref.lungs.available);
    verifyTrue(testCase, resp_ref.diaph.available);
    verifyTrue(testCase, resp_ref.diaph.change_detected);
    verifyEqual(testCase, resp_ref.change_pattern, 'insufficient_data');
end

function testMatchingBeltChangesAreSummarizedAsSimilar(testCase)
    config = reference_test_config();
    [t, lungs_amp] = step_series(140, 70, 1.0, 0.55);
    [~, diaph_amp] = step_series(140, 70, 0.8, 0.46);
    resp_ref = compute_respiratory_reference( ...
        make_resp_feat(t, lungs_amp, t, diaph_amp), config);

    verifyTrue(testCase, resp_ref.lungs.change_detected);
    verifyTrue(testCase, resp_ref.diaph.change_detected);
    verifyEqual(testCase, resp_ref.change_pattern, 'both_similar');
    verifyLessThanOrEqual(testCase, resp_ref.change_time_difference_sec, 3);
    verifyLessThan(testCase, resp_ref.change_ratio_log_difference, 0.08);
end

function testDifferentBeltChangeTimesAreSummarizedAsDifferent(testCase)
    config = reference_test_config();
    [t, lungs_amp] = step_series(180, 60, 1.0, 0.55);
    [~, diaph_amp] = step_series(180, 120, 0.8, 0.44);
    resp_ref = compute_respiratory_reference( ...
        make_resp_feat(t, lungs_amp, t, diaph_amp), config);

    verifyEqual(testCase, resp_ref.change_pattern, 'both_different');
    verifyGreaterThan(testCase, resp_ref.change_time_difference_sec, ...
        0.25 * config.resp_ref.edge_window_sec);
    verifyEqual(testCase, resp_ref.agreement_quality, 'belt_disagreement');
end

function testSuppliedBreathValuesAreUsedDirectly(testCase)
    config = reference_test_config();
    config = rmfield(config, 'resp');
    config.resp_ref.min_segment_breaths = 5;
    config.resp_ref.edge_window_sec = 45;
    t = (0:59)' * 7.3;
    amp = [2*ones(30,1); ones(30,1)];
    amp(5) = NaN;
    amp(10) = 0;
    resp_ref = compute_respiratory_reference(make_resp_feat(t, amp, [], []), config);

    verifyEqual(testCase, resp_ref.lungs.n_input_breaths, 60);
    verifyEqual(testCase, resp_ref.lungs.n_valid_breaths, 58);
    verifyEqual(testCase, resp_ref.lungs.n_invalid_breaths, 2);
    verifyTrue(testCase, resp_ref.lungs.change_detected);
    verifyEqual(testCase, resp_ref.lungs.ref_before, 2, 'AbsTol', eps);
    verifyEqual(testCase, resp_ref.lungs.ref_after, 1, 'AbsTol', eps);
    verifyTrue(testCase, ismember(resp_ref.lungs.change_t, t));
end

function testDiagnosticPlotUsesRepositorySaveConvention(testCase)
    output_dir = tempname;
    mkdir(output_dir);
    cleanup_dir = onCleanup(@() rmdir(output_dir, 's'));
    config = reference_test_config();
    config.sub_results_path = output_dir;
    config.resp_ref.do_plot = true;
    [t, amp] = step_series(120, 60, 1.0, 0.55);
    resp_feat = make_resp_feat(t, amp, t, 0.8*amp);
    resp_ref = compute_respiratory_reference(resp_feat, config);

    plot_respiratory_reference(resp_feat, resp_ref, config);

    expected_file = fullfile(output_dir, ...
        sprintf('Sub%d_M%d_respiratory_reference.png', config.subject, config.measure));
    verifyTrue(testCase, isfile(expected_file));
    verifyEmpty(testCase, findall(groot, 'Type', 'figure'));
end

function config = reference_test_config()
    config = make_test_config();
    config.resp_ref.edge_window_sec = 300;
    config.resp_ref.change_trigger_frac = 0.25;
    config.resp_ref.min_segment_breaths = 12;
    config.resp_ref.min_cost_improvement = 0.30;
    config.resp_ref.do_plot = false;
end

function [t, amp] = stationary_series(n, level, noise_scale)
    t = (0:n-1)' * 3;
    k = (1:n)';
    amp = level * (1 + noise_scale*sin(0.47*k) + 0.5*noise_scale*cos(0.19*k));
end

function [t, amp] = step_series(n, split_after, before_level, after_level)
    t = (0:n-1)' * 3;
    k = (1:n)';
    amp = [before_level*ones(split_after,1); after_level*ones(n-split_after,1)];
    amp = amp .* (1 + 0.02*sin(0.61*k) + 0.01*cos(0.17*k));
end

function resp_feat = make_resp_feat(t_lungs, amp_lungs, t_diaph, amp_diaph)
    resp_feat = struct();
    resp_feat.lungs = struct('peak_t', t_lungs(:), 'amp', amp_lungs(:));
    resp_feat.diaph = struct('peak_t', t_diaph(:), 'amp', amp_diaph(:));
end
