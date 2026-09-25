% DEMO Run the bundled MAGMA example from any MATLAB working directory.
example_root = fileparts(mfilename('fullpath'));
repo_root = fileparts(example_root);
addpath(genpath(fullfile(repo_root, 'src')));

config = get_config_defaults();
config.path_data_in = fullfile(example_root, 'data');
config.path_results_out = fullfile(example_root, 'output');
config.subjects = 42;
config.measurements = 1; % Use [1 2] to process both bundled recordings.

config.execution.mode = 'analyze';

config.overwrite_results = true;
config.overwrite_features = true;
config.make_figs_visible = 'off';

fprintf('Running MAGMA demo: Subject 42, Measurement 1\n');
fprintf('Input: %s\n', config.path_data_in);
fprintf('Output: %s\n\n', config.path_results_out);

run_magma(config);

fprintf('\nMAGMA demo finished.\n');
fprintf('Results saved to: %s\n', config.path_results_out);
