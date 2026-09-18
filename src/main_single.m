% Run MAGMA with the user-facing configuration.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% SETTINGS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Advanced scientific thresholds and processing defaults are defined in get_config_defaults.m. 
config = get_config_defaults(); 

% Here below are the main arguments to be checked and modified:

% INPUT / OUTPUT
config.path_data_in = 'D:\Projects\MAGMA\raw_data';
config.path_results_out = 'D:\Projects\MAGMA\data_analysis\statistical_labeling';
config.fs = 200;
config.subjects = [21];
config.remove_subjects = [3 30 91];
config.measurements = [1 2];
config.subjects(ismember(config.subjects, config.remove_subjects)) = [];

% EXECUTION
config.overwrite_results = false;       % If true, recompute even if "*_labels.h5" output already exists.
config.overwrite_features = false;      % If true, recompute respiratory features even if "*_features.mat" already exists.
config.verbosity = 2;                   % 1 = concise progress, 2 = detailed progress.
config.execution.mode = 'analyze_only'; % 'analyze_only', 'analyze_and_review', or 'review_only'.

% RESPIRATORY REPRESENTATION
config.resp.amp_method = 'symmetric';  % Selected breath amplitude: 'expiratory' (peak to following trough), 'inspiratory' (peak to preceding trough), or 'symmetric' (peak to the mean of both troughs)
config.resp.plot_amp_method_comparison = true; % save an optional comparison of all three breath-amplitude definitions

% PLOTTING
config.make_figs_visible = 'off';                           % If 'off' plots are only saved, and not shown, which increases the speed.
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
config.resp.manual_control = true;                          % this review is the base of the analysis (checking peaks and troughts of breaths), should be done carefully and always. Its done only once, then its saved and reloaded.
config.LabelEdit.apply_saved_edits = false;
config.LabelEdit.save_edits = true;
config.LabelEdit.start_from = 'automatic';
config.LabelEdit.reviewer_role = 'researcher';

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% RUN THE MAIN SCRIPT
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

run_magma(config);
