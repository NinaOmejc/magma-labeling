function config = get_config_defaults()
% GET_CONFIG_DEFAULTS Define MAGMA recording-analysis configuration defaults.
% Group-analysis settings are defined in main_group.m.
%
% Outputs:
%   config - Scalar pipeline configuration struct.


    config = struct;                                                                                   % main configuration container
    config.path_data_in = 'D:\Projects\MAGMA\raw_data';                                                % *** folder with raw input .dat files
    config.path_results_out = 'D:\Projects\MAGMA\data_analysis\statistical_labeling';                   % *** root output folder
    config.subjects = 1;                                                                                % *** subjects to analyze
    config.measurements = [1 2];                                                                       % *** measurements to analyze - 1: pre-rehab-pre-stress, 2: pre-rehab-post-stress, 3:post-rehab-pre-stress, 4:post-rehab-post-stress
    config.exclude_recordings = [ ...                                                                   % [subject, measurement]; omit only these recordings
          3 1;   3 2; ...
         30 1;  30 2; ...
         91 1;  91 2; ...
        135 1; 135 2; ...
        ];
    config.fs = 200;                                                                                   % native/master sampling frequency (Hz) for all aligned physiological signals
    config.data_columns = {'ECG1', 'ECG2', 'SpO₂', 'Resp-Lungs', 'Blood Pressure', 'Resp-Diaphragm'};  % column names in raw data
    config.input_filename_pattern = 'ECG1_ECG2_SpO2_RespL_BP_RespD_fs200_Sub{subject}_Pom{measure}_DeTr_Norm.dat'; % The generic name of the data files
    config.labels = get_labels();
    
    % execution
    config.overwrite_results = false;                                      % *** Recompute even if label output already exists
    config.overwrite_features = false;                                     % *** Recompute respiratory features even if "*_features.mat" exists
    config.verbosity = 2;                                                   % 1 = concise progress, 2 = detailed progress
    config.make_figs_visible = 'off';                                      % create figures hidden during batch runs, so they dont pop up (for faster run)
    config.execution = struct();
    config.execution.mode = 'analyze';                                     % 'analyze', 'analyze_and_review', or 'review'
    config.execution.selected_labels = {};                                 % empty = normal full/overwrite behavior; non-empty = compute or rerun only these canonical labels
    
    % FIRST CHECK: plot [X1, X2] seconds of raw data
    config.plot_raw_data = false;                               % save an overview plot of raw signals
    config.plot_raw_data_xrange = [1, 10];                      % raw overview x-axis range in seconds

    %---- PREPROCESSING ----                
    config.preprocessing = struct();
    config.preprocessing.check_relative_belt_polarity = false;   % review persistent negative thoracoabdominal correlation
    config.detrend.method = 'none';                             % 'hpfilter': Butterworth high-pass filter with filtfilt, 'moving_detrend': moving-average trend subtraction, or 'none': no additional detrending.
    config.detrend.signals = {'Resp-Lungs', 'Resp-Diaphragm'};  % *** signals to additionally detrend before feature extraction (in general, all signals are already detrended, this is just additional moving detrend, that can be useful for some noisier data)
    config.detrend.highpass_cutoff = 0.01;                      % high-pass cutoff frequency in Hz
    config.detrend.hp_edge_pad_sec = 100;                       % reflection padding before filtfilt to reduce edge artifacts
    config.detrend.window_length = 60;                          % moving detrend window length in seconds
    config.detrend.do_plot = true;                              % save detrending diagnostic plots
    

    %---- PROBLEMS ----
    config.problems.missing_lung_belt = [ ...                  % known [subject, measurement] recordings without a usable lung belt (e.g. first 20 subjects have a broken belt)
        (1:20)', ones(20, 1); ...
        (1:20)', 2 * ones(20, 1); ...
        ];

    %---- RESPIRATION / BREATHING AMPLITUDE EXTRACTION SETTINGS ----
    config.resp.min_peak_dist_sec = 1.5;    % *** Peak selection; min time between breaths (tune if needed)
    config.resp.min_peak_prom     = 0.5;    % *** Peak selection; key knob: increase to reduce extra peaks. But then this alters also apnea detection, where the amplitudes are extremely small. Trade-off...
    config.resp.min_peak_height   = -1.0;   % only peaks that have standardized amplitude above "min_peak_height" = -1.0 are allowed.
    config.resp.smooth_sec       = 0.25;    % Pre-processing; light smoothing (seconds); set to 0 to disable
    config.resp.trough_method = 'min';      % Trough selection; 'prctile' or 'min' (default)
    config.resp.trough_prct   = 5;          % Trough selection; 5th percentile trough
    config.resp.amp_method = 'symmetric';  % Selected breath amplitude: 'expiratory' (peak to following trough), 'inspiratory' (peak to preceding trough), or 'symmetric' (peak to the mean of both troughs)
    config.resp.plot_amp_method_comparison = false; % save an optional comparison of all three breath-amplitude definitions
    config.resp.do_plot         = false;     % save breath extraction diagnostic plots

    % qc - conservative removal of likely duplicate/split automatic peaks
    config.resp.qc.enabled = true;              % enable conservative automatic peak QC before manual review
    config.resp.qc.short_ibi_ratio = 0.65;      % flag intervals that are abnormally short relative to local rhythm
    config.resp.qc.rhythm_merge_tol = 0.35;     % tolerance for removal restoring the expected local rhythm
    config.resp.qc.min_prom_ratio = 0.35;       % unusually low prominence relative to neighboring peaks

    % manual control of respiratory cycles (independent of execution.mode)
    config.resp.manual_control = true;          % allow peak edits and independent movement of existing troughs before label detection
    config.resp.recheck_cached = true;          % reopen saved landmarks/artifacts; Cancel skips this recording
    config.resp.manual_window_sec = 600;        % visible time span for manual breath GUI scrolling
    
    %---- SESSION PHYSIOLOGICAL REFERENCE ----
    config.reference.pre_start_min = 3;          % M1/M3 common reference start ( in minutes! )
    config.reference.pre_end_min = 6;            % M1/M3 common reference end
    config.reference.post_start_min = 19;        % M2/M4 common reference start
    config.reference.post_end_min = 22;          % M2/M4 common reference end
    config.reference.resp_min_breaths = 10;      % minimum valid respiratory cycles required for respiratory reference and stability-QC estimates
    config.reference.spo2_min_valid_samples = 2; % finite SpO2 samples required for a reference statistic
    config.reference.do_plot = true;             % save respiratory-reference QC figure

    % Respiratory whole-record quality control of the reference
    config.reference.resp.edge_window_sec = 180;          % duration of early and late recording regions used to compare respiratory excursion stability
    config.reference.resp.change_trigger_frac = 0.25;     % minimum fractional early-vs-late excursion change that triggers change-point assessment
    config.reference.resp.min_cost_improvement = 0.30;    % minimum relative split-model cost improvement required to support a candidate change
    config.reference.resp.raw_min_finite_fraction = 0.80; % minimum finite fraction for fixed raw-excursion references and raw apnea windows
        
    %---- GENERAL DETECTION SETTINGS
    config.grid_step_sec = 1;      % evaluation grid for "state" labels

    %---- LABEL 1 - shallow - DETECTION SETTINGS 
    config.shallow = struct();                  % shallow breathing settings
    config.shallow.amp_ratio_low    = 0.10;     % lower amplitude ratio bound relative to the per-belt session reference (so only 10 % of the reference). What is lower than 10 %, is considered apnea
    config.shallow.amp_ratio_high   = 0.70;     % upper amplitude ratio bound relative to the per-belt session reference (80 % of the reference)
    config.shallow.min_dur_sec      = 30;       % minimum merged trough-to-trough shallow-state duration
    config.shallow.do_plot           = true;    % save shallow breathing diagnostic plot

    %---- LABEL 2 - deep - DETECTION SETTINGS
    % Relative increased excursion of an uncalibrated belt. This is a
    % within-record state, not an absolute tidal-volume measurement.
    config.deep = struct();
    config.deep.amp_ratio_thr = 1.30;              % breath excursion / fixed per-belt session reference
    config.deep.min_dur_sec = 30;                  % minimum merged trough-to-trough deep-state duration
    config.deep.do_plot = true;                    % save deep breathing diagnostic plot

    %---- LABEL 3 - slow - DETECTION SETTINGS
    config.slow = struct();                % slow breathing settings
    config.slow.analysis_win_sec = 60;     % 60-s respiratory-rate analysis window (use the preceding 60 s of breathing to obtain a reasonably stable estimate of respiratory rate.)
    config.slow.rr_thr_bpm       = 10;     % window RR = 60/mean(IBI) <= 10 bpm
    config.slow.min_dur_sec      = 30;     % minimum final localized slow-state duration 
    config.slow.plot_rr_step_sec = 5;      % display RR as held values that can change 12 times/min (60/5). So its averaged over X seconds, here 5 seconds.
    config.slow.do_plot          = true;   % save slow breathing diagnostic plot

    %---- LABEL 4 - rapid - DETECTION SETTINGS
    config.rapid = struct();                                      % rapid breathing settings
    config.rapid.analysis_win_sec = 60;                           % 60-s respiratory-rate analysis window
    config.rapid.rr_thr_bpm       = 20;                           % window RR = 60/mean(IBI) >= 20 bpm
    config.rapid.min_dur_sec      = 30;                           % minimum final localized rapid-state duration
    config.rapid.plot_rr_step_sec = 5;                            % display RR as held values at this step size in seconds
    config.rapid.do_plot         = true;                          % save rapid breathing diagnostic plot

    %---- LABEL 5 - irregular - DETECTION SETTINGS
    config.irregular = struct();              % irregular breathing settings
    config.irregular.analysis_win_sec = 120;   % trailing IBI-variability analysis window (history used to estimate CoV)
    config.irregular.cov_thr   = 0.4;         % CoV threshold for irregularity
    config.irregular.plot_cov_step_sec = 1;   % display CoV as held values over "step_sec" windows (just for display)
    config.irregular.do_plot       = true;    % save irregular breathing diagnostic plot

    %---- LABEL 6 - apnea - DETECTION SETTINGS
    config.apnea = struct();                          % apnea settings
    config.apnea.min_dur_sec = 10;                % defining apnea duration and amplitude/raw evidence-window duration
    config.apnea.amp_ratio_thr = 0.10;            % breath amplitude / fixed session breath-amplitude reference
    config.apnea.raw_excursion_ratio_thr = 0.10;  % raw P95-P5 / fixed session raw-excursion reference
    config.apnea.do_plot = true;                  % save apnea diagnostic plot

    %---- LABEL 7 - sigh - DETECTION SETTINGS
    config.sigh = struct();                      % sigh detection settings
    config.sigh.method = 'session_reference_2x'; % fixed session reference (default); alternatives: 'rolling_median_2x', 'global_ratio_outlier', 'legacy_60s'
    config.sigh.session_ratio_threshold = 2.0;  % canonical breath amplitude / existing fixed session reference
    config.sigh.rolling_window_breaths = 15;     % complete centered window; first/last complete baselines extend unchanged to the edges
    config.sigh.rolling_min_valid_breaths = 3;   % minimum finite positive canonical amplitudes within the full window
    config.sigh.rolling_ratio_threshold = 2.0;   % selected breath amplitude must be at least twice its local rolling median
    config.sigh.compare_methods = false;         % report/plot session_reference_2x versus rolling_median_2x, on jointly evaluable breaths
    config.sigh.ratio_prctile = 98;              % top 2% normalized breaths are sigh candidates
    config.sigh.min_abs_ratio = 2.0;             % minimum amplitude/reference ratio for sigh candidates
    config.sigh.iqr_k = 3.5;                     % IQR multiplier for outlier-based sigh detection
    config.sigh.min_gap_sec = 2;                 % minimum time between separate sigh events (check if this condition actually makes sense)
    config.sigh.do_plot = true;                  % save sigh diagnostic plot
        
    % Legacy option: previous 60 s thresholding
    config.sigh.legacy_prev_win_sec = 60;        % prior-window length for legacy sigh method
    config.sigh.legacy_amp_ratio_thr = 1.5;      % amplitude ratio threshold for legacy sigh method
    config.sigh.legacy_min_prev_breaths = 3;     % minimum previous breaths for legacy sigh method

    %---- LABEL 8 - periodic (periodic breathing / Cheyne-Stokes-like effort pattern)
    config.periodic = struct();
    config.periodic.primary_method = 'eami';     % explicit source of the canonical periodic event set: 'eami' or 'guyot'
    config.periodic.do_plot = true;              % save the two-method comparison figure

    % Fernandez Tellez et al., Sleep 2015 (DOI 10.5665/sleep.4494). 
    config.periodic.eami = struct();
    config.periodic.eami.resp_band_hz = [0.125 0.40];   % Respiratory frequency band in Hz. 0.125-0.40 Hz corresponds to approximately 7.5-24 breaths/min.
    config.periodic.eami.bandpass_order = 12;           % Overall Butterworth band-pass filter order. (Higher orders produce sharper frequency cutoffs, but also more edge artefacts)
    config.periodic.eami.resample_hz = 5;               % Sampling rate (Hz) after respiratory band-pass filtering.
    config.periodic.eami.envelope_lowpass_hz = 0.125;   % Low-pass cutoff (Hz) applied to the rectified respiratory signal. Produces a smooth amplitude envelope representing changes in breathing amplitude over time rather than individual breaths.
    config.periodic.eami.envelope_lowpass_order = 6;    % Butterworth low-pass filter order for amplitude-envelope extraction.
    config.periodic.eami.energy_win_sec = 60;           % Length (seconds) of the centered sliding window used to calculate the locally mean-removed energies of the respiratory signal and its amplitude envelope. The paper reports relative insensitivity once the window exceeds about 40 s.
    config.periodic.eami.threshold = 0.40;              % *** Minimum eAMI value indicating periodic amplitude modulation. A window is positive when eAMI >= threshold.

    % Guyot et al., PLOS ONE 2020 (DOI 10.1371/journal.pone.0221191).
    % The centered window/overlap and Matrix Pencil structure follow the paper.
    % The configured [0.008 0.050]-Hz f_m band is MAGMA-adapted. MAGMA also
    % uses a 1-Hz reconstruction and reviewed canonical breath amplitudes
    % instead of the paper's change-point breath front-end.
    config.periodic.guyot = struct();
    config.periodic.guyot.resample_hz = 1;                  % Sampling rate (Hz) of the reconstructed breath-amplitude envelope. Individual breath amplitudes are interpolated onto a 1-Hz timeline.
    config.periodic.guyot.window_sec = 120;                 % Duration (seconds) of each analysis window, for the Matrix Pencil method.
    config.periodic.guyot.overlap_fraction = 0.50;          % Fractional overlap between consecutive analysis windows.  0.90 means 90% overlap
    config.periodic.guyot.h_threshold = 0.5;                % *** h > 0.5 is required for a positive window.
    config.periodic.guyot.fm_band_hz = [0.008 0.050];       % Accepted modulation-frequency range in Hz. 0.008-0.050 Hz corresponds to modulation periods of approximately 125-20 seconds
    config.periodic.guyot.min_zone_sec = 60;                % Minimum duration (seconds) of a continuous positive interval.
    config.periodic.guyot.gap_factor = 3;                   % Threshold for identifying unusually long gaps between breath peaks.

    %---- LABEL 9 - thoracic - DETECTION SETTINGS
    % Relative thoracoabdominal excursion dominance after normalizing each
    % uncalibrated belt to its own fixed session reference. The threshold is
    % an operational automatic-label rule, not a validated clinical cutoff.
    config.thoracic = struct();
    config.thoracic.dominance_ratio_thr = 1.5;          % normalized thoracic / normalized abdominal excursion
    config.thoracic.analysis_win_sec = 30;              % common robust-median evidence window
    config.thoracic.min_dur_sec = 30;                   % sustained dominance duration
    config.thoracic.min_breaths = 3;                    % minimum finite positive breaths per belt/window
    config.thoracic.do_plot = true;                     % save relative-balance diagnostic plot

    %---- LABEL 10 - RESPIRATORY ASYNCHRONY
    config.async = struct();

    % Method selection
    config.async.primary_method = 'wavelet_phase_offset'; % method supplying the canonical asynchrony events
    config.async.compare_methods = true;                 % compare legacy coherence evidence without combining event decisions

    % Minimum sustained event duration
    config.async.min_dur_sec = 30;                        % minimum continuous qualifying evidence, in seconds

    % Plotting
    config.async.do_plot = true;                          % save phase-offset and phase-consistency diagnostics

    % Primary method: wavelet phase offset
    config.async.phase_offset = struct();
    config.async.phase_offset.angle_threshold_deg = 30;    % minimum absolute mean belt phase offset; research cutoff, not clinically validated
    config.async.phase_offset.summary_cycles = 5;          % centered circular-summary window in respiratory cycles
    config.async.phase_offset.min_resultant_length = 0.80; % minimum circular consistency for an assessable phase mean (0-1)

    %---- LABEL 11 - desat - DETECTION SETTINGS
    config.desat = struct();
    config.desat.spo2_floor = 90;             % absolute SpO2 threshold for desaturation
    config.desat.drop_thr = 3;                % drop in percentage points from the session SpO2 reference
    config.desat.min_dur_sec = 10;            % minimum desaturation duration in seconds
    config.desat.do_plot = true;              % save desaturation diagnostic plot

    % HOW TO REPRESENT RESULTS
    config.LabelMask = struct();                 % label-mask heatmap figure
    config.LabelMask.do_plot = true;             % generate a label-mask summary figure
    config.LabelMask.use_long_names = true;      % use long dysfunction names on the y-axis instead of only short codes

    config.PhenotypeSummary = struct();           % recording-level numeric phenotype summary figure
    config.PhenotypeSummary.do_plot = true;       % generate the phenotype summary after the final bundle is assembled
    
    %---- MANUAL LABEL EVENT EDITING
    config.LabelEdit = struct();
    config.LabelEdit.start_from = 'automatic';   % 'automatic' or 'latest_reviewed' GUI starting annotations
    config.LabelEdit.reviewer_role = 'researcher'; % flexible non-identifying role stored with the review round
    config.LabelEdit.reviewer_id = '';           % optional reviewer identifier; may remain empty
    config.LabelEdit.notes = '';                 % optional free-text review notes
    config.LabelEdit.window_sec = 800;           % visible time span for manual label GUI scrolling
    config.LabelEdit.min_interval_sec = 30;       % minimum drag interval accepted as a manual event
    config.LabelEdit.filename_suffix = '_manual_label_events.mat';

    %---- PER-RECORDING HDF5 EXCHANGE EXPORT
    % MAT remains authoritative and is not replaced. HDF5 contains native
    % numeric/text datasets plus a separate export-only lower-rate ML timeline.
    config.HDF5 = struct();
    config.HDF5.enabled = false;
    config.HDF5.filename_suffix = '_results.h5';
    config.HDF5.include_raw_signals = false;
    config.HDF5.include_preprocessed_signals = true;
    config.HDF5.include_ml_signals = true;
    config.HDF5.ml_sampling_hz = 10;
    config.HDF5.signal_datatype = 'single';
    config.HDF5.compression_level = 4;
    config.HDF5.upstream_input_preprocessing = 'external / not fully documented';

end
