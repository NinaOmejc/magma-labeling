
% MAIN_GROUP Run cohort analysis using saved *_results.mat files only.
% Edit the group defaults below, or supply config before running this script.
src_root = fileparts(mfilename('fullpath'));
if ~isempty(src_root)
    addpath(genpath(src_root));
end

% Group settings: explicitly supplied config.group fields take precedence.
group_defaults = struct( ...
    'subjects', [], ...                     % empty discovers all saved subject IDs
    'measurements', [1 2], ...              % measurements to include
    'control_subjects', [], ...             % optional explicit group membership
    'patient_subjects', [], ...
    'paired_measurements', [1 2], ...       % before/after measurement pair
    'plot_layer', 'automatic', ...          % 'automatic' or 'reviewed'
    'plot_label_histograms', true, ...
    'plot_stratified_histograms', true);

if ~exist('config', 'var') || ~isstruct(config)
    config = get_config_defaults();
end
if ~isfield(config, 'group')
    config.group = struct();
end
for group_field = fieldnames(group_defaults)'
    if ~isfield(config.group, group_field{1})
        config.group.(group_field{1}) = group_defaults.(group_field{1});
    end
end

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
