function write_respiratory_artifact_hdf5(filename,state)
% WRITE_RESPIRATORY_ARTIFACT_HDF5 Reversible UTF-8 metadata, without signal writes.
% Match the recording-observation text convention, with expandable storage.
    dataset = '/observations/respiratory_artifacts_json';
    fid = H5F.open(filename,'H5F_ACC_RDWR','H5P_DEFAULT');
    cleanup = onCleanup(@() H5F.close(fid));
    exists = H5L.exists(fid,'/observations','H5P_DEFAULT') && ...
        H5L.exists(fid,dataset,'H5P_DEFAULT');
    clear cleanup;
    old_size = 0;
    if exists
        info = h5info(filename,dataset); old_size = info.Dataspace.Size(1);
    else
        h5create(filename,dataset,[Inf 1],'Datatype','uint8','ChunkSize',[1024 1]);
    end
    bytes = unicode2native(jsonencode(state),'UTF-8')';
    bytes(end+1:max(old_size,numel(bytes)),1) = 0;
    h5write(filename,dataset,bytes,[1 1],[numel(bytes) 1]);
    h5writeatt(filename,dataset,'encoding','UTF-8');
    h5writeatt(filename,dataset,'layout','zero_padded_columns');
end
