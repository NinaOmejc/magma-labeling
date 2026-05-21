% Generate artificial one-label datasets from one source file.

% Create Sub0/Pom1-9 artificial raw files from subject 7, measurement 1, cause its really nice control.
source_config = get_config();
test_data_dir = fullfile('D:\Projects\MAGMA', 'test_data'); % path where the test data will be saved
source_subject = 7; % take subject with id 7
source_measure = 1; 
test_subject = 0;   % rename the modified data to subject with id 0
trange_min = [8 10]; % make a change in this time frame
force_overwrite = true;

test_specs = create_artificial_test_data(source_config, test_data_dir, source_subject, source_measure, test_subject, trange_min, force_overwrite);

% Then, to analyze the test data, call main_single, where you should specify
% config.path_data_in = test_data_dir 
% config.subjects = [0]
% config.path_results_out = fullfile(test_data_dir, 'results')
% or sth similar