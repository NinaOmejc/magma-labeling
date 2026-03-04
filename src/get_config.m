function config = get_config()

    %---- GENERAL SETTINGS ----
    config = struct;
    config.path_data_in = 'D:\Projects\MAGMA\MAGMA-labeling\example_data';
    config.path_results_out = 'D:\Projects\MAGMA\MAGMA-labeling\results';
    config.fs = 200;  
    config.data_columns = {'ECG1', 'ECG2', 'SpO₂', 'Resp-Lungs', 'Blood Pressure', 'Resp-Diaphragm'};
    config.labels = get_labels();
    config.plot_raw_data = true;
    config.plot_raw_data_xrange = [1, 10]; % in sec
    config.save_plots = true;
    config.plot_format     = 'png';      % future-proof
    config.plot_dpi        = 150;        % resolution
    config.make_figs_visible = 'off';

    %---- BASELINE SETTINGS ----
    config.baseline_sec = 60;

    %---- RESPIRATION / BREATHING AMPLITUDE EXTRACTION SETTINGS ----
    config.resp.min_peak_dist_sec = 0.8;   % Peak selection; min time between breaths (tune if needed)
    config.resp.min_peak_prom     = 0.2;   % Peak selection; key knob: increase to reduce extra peaks
    config.resp.min_num_peaks     = 3;    
    config.resp.smooth_sec       = 0.25;   % Pre-processing; light smoothing (seconds); set 0 to disable
    config.resp.trough_method = 'min';     % Trough selection; 'prctile' (robust) or 'min'
    config.resp.trough_prct   = 5;         % Trough selection; 5th percentile trough
    config.resp.do_plot         = true;
    
    %---- SPO2 / DESATURATION FEATURE EXTRACTION
    config.spo2.spo2_floor  = 90;   % absolute threshold (%)
    config.spo2.drop_thr    = 3;    % relative drop threshold (% points)
    config.spo2.min_dur_sec = 10;   % episode duration (seconds)

    %---- GENERAL DETECTION SETTINGS
    config.grid_step_sec = 1;      % evaluation grid for "state" labels

    %---- LABEL 1 - ShB - DETECTION SETTINGS 
    config.ShB = struct();
    config.ShB.analysis_win_sec = 60;   % "60s analysis windows"
    config.ShB.amp_ratio_low    = 0.20;
    config.ShB.amp_ratio_high   = 0.35;
    config.ShB.min_dur_sec       = 30;
    config.ShB.exclude_desat     = true;
    config.ShB.do_plot           = true;

    %---- LABEL 2 - IrB - DETECTION SETTINGS 
    config.IrB = struct();
    config.IrB.analysis_win_sec = 60;
    config.IrB.cov_thr   = 0.3;
    config.IrB.rmssd_thr = 0.5;
    config.IrB.min_dur_sec = 30;
    config.IrB.pause_thr_sec = 10;
    config.IrB.do_plot       = true;

    %---- LABEL 3 - SlB - DETECTION SETTINGS 
    config.SlB = struct();
    config.SlB.analysis_win_sec = 60;     % rolling analysis window (30–60 s allowed)
    config.SlB.rr_thr_bpm       = 10;     % mean RR <= 10 bpm
    config.SlB.min_dur_sec      = 30;     % sustained >= 30 s
    config.SlB.classify_depth   = true;   % Depth classification (slow + shallow vs slow + deep)
    config.SlB.shallow_lo_ratio = 0.20;   % 20% of baseline (Shallow amplitude band (same logic as ShB))
    config.SlB.shallow_hi_ratio = 0.35;   % 35% of baseline (Shallow amplitude band (same logic as ShB))
    config.SlB.mark_desat        = true;  % Desaturation logic (append "_desat" if overlap)
    config.SlB.desat_delay_sec   = 20;    % Desaturation logic (allow SpO2 delay (lag buffer))
    config.SlB.do_plot          = true;

    %---- LABEL 4: RaB 
    config.RaB = struct();
    config.RaB.analysis_win_sec = 60;
    config.RaB.rr_thr_bpm       = 20;    % mean RR >= 20 bpm
    config.RaB.min_dur_sec      = 30;    % sustained >= 30 s
    config.RaB.classify_depth   = true; % Depth classification (fast+deep vs fast+shallow) ----
    config.RaB.shallow_lo_ratio = 0.20;  % 20% of baseline (Same amplitude band logic as ShB)
    config.RaB.shallow_hi_ratio = 0.35;  % 35% of baseline (Same amplitude band logic as ShB)
    config.RaB.mark_desat      = true;   % Desaturation association ; append "_desat" if overlapping
    config.RaB.desat_delay_sec = 20;     % Desaturation association ; allow SpO2 delay (lag buffer)
    config.RaB.do_plot         = true;

    %---- LABEL 5: Respiratory Asynchrony
    config.ReA = struct();
    config.ReA.do_plot          = true;

    %---- LABEL 6: SpO2 desaturation
    config.Des = struct();
    config.Des.do_plot = true;

    %---- LABEL 7: Apnea
    config.Anp = struct();
    config.Apn.analysis_win_sec = 30;    % rolling window for amplitude ratio estimate
    config.Apn.amp_ratio_thr    = 0.10;  % <=10% of baseline in BOTH belts
    config.Apn.min_dur_sec      = 10;    % >=10 s
    config.Apn.mark_desat        = true;     % append "_desat" if associated
    config.Apn.desat_lag_sec    = 45;       % look for desat within 30–60 s after apnea
    config.Apn.desat_pad_sec    = 0;        % optional extra expansion of desat events
    config.Apn.do_plot = true;

    %---- LABEL 8: Sigh
    config.Sig = struct();
    config.Sig.prev_win_sec     = 60;
    config.Sig.amp_ratio_thr    = 1.5;
    config.Sig.min_prev_breaths = 3;
    config.Sig.use_either_belt  = true;
    config.Sig.freq_win_sec       = 1800; % optional frequency summary
    config.Sig.freq_thr_per_30min = 7; % optional frequency summary
    config.Sig.do_plot = true;


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




