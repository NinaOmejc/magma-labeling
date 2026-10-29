% Run MAGMA with the user-facing configuration.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% SETTINGS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Add MAGMA source folders to the MATLAB path
src_dir = fileparts(mfilename('fullpath'));
addpath(genpath(src_dir));

% Advanced scientific thresholds and processing defaults are defined in get_config_defaults.m.
config = get_config_defaults();

% Here below are the main arguments to be checked and modified:
% INPUT / OUTPUT
config.path_data_in = 'D:\Projects\MAGMA\raw_data';
config.path_results_out = 'D:\Projects\MAGMA\data_analysis\statistical_labeling';
config.subjects = [6:10];
config.measurements = [1 2];
config.exclude_recordings = [ ...                   % [subject, measurement];
      3 1;   3 2; ...
             5 2; ...
     30 1;  30 2; ...
     91 1;  91 2; ...
    135 1; 135 2; ...
    ];

% EXECUTION
config.overwrite_results = true;                    % If true, recompute even if "*_results.mat" output already exists.
config.overwrite_features = false;                  % If true, recompute respiratory features even if "*_features.mat" already exists.
config.resp.recheck_cached = false;                  % reopen saved landmarks/artifacts; Cancel skips this recording
config.execution.mode = 'analyze';       % 'analyze', 'analyze_and_review', or 'review'.

config.preprocessing.check_relative_belt_polarity = false;  % keep checking disabled; reuse compatible feature caches

% LABEL SELECTION
% Empty = normal behavior: new recordings analyze all labels; existing recordings obey config.overwrite_results.
% To calculate or rerun only selected labels, for example: config.execution.selected_labels = {'irregular', 'slow'};
config.execution.selected_labels = {};

% RESPIRATORY REPRESENTATION
config.resp.amp_method = 'symmetric';  % Selected breath amplitude: 'expiratory' (peak to following trough), 'inspiratory' (peak to preceding trough), or 'symmetric' (peak to the mean of both troughs)
config.resp.plot_amp_method_comparison = false; % save an optional comparison of all three breath-amplitude definitions

% PLOTTING
config.plot_raw_data = false;                               % save an overview plot of raw signals
config.reference.do_plot = true;                            % save respiratory-reference QC figure
config.resp.do_plot = false;                                % save breath extraction diagnostic plots

% MANUAL REVIEW
config.resp.manual_control = true;                          % separately review respiratory peaks/troughs before label detection; cached after confirmation
config.LabelEdit.start_from = 'automatic';
config.LabelEdit.reviewer_role = 'researcher';
config.LabelEdit.reviewer_id = '';                           % optional reviewer identifier; may remain empty
config.LabelEdit.window_sec = 1000;                           % visible time span for manual label GUI scrolling

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% RUN THE MAIN SCRIPT
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

run_magma(config);
