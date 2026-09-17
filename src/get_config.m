function config = get_config()
% GET_CONFIG Define routine user settings on top of complete MAGMA defaults.

    config = get_config_defaults();

    % INPUT / OUTPUT
    config.path_data_in = 'D:\Projects\MAGMA\raw_data';
    config.path_results_out = 'D:\Projects\MAGMA\data_analysis\statistical_labeling';
    config.fs = 200;
    config.data_columns = {'ECG1', 'ECG2', 'SpO₂', 'Resp-Lungs', 'Blood Pressure', 'Resp-Diaphragm'};
    config.input_filename_pattern = 'ECG1_ECG2_SpO2_RespL_BP_RespD_fs200_Sub{subject}_Pom{measure}_DeTr_Norm.dat';

    % RECORDINGS
    config.subjects = 1;
    config.remove_subjects = [3 30 91];
    config.measurements = [1 2];
    config.subjects(ismember(config.subjects, config.remove_subjects)) = [];

    % EXECUTION
    config.overwrite_results = true;
    config.overwrite_features = false;
    config.make_figs_visible = 'on';

    % OPTIONAL PREPROCESSING
    config.detrend.method = 'none';

    % RESPIRATORY REPRESENTATION
    config.resp.amp_method = 'expiratory';
    config.resp.manual_control = true;

    % PRIMARY METHODS
    config.sigh.method = 'rolling_median_2x';
    config.periodic.primary_method = 'eami';
    config.async.primary_method = 'wavelet_phase_offset';
    config.async.compare_methods = true;

    % MANUAL REVIEW
    config.sigh.manual_control = false;
    config.LabelEdit.manual_control = false;
    config.LabelEdit.apply_saved_edits = false;
    config.LabelEdit.save_edits = true;
    config.LabelEdit.start_from = 'automatic';
    config.LabelEdit.reviewer_role = 'researcher';

    % Advanced scientific thresholds and processing defaults are defined in get_config_defaults.m.
end
