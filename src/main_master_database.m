% Rebuild the MAGMA master database from the current source workbooks.
% Update these paths for new versions; row counts and columns are discovered.
% Confirmed visit/status overrides in output_dir are reused on every rebuild.
script_dir = fileparts(mfilename('fullpath'));
addpath(genpath(script_dir));
project_dir = fileparts(fileparts(script_dir));
group_file = fullfile(project_dir, 'data_analysis', 'statistical_labeling', ...
    'group_analysis', 'group_summary.xlsx');
collaborator_file = fullfile(project_dir, 'ML_database_WORK_IN_PROGRESS_20Sep26_MG.xlsx');
stress_test_file = fullfile(project_dir, 'STRESS TEST _WORK IN PROGRESS_20Sep26.xlsx');
output_dir = fullfile(project_dir, 'data_analysis', 'statistical_labeling', 'master_database');
config = get_master_database_config(group_file, collaborator_file, output_dir, stress_test_file);
database = build_master_database(config);
