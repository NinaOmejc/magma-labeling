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
config.subjects = [21];
config.measurements = [1];
config.exclude_recordings = [ ...                   % [subject, measurement]; omit only these recordings
      3 1;   3 2; ...
     30 1;  30 2; ...
     91 1;  91 2; ...
    135 1; 135 2; ...
    ];

% EXECUTION
config.overwrite_results = true;       % If true, recompute even if "*_results.mat" output already exists.
config.overwrite_features = false;      % If true, recompute respiratory features even if "*_features.mat" already exists.
config.resp.recheck_cached = true;      % reopen saved landmarks/artifacts; Cancel skips this recording
config.execution.mode = 'analyze';      % 'analyze', 'analyze_and_review', or 'review_only'.

% LABEL SELECTION
config.execution.selected_labels = {};
% Empty = normal behavior: new recordings analyze all labels; existing recordings obey config.overwrite_results.
% To calculate or rerun only selected labels, for example:
% config.execution.selected_labels = {'irregular'};
% config.execution.selected_labels = {'irregular', 'slow'};

% RESPIRATORY REPRESENTATION
config.resp.amp_method = 'symmetric';  % Selected breath amplitude: 'expiratory' (peak to following trough), 'inspiratory' (peak to preceding trough), or 'symmetric' (peak to the mean of both troughs)
config.resp.plot_amp_method_comparison = false; % save an optional comparison of all three breath-amplitude definitions

% PLOTTING
config.plot_raw_data = false;                               % save an overview plot of raw signals
config.reference.do_plot = true;                            % save respiratory-reference QC figure
config.shallow.do_plot = true;                              % save shallow breathing diagnostic plot
config.deep.do_plot = true;                                 % save deep breathing diagnostic plot
config.slow.do_plot  = true;                                % save slow breathing diagnostic plot
config.rapid.do_plot = true;                                % save rapid breathing diagnostic plot
config.irregular.do_plot = true;                            % save irregular breathing diagnostic plot
config.apnea.do_plot = true;                                % save apnea diagnostic plot
config.sigh.do_plot = true;                                 % save sigh diagnostic plot
config.periodic.do_plot = true;                             % save the two-method comparison figure
config.thoracic.do_plot = true;                             % save relative-balance diagnostic plot
config.async.do_plot = true;                                % save respiratory asynchrony diagnostic plot
config.async.plot_legacy_coherence = false;                 % optionally add legacy mid-band coherence as the bottom panel
config.desat.do_plot = true;                                % save desaturation diagnostic plot
config.LabelMask.do_plot = true;                            % generate a label-mask summary figure

% MANUAL REVIEW
config.resp.manual_control = true;                          % separately review respiratory peaks/troughs before label detection; cached after confirmation
config.LabelEdit.start_from = 'automatic';
config.LabelEdit.reviewer_role = 'researcher';
config.LabelEdit.reviewer_id = '';                           % optional reviewer identifier; may remain empty
config.LabelEdit.window_sec = 800;                           % visible time span for manual label GUI scrolling

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% RUN THE MAIN SCRIPT
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

run_magma(config);
