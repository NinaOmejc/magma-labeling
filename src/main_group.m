
%---- SETTINGS ----
subjects = [1 3 7 55 80 92];
remove_subjects = [3 30 91];
subjects(ismember(subjects, remove_subjects)) = [];

measurements = [1, 2]; % 1: pre-rehab-pre-stress, 2: pre-rehab-post-stress, 3:post-rehab-pre-stress, 4:post-rehab-post-stress

% add src to path
src_root = fileparts(mfilename('fullpath'));
if ~isempty(src_root)
    addpath(genpath(src_root));
end

% load config structure
config = get_config();
config.group.subjects = subjects;
config.group.measurements = measurements;
% Optional: fill these when subject metadata are available. If left empty,
% group plots still run, but traces/points are colored as unknown group.
% config.group.control_subjects = [];
% config.group.patient_subjects = [];

group_table = build_group_label_table(config);
group_overview = plot_group_diagnostic_overview(config, group_table);
