function tests = test_logging
% Lightweight tests for centralized verbosity gating.
    tests = functiontests(localfunctions);
end

function testDefaultVerbosityIsConcise(testCase)
    config = get_config_defaults();
    verifyEqual(testCase, config.verbosity, 1);
end

function testMessagesAreGatedByLevel(testCase)
    config = struct('verbosity', 1);
    concise_output = evalc("log_message(config, 1, 'Concise %d', 1);");
    detailed_output = evalc("log_message(config, 2, 'Detailed');");

    verifyEqual(testCase, strtrim(concise_output), 'Concise 1');
    verifyEmpty(testCase, detailed_output);

    config.verbosity = 2;
    detailed_output = evalc("log_message(config, 2, 'Detailed');");
    verifyEqual(testCase, strtrim(detailed_output), 'Detailed');
end

function testMissingVerbosityUsesConciseDefault(testCase)
    output = evalc("log_message(struct(), 1, 'Legacy config');");
    verifyEqual(testCase, strtrim(output), 'Legacy config');
end
