addpath(genpath('src'));

subjects = [1];
measurements = [1 2];

for sub = subjects
    for measure = measurements
        % Load saved results
        matfile = ['D:\Projects\MAGMA\data_analysis\statistical_labeling\Sub' sub '_M' measure '\Sub' sub '_M' measure '_results.mat'];
        R = recording_results('load', matfile);
        
        % Use the original analysis configuration
        cfg = R.config;
        cfg.path_data_in = 'D:\Projects\MAGMA\raw_data';
        cfg.path_results_out = fileparts(fileparts(matfile));
        
        % Allow the raw-data loader to read an already analyzed recording
        cfg.execution.mode = 'analyze';
        cfg.overwrite_results = true;
        cfg.overwrite_features = false;
        cfg.plot_raw_data = false;
        cfg.detrend.do_plot = false;
        
        % Load physiological signals and reproduce preprocessing
        [data_raw, cfg, ok] = load_raw_data(cfg);
        assert(ok && ~isempty(data_raw));
        
        [data, cfg] = preprocess_data(data_raw, cfg);
        
        % HDF5 export settings
        R.config.HDF5.include_ml_signals = true;
        R.config.HDF5.ml_sampling_hz = 20;
        
        % Export
        h5file = fullfile(cfg.sub_results_path, ['Sub' sub '_M' measure '_results.h5']);
        export_results_hdf5(h5file, R, data_raw, data);
        
        % Inspect exported file
        h5info(h5file)
    end
end
