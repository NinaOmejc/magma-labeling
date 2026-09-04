function save_recording_results(results, data_raw, data, config)
% SAVE_RECORDING_RESULTS Save one recording to MAT and optional HDF5 files.

    save(fullfile(config.sub_results_path, config.sub_results_filename), ...
        '-struct', 'results');
    if get_config_value(config, 'HDF5', 'enabled', true)
        hdf5_suffix = get_config_value(config, 'HDF5', ...
            'filename_suffix', '_labels.h5');
        hdf5_filename = fullfile(config.sub_results_path, ...
            sprintf('Sub%d_M%d%s', config.subject, config.measure, hdf5_suffix));
        export_results_hdf5(hdf5_filename, results, data_raw, data);
    end
end
