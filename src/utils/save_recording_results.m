function results = save_recording_results(results, data_raw, data, config)
% SAVE_RECORDING_RESULTS Save one recording to MAT and optional HDF5 files.
%
% Inputs:
%   results  - Scalar authoritative result struct from build_recording_results.
%   data_raw - Nsample x Nchannel raw physiological signal matrix for HDF5.
%   data     - Nsample x Nchannel preprocessed signal matrix for HDF5.
%   config   - Result directory/filename, recording identity, and HDF5 settings.
% The MAT file stores one hierarchical results variable; optional
% HDF5 export uses the validated recording-level exchange schema.

    log_message(config, 2, 'Saving results...');
    if ~isfield(results,'config'), results.config = config; end
    results.subject = config.subject; results.measure = config.measure;
    results.recording_observations = recording_observation('load', config);
    if ~isfield(results, 'analysis_recording_observations')
        results.analysis_recording_observations = recording_observation('default', config);
    end
    results.respiratory_artifact_state = respiratory_artifact_checkpoint('load',config);
    if ~isfield(results,'analysis_respiratory_artifact_revision'), results.analysis_respiratory_artifact_revision = 0; end
    full_analysis = ~strcmp(execution_mode(config),'review') && isempty(resolve_selected_labels(config)) && ...
        ~get_config_value(config, 'LabelEdit', 'refresh_derived', false);
    if full_analysis && results.analysis_recording_observations.revision ~= results.recording_observations.revision
        error('MAGMA:Observation:RevisionChanged', 'Observation changed during analysis; rerun this recording.');
    end
    if full_analysis && results.analysis_respiratory_artifact_revision ~= results.respiratory_artifact_state.revision
        error('MAGMA:Respiration:ArtifactRevisionChanged','Feature annotations changed during analysis; rerun this recording.');
    end
    if full_analysis
        % These labels were computed at this revision; cache pending clears
        % only after every required output has been saved successfully.
        results.respiratory_artifact_state.pending_reanalysis = false;
    end
    results.respiratory_artifact_qc = respiratory_artifact_qc(results,size(data,1),config.fs);
    recording_results('save',fullfile(config.sub_results_path, ...
        config.sub_results_filename),results);
    if get_config_value(config, 'HDF5', 'enabled', true)
        hdf5_suffix = get_config_value(config, 'HDF5', ...
            'filename_suffix', '_results.h5');
        hdf5_filename = fullfile(config.sub_results_path, ...
            sprintf('Sub%d_M%d%s', config.subject, config.measure, hdf5_suffix));
        export_results_hdf5(hdf5_filename, results, data_raw, data);
    end
    if full_analysis
        recording_observation('complete', config, results.analysis_recording_observations.revision);
        results.respiratory_artifact_state = respiratory_artifact_checkpoint('complete',config,results.analysis_respiratory_artifact_revision);
    end
    results.recording_observations = recording_observation('load', config);
end
