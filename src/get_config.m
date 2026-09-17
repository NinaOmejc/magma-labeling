function config = get_config()
% GET_CONFIG Define default inputs, thresholds, plotting, and export settings.
%
% Outputs:
%   config - Scalar pipeline configuration struct. Core fields path_data_in,
%            path_results_out, input_filename_pattern, subjects/remove_subjects,
%            measurements, fs (Hz), data_columns, and labels define input identity.
%            overwrite_results/overwrite_features and make_figs_visible control
%            execution; plot_raw_data/plot_raw_data_xrange and LabelMask control
%            overview plots. Nested problems records known data exclusions;
%            detrend controls preprocessing; resp controls breath extraction/review;
%            reference controls session/global baseline estimation. shallow, deep,
%            slow, rapid, irregular, apnea, sigh, periodic, thoracic, async, and desat
%            contain detector thresholds/windows; grid_step_sec defines their common
%            analysis grid. LabelEdit controls manual interval review and HDF5
%            controls export. Durations are seconds and respiratory rates are
%            breaths/min unless a field or inline comment states otherwise.

    config = struct;                                                                                   % main configuration container
    config.path_data_in = 'D:\Projects\MAGMA\raw_data';                                                % *** folder with raw input .dat files
    config.path_results_out = 'D:\Projects\MAGMA\data_analysis\statistical_labeling';               % *** root output folder
    config.subjects = 1;                                                                                % *** subjects to analyze
    config.remove_subjects = [3 30 91];                                                                % *** subjects to not analyze
    config.measurements = [1];                                                                       % *** measurements to analyze - 1: pre-rehab-pre-stress, 2: pre-rehab-post-stress, 3:post-rehab-pre-stress, 4:post-rehab-post-stress
    config.fs = 200;                                                                                   % native/master sampling frequency (Hz) for all aligned physiological signals
    config.data_columns = {'ECG1', 'ECG2', 'SpO₂', 'Resp-Lungs', 'Blood Pressure', 'Resp-Diaphragm'};  % column names in raw data
    config.input_filename_pattern = 'ECG1_ECG2_SpO2_RespL_BP_RespD_fs200_Sub{subject}_Pom{measure}_DeTr_Norm.dat'; % The generic name of the data files
    config.labels = get_labels();                                          % canonical label names and indices
    config.make_figs_visible = 'on';                                      % create figures hidden during batch runs, so they dont pop up (for faster run)
    config.overwrite_results = true;                                      % *** Recompute even if label output already exists
    config.overwrite_features = false;                                     % *** Recompute respiratory features even if "*_features.mat" exists
    
    % FIRST CHECK: plot [X1, X2] seconds of raw data
    config.plot_raw_data = false;                               % save an overview plot of raw signals
    config.plot_raw_data_xrange = [1, 10];                      % raw overview x-axis range in seconds

    %---- PREPROCESSING ----                
    config.detrend.method = 'none';                         % 'hpfilter': Butterworth high-pass filter with filtfilt, 'moving_detrend': moving-average trend subtraction, or 'none': no additional detrending.
    config.detrend.signals = {'Resp-Lungs', 'Resp-Diaphragm'};  % *** signals to additionally detrend before feature extraction (in general, all signals are already detrended, this is just additional moving detrend, that can be useful for some noisier data)
    config.detrend.highpass_cutoff = 0.01;                      % high-pass cutoff frequency in Hz
    config.detrend.hp_edge_pad_sec = 100;                       % reflection padding before filtfilt to reduce edge artifacts
    config.detrend.window_length = 60;                          % moving detrend window length in seconds
    config.detrend.do_plot = true;                              % save detrending diagnostic plots
    
    %---- PROBLEMS ----
    config.problems.missing_lung_belt = [ ...                  % known [subject, measurement] recordings without a usable lung belt (e.g. first 20 subjects have a broken belt)
        (1:20)', ones(20, 1); ...
        (1:20)', 2 * ones(20, 1)];

    %---- RESPIRATION / BREATHING AMPLITUDE EXTRACTION SETTINGS ----
    config.resp.min_peak_dist_sec = 1.0;    % *** Peak selection; min time between breaths (tune if needed)
    config.resp.min_peak_prom     = 0.2;    % *** Peak selection; key knob: increase to reduce extra peaks. But then this alters also apnea detection, where the amplitudes are extremely small. Trade-off...
    config.resp.min_peak_height   = -1.0;   % only peaks that have standardized amplitude above "min_peak_height" = -1.0 are allowed.
    config.resp.smooth_sec       = 0.25;    % Pre-processing; light smoothing (seconds); set to 0 to disable
    config.resp.trough_method = 'min';      % Trough selection; 'prctile' or 'min' (default)
    config.resp.trough_prct   = 5;          % Trough selection; 5th percentile trough
    config.resp.amp_method = 'expiratory';  % Selected breath amplitude: 'expiratory' (peak to following trough), 'inspiratory' (peak to preceding trough), or 'symmetric' (peak to the mean of both troughs)
    config.resp.plot_amp_method_comparison = false; % save an optional comparison of all three breath-amplitude definitions
    config.resp.do_plot         = true;     % save breath extraction diagnostic plots

    % qc - conservative removal of likely duplicate/split automatic peaks
    config.resp.qc.enabled = true;              % enable conservative automatic peak QC before manual review
    config.resp.qc.short_ibi_ratio = 0.65;      % flag intervals that are abnormally short relative to local rhythm
    config.resp.qc.rhythm_merge_tol = 0.35;     % tolerance for removal restoring the expected local rhythm
    config.resp.qc.min_prom_ratio = 0.35;       % unusually low prominence relative to neighboring peaks
    
    % manual control of peak detection
    config.resp.manual_control = true;          % allow click-to-add/remove breath peaks before label detection (it takes time, but important to check the quality of detection, and not blindly follow automatic detection - GUI will appear for editing.)
    config.resp.manual_window_sec = 300;        % visible time span for manual breath GUI scrolling

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
    config.shallow.amp_ratio_high   = 0.80;     % upper amplitude ratio bound relative to the per-belt session reference (80 % of the reference)
    config.shallow.min_dur_sec      = 30;       % minimum merged trough-to-trough shallow-state duration
    config.shallow.do_plot           = true;    % save shallow breathing diagnostic plot

    %---- LABEL 2 - deep - DETECTION SETTINGS
    % Relative increased excursion of an uncalibrated belt. This is a
    % within-record state, not an absolute tidal-volume measurement.
    config.deep = struct();
    config.deep.amp_ratio_thr = 1.20;              % breath excursion / fixed per-belt session reference
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
    config.irregular.analysis_win_sec = 60;   % trailing IBI-variability analysis window (history used to estimate CoV)
    config.irregular.cov_thr   = 0.3;         % CoV threshold for irregularity
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
    config.sigh.method = 'rolling_median_2x';    % options: 'rolling_median_2x' (default), 'global_ratio_outlier', or 'legacy_60s'
    config.sigh.rolling_window_breaths = 15;     % complete centered window; first/last complete baselines extend unchanged to the edges
    config.sigh.rolling_min_valid_breaths = 3;   % minimum finite positive canonical amplitudes within the full window
    config.sigh.rolling_ratio_threshold = 2.0;   % selected breath amplitude must be at least twice its local rolling median
    config.sigh.compare_methods = false;         % report/plot rolling_median_2x versus global_ratio_outlier diagnostics
    config.sigh.ratio_prctile = 98;              % top 2% normalized breaths are sigh candidates
    config.sigh.min_abs_ratio = 2.0;             % minimum amplitude/reference ratio for sigh candidates
    config.sigh.iqr_k = 3.5;                     % IQR multiplier for outlier-based sigh detection
    config.sigh.min_gap_sec = 2;                 % minimum time between separate sigh events (check if this condition actually makes sense)
    config.sigh.manual_control = false;           % allow click-to-add/remove sigh markers in GUI - GUI will appear where sighs can be edited!)
    config.sigh.manual_window_sec = 1200;        % visible time span for manual GUI scrolling
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
    % The filter bands/orders, 1-Hz rate, and threshold follow the published
    % eAMI method. The 60-s energy window is a MAGMA comparison default; the
    % paper reports relative insensitivity once this window exceeds about 40 s.
    config.periodic.eami = struct();
    config.periodic.eami.resp_band_hz = [0.125 0.40];
    config.periodic.eami.bandpass_order = 12;
    config.periodic.eami.resample_hz = 1;
    config.periodic.eami.envelope_lowpass_hz = 0.125;
    config.periodic.eami.envelope_lowpass_order = 6;
    config.periodic.eami.energy_win_sec = 60;
    config.periodic.eami.threshold = 0.65;

    % Guyot et al., PLOS ONE 2020 (DOI 10.1371/journal.pone.0221191).
    % Window, overlap, h/fm criteria, one-minute zone, and three-IBI gap rule
    % follow the publication. MAGMA uses a 1-Hz reconstruction and reviewed
    % canonical MAGMA breath amplitudes instead of the paper's change-point
    % breath front-end.
    config.periodic.guyot = struct();
    config.periodic.guyot.resample_hz = 1;
    config.periodic.guyot.window_sec = 120;
    config.periodic.guyot.overlap_fraction = 0.80;
    config.periodic.guyot.h_threshold = 0.12;
    config.periodic.guyot.fm_band_hz = [0.008 0.030];
    config.periodic.guyot.min_zone_sec = 60;
    config.periodic.guyot.gap_factor = 3;

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

    %---- LABEL 10 - async - DETECTION SETTINGS
    config.async = struct();                  % respiratory asynchrony settings
    config.async.primary_method = 'wavelet_coherence_drop'; % canonical async label source: 'wavelet_coherence_drop' or 'wavelet_phase_offset'
    config.async.compare_methods = true;      % store complementary method evidence; never combines or replaces the selected primary method
    config.async.analysis_fs = 20;            % local anti-aliased analysis rate; master data and indices remain at config.fs
    config.async.f0 = 1;                      % wavelet resolution parameter from Tomislav's script
    config.async.fmin = 0.052;                % lower WT frequency bound from Tomislav's script
    config.async.low_mid_cut_hz = 0.145;      % low vs respiratory-band split
    config.async.mid_high_cut_hz = 0.6;       % respiratory-band vs high split
    config.async.fmax = 2.0;                  % upper WT frequency bound from Tomislav's script
    config.async.tlphcoh_cycles = 10;         % time-localized phase coherence window in cycles
    config.async.min_dur_sec = 30;            % sustained low-coherence deviation duration
    config.async.reference_mad_k = 3;         % robust spread multiplier for session-reference-relative threshold
    config.async.min_abs_drop = 0.15;         % minimum coherence drop from session reference median
    config.async.min_deviating_bins = 1;      % number of frequency bins that must deviate
    config.async.plot_step_sec = 5;           % display coherence as held medians at this step (in seconds)
    config.async.do_plot          = true;     % save respiratory asynchrony diagnostic plot
    config.async.phase_offset = struct();
    config.async.phase_offset.angle_threshold_deg = 30;    % operational research cutoff; not a validated clinical threshold
    config.async.phase_offset.summary_cycles = 5;          % centered circular-summary support in respiratory cycles
    config.async.phase_offset.min_resultant_length = 0.80; % minimum circular consistency for an assessable phase mean
    config.async.phase_offset.min_valid_fraction = 0.80;   % minimum valid coefficient fraction within the full summary window
    config.async.phase_offset.min_magnitude_fraction = 0.05; % per-belt wavelet-magnitude floor relative to recording median
    config.async.phase_offset.frequency_min_hz = config.async.low_mid_cut_hz;  % shared respiratory-frequency search lower bound
    config.async.phase_offset.frequency_max_hz = config.async.mid_high_cut_hz; % shared respiratory-frequency search upper bound

    %---- LABEL 11 - desat - DETECTION SETTINGS
    config.desat = struct();
    config.desat.spo2_floor = 90;             % absolute SpO2 threshold for desaturation
    config.desat.drop_thr = 3;                % drop in percentage points from the session SpO2 reference
    config.desat.min_dur_sec = 10;            % minimum desaturation duration in seconds
    config.desat.association_delay_sec = 5;   % downstream pulse-ox association allowance in seconds; never modifies respiratory labels
    config.desat.do_plot = true;              % save desaturation diagnostic plot
    config.desat.metrics = struct();
    config.desat.metrics.pre_event_lookback_sec = 30;    % descriptive local baseline only; does not affect event detection
    config.desat.metrics.min_pre_event_valid_sec = 10;   % contiguous usable non-event support required for a local baseline
    config.desat.metrics.recovery_tolerance_pp = 1;      % recovery target is local baseline minus this many percentage points
    config.desat.metrics.recovery_hold_sec = 5;          % continuous target support required for observed recovery
    config.desat.metrics.max_recovery_search_sec = 120;  % descriptive recovery-search censoring horizon

    % HOW TO REPRESENT RESULTS
    config.LabelMask = struct();                 % label-mask heatmap figure
    config.LabelMask.do_plot = true;             % generate a label-mask summary figure
    config.LabelMask.use_long_names = true;      % use long dysfunction names on the y-axis instead of only short codes
    
    %---- MANUAL LABEL EVENT EDITING
    config.LabelEdit = struct();
    config.LabelEdit.manual_control = false;      % *** open final event-interval editor before saving labels
    config.LabelEdit.apply_saved_edits = false;  % reuse saved manual event edits on rerun, even when GUI is off
    config.LabelEdit.save_edits = true;          % persist edited event intervals in the subject results folder
    config.LabelEdit.start_from = 'automatic';   % 'automatic' or 'latest_reviewed' GUI starting annotations
    config.LabelEdit.replace_reviewed = true;    % make a completed review round the active reviewed layer
    config.LabelEdit.reviewer_role = 'researcher'; % flexible non-identifying role stored with the review round
    config.LabelEdit.reviewer_id = '';           % optional reviewer identifier; may remain empty
    config.LabelEdit.notes = '';                 % optional free-text review notes
    config.LabelEdit.window_sec = 400;           % *** visible time span for manual label GUI scrolling
    config.LabelEdit.min_interval_sec = 1;       % minimum drag interval accepted as a manual event
    config.LabelEdit.filename_suffix = '_manual_label_events.mat';

    %---- PER-RECORDING ML-READY EXPORT
    % MAT remains authoritative and is not replaced. HDF5 contains simple
    % numeric/text datasets on the same native 200-Hz master timeline.
    config.HDF5 = struct();
    config.HDF5.enabled = true;
    config.HDF5.filename_suffix = '_labels.h5';
    config.HDF5.upstream_input_preprocessing = ...
        'external / not fully documented';

    % some additional logic:
    config.subjects(ismember(config.subjects, config.remove_subjects)) = [];

    % add src to path
    src_root = fileparts(mfilename('fullpath'));
    if ~isempty(src_root)
        addpath(genpath(src_root));
    end

    % save configs
    if ~isfolder(config.path_results_out)
        mkdir(config.path_results_out);
    end
    save(fullfile(base_config.path_results_out, 'analysis_configuration.mat'), 'config');

end
