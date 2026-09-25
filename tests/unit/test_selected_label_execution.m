function tests = test_selected_label_execution
% Unit tests for selected-label normalization and execution decisions.
    tests = functiontests(localfunctions);
end

function testEmptySelectionsMeanNormalBehavior(testCase)
    config = struct('execution', struct('selected_labels', {{}}));
    verifyEmpty(testCase, resolve_selected_labels(config));
    config.execution.selected_labels = [];
    verifyEmpty(testCase, resolve_selected_labels(config));
    verifyEmpty(testCase, resolve_selected_labels(struct()));
end

function testTextInputsNormalizeToCanonicalCellstr(testCase)
    verifyEqual(testCase, selected('irregular'), {'irregular'});
    verifyEqual(testCase, selected("irregular"), {'irregular'});
    verifyEqual(testCase, selected(["irregular" "slow"]), ...
        {'irregular', 'slow'});
    verifyEqual(testCase, selected({'irregular', 'slow'}), ...
        {'irregular', 'slow'});
end

function testDuplicatesAreRemovedInCallerOrder(testCase)
    verifyEqual(testCase, selected( ...
        {'slow', 'irregular', 'slow', 'rapid'}), ...
        {'slow', 'irregular', 'rapid'});
end

function testUnknownLabelHasClearError(testCase)
    verifyError(testCase, @() selected({'irregular', 'unknown'}), ...
        'MAGMA:Execution:UnknownSelectedLabel');
end

function testExecutionDecisionMatrix(testCase)
    verifyTrue(testCase, should_analyze_recording( ...
        false, false, 'analyze', {}));
    verifyTrue(testCase, should_analyze_recording( ...
        false, false, 'analyze', {'irregular'}));
    verifyFalse(testCase, should_analyze_recording( ...
        true, false, 'analyze', {}));
    verifyTrue(testCase, should_analyze_recording( ...
        true, true, 'analyze', {}));
    verifyTrue(testCase, should_analyze_recording( ...
        true, false, 'analyze', {'irregular'}));
end

function testShouldRunLabelUsesFullOrSubsetMode(testCase)
    verifyTrue(testCase, should_run_label('deep', {}));
    verifyTrue(testCase, should_run_label( ...
        'irregular', {'irregular', 'slow'}));
    verifyFalse(testCase, should_run_label( ...
        'rapid', {'irregular', 'slow'}));
end

function labels = selected(value)
    config = struct('execution', struct('selected_labels', {value}));
    labels = resolve_selected_labels(config);
end
