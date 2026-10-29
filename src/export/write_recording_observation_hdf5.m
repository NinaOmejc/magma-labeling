function write_recording_observation_hdf5(filename, observation, analysis)
% WRITE_RECORDING_OBSERVATION_HDF5 Update compact metadata without rewriting signals.
% UTF-8 JSON uses the existing zero-padded text-column convention. Unlimited
% length allows reversible status/provenance changes without fixed string limits.
% Existing respiratory ML eligibility is refreshed from the current/analysis
% revisions; native signals, automatic labels and analysis snapshots stay intact.
    dataset = '/observations/recording_json';
    fid = H5F.open(filename, 'H5F_ACC_RDWR', 'H5P_DEFAULT');
    cleanup = onCleanup(@() H5F.close(fid));
    exists = H5L.exists(fid, '/observations', 'H5P_DEFAULT') && ...
        H5L.exists(fid, dataset, 'H5P_DEFAULT');
    clear cleanup;
    old_size = 0;
    if exists
        info = h5info(filename, dataset);
        old_size = info.Dataspace.Size(1);
        if nargin < 3
            saved = read_hdf5_text(filename, dataset);
            saved = jsondecode(saved{1});
            analysis = saved.analysis;
        end
    elseif nargin < 3
        analysis = [];
    end
    stale = isempty(analysis) || analysis.revision ~= observation.revision;
    payload = struct('current', observation, 'analysis', analysis, ...
        'derived_results_pending_reanalysis', observation.pending_reanalysis || stale);
    bytes = unicode2native(jsonencode(payload), 'UTF-8')';
    bytes(end+1:max(old_size, numel(bytes)), 1) = 0;
    if ~exists
        h5create(filename, dataset, [Inf 1], 'Datatype', 'uint8', 'ChunkSize', [1024 1]);
    end
    h5write(filename, dataset, bytes, [1 1], [numel(bytes) 1]);
    h5writeatt(filename, dataset, 'encoding', 'UTF-8');
    fid = H5F.open(filename, 'H5F_ACC_RDONLY', 'H5P_DEFAULT');
    cleanup = onCleanup(@() H5F.close(fid));
    has_artifacts = H5L.exists(fid, '/observations/respiratory_artifacts_json', 'H5P_DEFAULT');
    clear cleanup;
    if has_artifacts
        text = read_hdf5_text(filename, '/observations/respiratory_artifacts_json');
        write_respiratory_artifact_hdf5(filename, jsondecode(text{1}));
    end
end
