
% MAIN_GROUP Run cohort analysis using saved *_results.mat files only.
% Set config before run('src/main_group.m') to override the defaults.
src_root = fileparts(mfilename('fullpath'));
if ~isempty(src_root)
    addpath(genpath(src_root));
end

if ~exist('config', 'var') || ~isstruct(config)
    config = get_config_defaults();
end
if ~isfield(config, 'group')
    config.group = struct();
end
if ~isfield(config.group, 'subjects'), config.group.subjects = []; end
if ~isfield(config.group, 'measurements'), config.group.measurements = [1 2]; end
if ~isfield(config.group, 'control_subjects'), config.group.control_subjects = []; end
if ~isfield(config.group, 'patient_subjects'), config.group.patient_subjects = []; end
if ~isfield(config.group, 'paired_measurements'), config.group.paired_measurements = [1 2]; end
if ~isfield(config.group, 'plot_layer'), config.group.plot_layer = 'automatic'; end
if ~isfield(config.group, 'plot_label_histograms'), config.group.plot_label_histograms = true; end
if ~isfield(config.group, 'plot_stratified_histograms'), config.group.plot_stratified_histograms = true; end

config = resolve_group_metadata(config);
[group_table, cohort] = build_group_label_table(config, false);
descriptive = build_group_descriptive_tables(config, group_table, cohort.phenotypes);
if strcmp(descriptive.layer, 'automatic') && config.group.plot_label_histograms
    descriptive.label_histograms = plot_group_label_histograms(config, descriptive);
end
if strcmp(descriptive.layer, 'automatic') && config.group.plot_stratified_histograms
    descriptive.group_histograms = plot_group_stratified_histograms(config, descriptive);
end
descriptive.manifest = build_group_descriptive_manifest(config, descriptive);
descriptive.files = write_group_workbooks(config.path_results_out, group_table, cohort, descriptive);
save(fullfile(config.path_results_out, 'group_analysis', '_cache', ...
    'group_analysis_data.mat'), 'group_table', 'cohort', 'descriptive');
log_message(config, 1, 'Saved group summaries: %s', descriptive.files{1});
