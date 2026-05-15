function config = get_config()

    %---- GENERAL SETTINGS ----
    config = struct;
    config.path_data_in = 'D:\Projects\MAGMA\raw_data';
    config.path_results_out = 'D:\Projects\MAGMA\data_analyis\disorder_classification';
    config.fs = 200;  
    config.data_columns = {'ECG1', 'ECG2', 'SpO₂', 'Resp-Lungs', 'Blood Pressure', 'Resp-Diaphragm'};
    config.labels = get_labels();
    config.plot_raw_data = true;
    config.plot_raw_data_xrange = [1, 10]; % in sec
    config.save_plots = true;
    config.plot_format     = 'png';      % future-proof
    config.plot_dpi        = 150;        % resolution
    config.make_figs_visible = 'on';
    config.overwrite_results = true;

    %---- PREPROCESSING ----
    config.detrend.method = 'hpfilter'; % 'hpfilter': Butterworth high-pass filter with filtfilt or 'moving_detrend', moving-average trend subtraction
    config.detrend.signals = {'Resp-Lungs', 'Resp-Diaphragm'};
    config.detrend.highpass_cutoff = 0.01;
    config.detrend.hp_edge_pad_sec = 100;   % reflection padding before filtfilt to reduce edge artifacts
    config.detrend.window_length = 60;
    config.detrend.do_plot = false;
    
    % PROBLEMS
    config.problems.subjects_with_broken_lung_belt = 1:25;

    %---- BASELINE SETTINGS ----
    config.baseline_sec = 60;
    config.baseline_location = '5/20'; % It can either be 'first', 'second', '5/21' or 'last' minute of the data.

    %---- ROLLING RESPIRATORY BASELINE SETTINGS ----
    config.rolling_baseline.enabled = true;
    config.rolling_baseline.win_sec = 360;
    config.rolling_baseline.lag_sec = 30; % when computing the rolling baseline at time t, ignore the most recent 30 seconds before t. [t - win_sec - lag_sec, t - lag_sec]
    config.rolling_baseline.min_breaths = 10;
    config.rolling_baseline.method = 'median';
    config.rolling_baseline.do_plot = true;

    %---- RESPIRATION / BREATHING AMPLITUDE EXTRACTION SETTINGS ----
    config.resp.min_peak_dist_sec = 1.0;   % Peak selection; min time between breaths (tune if needed)
    config.resp.min_peak_prom     = 0.2;   % Peak selection; key knob: increase to reduce extra peaks
    config.resp.min_peak_height   = -1.0;   % all peaks should be on the positive side
    config.resp.min_num_peaks     = 3;    
    config.resp.smooth_sec       = 0.25;   % Pre-processing; light smoothing (seconds); set 0 to disable
    config.resp.trough_method = 'min';     % Trough selection; 'prctile' (robust) or 'min'
    config.resp.trough_prct   = 5;         % Trough selection; 5th percentile trough
    config.resp.do_plot         = true;
    config.resp.manual_control = true;      % allow click-to-add/remove breath peaks before label detection
    config.resp.manual_window_sec = 300;    % visible time span for manual breath GUI scrolling
    config.resp.manual_peak_search_sec = 1.0; % add peak at local maximum within this window around the click
    config.resp.qc.enabled = true;          % conservative automatic removal of likely artefact peaks before manual review
    config.resp.qc.min_amp_ratio = 0.25;    % candidate artefact if breath amp is below this fraction of local median
    config.resp.qc.min_prom_ratio = 0.35;   % require prominence to stay above this fraction of local median prominence
    config.resp.qc.min_ibi_sec = 1.0;       % hard physiologic lower bound for inter-breath interval
    config.resp.qc.short_ibi_ratio = 0.65;  % also flag peaks that are much too close relative to local rhythm
    config.resp.qc.rhythm_merge_tol = 0.35; % if two short adjacent intervals merge back to one normal interval, treat as split-breath artefact
    config.resp.qc.noise_window_sec = 8.0;  % local window used to estimate signal noise around a candidate peak
    config.resp.qc.noise_prom_mult = 3.0;   % prominence must clear this multiple of local noise
    config.resp.qc.local_window_breaths = 7;
    
    %---- SPO2 / DESATURATION FEATURE EXTRACTION
    config.spo2.spo2_floor  = 90;   % absolute threshold (%)
    config.spo2.drop_thr    = 3;    % relative drop threshold (% points)
    config.spo2.min_dur_sec = 10;   % episode duration (seconds)

    %---- GENERAL DETECTION SETTINGS
    config.grid_step_sec = 1;      % evaluation grid for "state" labels

    %---- LABEL 1 - ShB - DETECTION SETTINGS 
    config.ShB = struct();
    config.ShB.amp_ratio_low    = 0.65;
    config.ShB.amp_ratio_high   = 0.80;
    config.ShB.min_dur_sec       = 30; % minimal duration / analysis window size in seconds
    config.ShB.exclude_desat     = true;
    config.ShB.do_plot           = true;

    %---- LABEL 2 - IrB - DETECTION SETTINGS 
    config.IrB = struct();
    config.IrB.analysis_win_sec = 60; % analysis window size in seconds
    config.IrB.cov_thr   = 0.3;
    config.IrB.rmssd_thr = 0.0; % if zero, do not include this measure
    config.IrB.pause_thr_sec = 10;
    config.IrB.do_plot       = true;

    %---- LABEL 3 - SlB - DETECTION SETTINGS 
    config.SlB = struct();
    config.SlB.analysis_win_sec = 60;     % rolling analysis window (30–60 s allowed)
    config.SlB.rr_thr_bpm       = 10;     % mean RR <= 10 bpm
    config.SlB.min_dur_sec      = 30;     % sustained >= 30 s
    config.SlB.classify_depth   = false;   % Depth classification (slow + shallow vs slow + deep)
    config.SlB.shallow_lo_ratio = 0.20;   % 20% of baseline (Shallow amplitude band (same logic as ShB))
    config.SlB.shallow_hi_ratio = 0.35;   % 35% of baseline (Shallow amplitude band (same logic as ShB))
    config.SlB.mark_desat        = true;  % Desaturation logic (append "_desat" if overlap)
    config.SlB.desat_delay_sec   = 20;    % Desaturation logic (allow SpO2 delay (lag buffer))
    config.SlB.do_plot          = true;

    %---- LABEL 4: RaB 
    config.RaB = struct();
    config.RaB.analysis_win_sec = 30;    % mean RR window; 20 bpm sustained for >=30 s
    config.RaB.rr_thr_bpm       = 20;    % mean RR >= 20 bpm
    config.RaB.min_dur_sec      = 30;    % sustained >= 30 s
    config.RaB.classify_depth   = true;  % detect rapid shallow/deep subtype modifiers
    config.RaB.shallow_lo_ratio = config.ShB.amp_ratio_low;   % same amplitude band as ShB
    config.RaB.shallow_hi_ratio = config.ShB.amp_ratio_high;  % same amplitude band as ShB
    config.RaB.deep_lo_ratio    = 1.20;  % 20% above baseline
    config.RaB.deep_hi_ratio    = 1.35;  % 35% above baseline
    config.RaB.subtype_min_overlap_frac = 0.5; % majority of rapid event must match depth subtype
    config.RaB.mark_desat      = true;   % mark rapid subtype as desat if desaturation is associated
    config.RaB.desat_delay_sec = 20;     % allow delayed SpO2 drop after rapid breathing
    config.RaB.do_plot         = true;

    %---- LABEL 5: Respiratory Asynchrony
    config.ReA = struct();
    config.ReA.do_plot          = true;

    %---- LABEL 6: SpO2 desaturation
    config.Des = struct();
    config.Des.do_plot = true;

    %---- LABEL 7: Apnea
    config.Apn = struct();
    config.Apn.amp_ratio_thr    = 0.10;  % <=10% of baseline in BOTH belts
    config.Apn.min_dur_sec      = 10;    % >=10 s
    config.Apn.mark_desat       = true;     % append "_desat" if associated
    config.Apn.desat_lag_min_sec = 30;      % lower bound for desat association after apnea end
    config.Apn.desat_lag_max_sec = 60;      % upper bound for desat association after apnea end
    config.Apn.desat_lag_sec     = 45;      % backward-compatible alias for upper bound
    config.Apn.desat_pad_sec    = 0;        % optional extra expansion of desat events
    config.Apn.do_plot = true;

    %---- LABEL 8: Sigh
    config.Sig = struct();
    config.Sig.method = 'global_ratio_outlier'; % default: nonparametric global outliers in amplitude/baseline ratio
    config.Sig.ratio_prctile = 98;              % top 2% normalized breaths are sigh candidates
    config.Sig.do_plot = true;
    config.Sig.manual_control = true;      % allow click-to-add/remove sigh markers in GUI
    config.Sig.manual_window_sec = 1000;     % visible time span for manual GUI scrolling
    config.Sig.min_abs_ratio = 2.0;
    config.Sig.iqr_k = 3.5;
    config.Sig.min_gap_sec = 20;

    % Legacy option: previous 60 s thresholding
    config.Sig.legacy_prev_win_sec = 60;
    config.Sig.legacy_amp_ratio_thr = 1.5;
    config.Sig.legacy_min_prev_breaths = 3;
end


function labels = get_labels()
    labels_long = {'ShallowBreathing', 'IrregularBreathing', 'SlowBreathing', 'Rapid Breathing', 'RespiratoryAsynchrony', 'Desaturation', 'Apnea', 'Sigh'};
    labels_short = {'ShB', 'IrB', 'SlB', 'RaB', 'ReA', 'Des', 'Apn', 'Sig'};
    labels_idx = [1:8];
    labels = struct( ...
        'idx',   num2cell(labels_idx), ...
        'long',  labels_long, ...
        'short', labels_short );
end




