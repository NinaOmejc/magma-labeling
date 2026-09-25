function save_recording_results(results, data_raw, data, config)
% SAVE_RECORDING_RESULTS Save one recording to MAT and optional HDF5 files.
%
% Inputs:
%   results  - Scalar authoritative result struct from build_recording_results.
%   data_raw - Nsample x Nchannel raw physiological signal matrix for HDF5.
%   data     - Nsample x Nchannel preprocessed signal matrix for HDF5.
%   config   - Result directory/filename, recording identity, and HDF5 settings.
% The MAT file stores each results field as a top-level variable; optional
% HDF5 export uses the validated recording-level exchange schema.

    log_message(config, 2, 'Saving MAT results...');
    save(fullfile(config.sub_results_path, config.sub_results_filename), ...
        '-struct', 'results');
    if get_config_value(config, 'HDF5', 'enabled', true)
        log_message(config, 2, 'Saving HDF5 results...');
        hdf5_suffix = get_config_value(config, 'HDF5', ...
            'filename_suffix', '_labels.h5');
        hdf5_filename = fullfile(config.sub_results_path, ...
            sprintf('Sub%d_M%d%s', config.subject, config.measure, hdf5_suffix));
        export_results_hdf5(hdf5_filename, results, data_raw, data);
    end
end
