function config = get_config()

    %---- GENERAL SETTINGS ----
    config = struct;                                                                                    % main configuration container
    config.path_data_in = 'D:\Projects\MAGMA\raw_data';                                                 % folder with raw input .dat files
    config.path_results_out = 'D:\Projects\MAGMA\data_analyis\disorder_classification';                 % root output folder
    config.fs = 200;                                                                                    % raw sampling frequency in Hz
    config.new_fs = 20;                                                                                 % sampling frequency after preprocessing in Hz
    config.data_columns = {'ECG1', 'ECG2', 'SpO₂', 'Resp-Lungs', 'Blood Pressure', 'Resp-Diaphragm'};   % column names in raw data
    config.labels = get_labels();                                                                       % canonical label names and indices
    config.plot_raw_data = true;                                                                        % save an overview plot of raw signals
    config.plot_raw_data_xrange = [1, 10];                                                              % raw overview x-axis range in seconds
    config.save_plots = true;                                                                           % save all plots to the subject output folder
    config.plot_format     = 'png';      
    config.plot_dpi        = 150;                                                                       % resolution of the saved figures
    config.make_figs_visible = 'off';                                                                   % create figures hidden during batch runs, so they dont pop up (for faster run)
    config.overwrite_results = true;   % recompute even if label output already exists (but recompute only the labeling, the features will remain computed if the file "*_features.mat" exists. If you want to recompute features, delete the file.

    %---- PREPROCESSING ----                
    config.detrend.method = 'hpfilter';                         % 'hpfilter': Butterworth high-pass filter with filtfilt or 'moving_detrend', moving-average trend subtraction. 
    config.detrend.signals = {'Resp-Lungs', 'Resp-Diaphragm'};  % signals to additionally detrend before feature extraction (in general, all signals are already detrended by Marcin, this is just additional moving detrend for some noisier data)
    config.detrend.highpass_cutoff = 0.01;                      % high-pass cutoff frequency in Hz
    config.detrend.hp_edge_pad_sec = 100;                       % reflection padding before filtfilt to reduce edge artifacts
    config.detrend.window_length = 60;                          % moving detrend window length in seconds
    config.detrend.do_plot = false;                             % save detrending diagnostic plots
    
    %---- PROBLEMS ----
    config.problems.subjects_with_broken_lung_belt = 1:25;      % subjects where lung belt signal should be ignored 

    %---- STATIC BASELINE SETTINGS ----
    config.baseline_sec = 60;           % static baseline segment length in seconds
    config.baseline_location = '5/20';  % It can either be 'first', 'second', '5/20' or 'last' minute of the data.

    %---- ROLLING RESPIRATORY BASELINE SETTINGS ----
    config.rolling_baseline.enabled = true;     % use time-varying respiratory amplitude baseline (sometimes data are unstationary, and this helps. If the data are stationary, the rolling baseline should be similar to static baseline.)
    config.rolling_baseline.win_sec = 360;      % window length for rolling amplitude baseline
    config.rolling_baseline.lag_sec = 60;       % when computing the rolling baseline at time t, ignore the most recent 30 seconds before t. [t - win_sec - lag_sec, t - lag_sec]
    config.rolling_baseline.min_breaths = 10;   % minimum breaths needed for rolling baseline estimate
    config.rolling_baseline.method = 'median';  % statistic used for rolling amplitude baseline
    config.rolling_baseline.do_plot = true;     % save rolling baseline diagnostic plot

    %---- RESPIRATION / BREATHING AMPLITUDE EXTRACTION SETTINGS ----
    config.resp.min_peak_dist_sec = 1.0;    % Peak selection; min time between breaths (tune if needed)
    config.resp.min_peak_prom     = 0.2;    % Peak selection; key knob: increase to reduce extra peaks. But then this alters also apnea detection, where the amplitudes are extremely small. Trade-off...
    config.resp.min_peak_height   = -1.0;   % only peaks that have standardized amplitude above "min_peak_height" = -1.0 are allowed.
    config.resp.smooth_sec       = 0.25;    % Pre-processing; light smoothing (seconds); set to 0 to disable
    config.resp.trough_method = 'min';      % Trough selection; 'prctile' or 'min' (default)
    config.resp.trough_prct   = 5;          % Trough selection; 5th percentile trough
    config.resp.do_plot         = true;     % save breath extraction diagnostic plots

    % qc - quality control of automatic peak detection
    config.resp.qc.enabled = true;              % conservative automatic removal of likely artefact peaks before manual review
    config.resp.qc.min_amp_ratio = 0.25;        % candidate artefact if breath amp is below this fraction of local median
    config.resp.qc.min_prom_ratio = 0.35;       % require prominence to stay above this fraction of local median prominence
    config.resp.qc.min_ibi_sec = 1.0;           % hard physiologic lower bound for inter-breath interval
    config.resp.qc.short_ibi_ratio = 0.65;      % also flag peaks that are much too close relative to local rhythm
    config.resp.qc.rhythm_merge_tol = 0.35;     % if two short adjacent intervals merge back to one normal interval, treat as split-breath artefact
    config.resp.qc.noise_window_sec = 8.0;      % local window used to estimate signal noise around a candidate peak
    config.resp.qc.noise_prom_mult = 3.0;       % prominence must clear this multiple of local noise
    config.resp.qc.local_window_breaths = 7;    % neighboring breaths used for local rhythm/amplitude reference
    
    % manual control of peak detection
    config.resp.manual_control = true;          % allow click-to-add/remove breath peaks before label detection (it takes time, but important to check the quality of detection, and not blindly follow automatic detection - GUI will appear for editing.)
    config.resp.manual_window_sec = 300;        % visible time span for manual breath GUI scrolling
    config.resp.manual_peak_search_sec = 1.0;   % add peak at local maximum within this window around the click
        
    %---- SPO2 / DESATURATION FEATURE EXTRACTION
    config.spo2.spo2_floor  = 90;   % absolute threshold (%) if spo2 goes below, its considered desaturation
    config.spo2.drop_thr    = 3;    % relative drop threshold (% points). if the spo2 decreases for more than "drop_thr %" from the baseline, its considered desaturation
    config.spo2.min_dur_sec = 10;   % episode duration (seconds)
    config.spo2.desat_association_delay_sec = 5; % max delay after a breathing event for associating a SpO2 drop; increase if pulse-ox lag appears longer

    %---- GENERAL DETECTION SETTINGS
    config.grid_step_sec = 1;      % evaluation grid for "state" labels

    %---- LABEL 1 - ShB - DETECTION SETTINGS 
    config.ShB = struct();                  % shallow breathing settings
    config.ShB.amp_ratio_low    = 0.65;     % lower amplitude ratio bound for shallow breaths (35 % decreased from baseline)
    config.ShB.amp_ratio_high   = 0.80;     % upper amplitude ratio bound for shallow breaths (20 % decreased from baseline)
    config.ShB.min_dur_sec       = 30;      % minimal duration of shallow breathing to be counted as dysfunction. in seconds
    config.ShB.exclude_desat     = true;    % do not label shallow breathing during desaturation.
    config.ShB.do_plot           = true;    % save shallow breathing diagnostic plot

    %---- LABEL 2 - IrB - DETECTION SETTINGS 
    config.IrB = struct();              % irregular breathing settings
    config.IrB.min_dur_sec = 60;        % rolling window length and sustained endpoint duration
    config.IrB.cov_thr   = 0.3;         % CoV threshold for irregularity
    config.IrB.robust_cov_thr = 0.25;   % robust CoV threshold: 1.4826*MAD(IBI)/median(IBI)
    config.IrB.detection_metric = 'robust_cov'; % options: 'cov', 'robust_cov', 'either', 'both'
    config.IrB.rmssd_thr = 0.0;         % if zero, do not include this measure
    config.IrB.pause_thr_sec = 10;      % exclude irregular windows with pauses at or above this length
    config.IrB.plot_cov_step_sec = 5;   % display CoV as held values over "step_sec" windows (just for display)
    config.IrB.do_plot       = true;    % save irregular breathing diagnostic plot

    %---- LABEL 3 - SlB - DETECTION SETTINGS 
    config.SlB = struct();                % slow breathing settings
    config.SlB.analysis_win_sec = 60;     % rolling analysis window (30–60 s allowed)
    config.SlB.rr_thr_bpm       = 10;     % mean RR <= 10 bpm
    config.SlB.min_dur_sec      = 30;     % sustained >= 30 s
    config.SlB.classify_depth   = true;   % Depth classification (slow + shallow vs slow + deep)
    config.SlB.mark_desat        = true;  % Desaturation logic (append "_desat" if overlap)
    config.SlB.plot_rr_step_sec = 5;      % display RR as held values that can change 12 times/min (60/5). So its averaged over X seconds, here 5 seconds.
    config.SlB.do_plot          = true;   % save slow breathing diagnostic plot

    %---- LABEL 4: RaB 
    config.RaB = struct();                                      % rapid breathing settings
    config.RaB.rr_thr_bpm       = 20;                           % mean RR >= 20 bpm
    config.RaB.min_dur_sec      = 30;                           % rolling RR window length and sustained endpoint duration
    config.RaB.classify_depth   = true;                         % detect rapid shallow/deep subtype modifiers
    config.RaB.deep_lo_ratio    = 1.20;                         % 20% above baseline
    config.RaB.deep_hi_ratio    = 1.35;                         % 35% above baseline
    config.RaB.subtype_min_overlap_frac = 0.5;                  % rapid subtype is assigned only if >= this fraction of the event overlaps shallow/deep amplitude evidence
    config.RaB.mark_desat      = true;                          % mark rapid subtype as desat if desaturation is associated
    config.RaB.plot_rr_step_sec = 5;                            % display RR as held values at this step size in seconds
    config.RaB.do_plot         = true;                          % save rapid breathing diagnostic plot

    %---- LABEL 5: Respiratory Asynchrony
    config.ReA = struct();                  % respiratory asynchrony settings
    config.ReA.target_fs = 20;              % downsample target for wavelet phase-coherence analysis
    config.ReA.fmin = 0.052;                % lower WT frequency bound from Tomislav's script
    config.ReA.fmax = 2.0;                  % upper WT frequency bound from Tomislav's script
    config.ReA.f0 = 1;                      % wavelet resolution parameter from Tomislav's script
    config.ReA.low_mid_cut_hz = 0.145;      % low vs respiratory-band split
    config.ReA.mid_high_cut_hz = 0.6;       % respiratory-band vs high split
    config.ReA.tlphcoh_cycles = 10;         % time-localized phase coherence window in cycles
    config.ReA.min_dur_sec = 30;            % sustained low-coherence deviation duration
    config.ReA.baseline_mad_k = 3;          % robust spread multiplier for baseline-relative threshold
    config.ReA.min_abs_drop = 0.15;         % minimum coherence drop from baseline median
    config.ReA.min_deviating_bins = 1;      % number of frequency bins that must deviate
    config.ReA.plot_step_sec = 5;           % display coherence as held medians at this step (in seconds)
    config.ReA.do_plot          = true;     % save respiratory asynchrony diagnostic plot

    %---- LABEL 6: SpO2 desaturation
    config.Des = struct();                  % desaturation settings (its exactly the same as feature extraction, see SPO2 / DESATURATION FEATURE EXTRACTION above)
    config.Des.do_plot = true;              % save desaturation diagnostic plot

    %---- LABEL 7: Apnea
    config.Apn = struct();                  % apnea settings
    config.Apn.amp_ratio_thr    = 0.10;     % <=10% of baseline in BOTH belts (if only one belt is working, then consider only one)
    config.Apn.min_dur_sec      = 10;       % it needs to be sustained for more than X (here 10) seconds
    config.Apn.mark_desat       = true;     % append "_desat" if a SpO2 drop is associated using config.spo2.desat_association_delay_sec
    config.Apn.raw_flat_enabled = true;     % optional second apnea detector based directly on raw belt flatness/low motion, independent of detected breath peaks
    config.Apn.raw_flat_win_sec = 10;       % raw-signal analysis window for flat/low-motion apnea evidence
    config.Apn.raw_flat_ref_win_sec = 60;   % prior raw-signal reference window for normal belt motion
    config.Apn.raw_flat_ref_lag_sec = 10;   % ignore the most recent seconds when estimating the raw-signal reference
    config.Apn.raw_flat_ref_floor_ratio = 0.25;     % prevent raw reference from collapsing during long flat intervals
    config.Apn.raw_flat_motion_ratio_thr = 0.10;    % raw robust excursion must be <= this fraction of local raw motion reference
    config.Apn.raw_flat_slope_ratio_thr = 0.15;     % raw median abs slope must be <= this fraction of local raw slope reference
    config.Apn.raw_flat_hist_peak_frac_thr = 0.35;  % histogram peak must contain at least this fraction of window samples
    config.Apn.raw_flat_min_plateau_sec = 5;        % minimum continuous time spent inside the dominant histogram amplitude band
    config.Apn.raw_flat_hist_bins = 40;             % histogram bins used to find held-amplitude plateaus
    config.Apn.do_plot = true;              % save apnea diagnostic plot

    %---- LABEL 8: Sigh
    config.Sig = struct();                      % sigh detection settings
    config.Sig.method = 'global_ratio_outlier'; % options: 'global_ratio_outlier' or 'legacy_60s'
    config.Sig.ratio_prctile = 98;              % top 2% normalized breaths are sigh candidates
    config.Sig.min_abs_ratio = 2.0;             % minimum amplitude/reference ratio for sigh candidates
    config.Sig.iqr_k = 3.5;                     % IQR multiplier for outlier-based sigh detection
    config.Sig.min_gap_sec = 2;                 % minimum time between separate sigh events (check if this condition actually makes sense)
    config.Sig.manual_control = true;           % allow click-to-add/remove sigh markers in GUI - GUI will appear where sighs can be edited!)
    config.Sig.manual_window_sec = 1200;        % visible time span for manual GUI scrolling
    config.Sig.do_plot = true;                  % save sigh diagnostic plot
        
    % Legacy option: previous 60 s thresholding
    config.Sig.legacy_prev_win_sec = 60;        % prior-window length for legacy sigh method
    config.Sig.legacy_amp_ratio_thr = 1.5;      % amplitude ratio threshold for legacy sigh method
    config.Sig.legacy_min_prev_breaths = 3;     % minimum previous breaths for legacy sigh method
end


function labels = get_labels()
    labels_long = {'ShallowBreathing', 'IrregularBreathing', 'SlowBreathing', 'Rapid Breathing', 'RespiratoryAsynchrony', 'Desaturation', 'Apnea', 'Sigh'};
    labels_short = {'ShB', 'IrB', 'SlB', 'RaB', 'ReA', 'Des', 'Apn', 'Sig'};
    labels_idx = 1:8;
    labels = struct( ...
        'idx',   num2cell(labels_idx), ...
        'long',  labels_long, ...
        'short', labels_short );
end




