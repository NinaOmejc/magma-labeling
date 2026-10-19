function write_respiratory_artifact_hdf5(filename,state)
% WRITE_RESPIRATORY_ARTIFACT_HDF5 Mirror current annotations and ML exclusions.
% Original/native waveforms and physiological label masks are never rewritten.
% Match the recording-observation text convention, with expandable storage.
    state = respiratory_artifact_state(struct(),struct('respiratory_artifact_state',state));
    eligibility_path = '/qc/respiratory_artifacts/automatic_respiratory_training_eligible';
    replace_numeric(filename,eligibility_path,false); % Remain excluded if an update fails.
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
    replace_numeric(filename,'/breaths/artifact_intervals_idx',state.artifact_intervals_idx);
    for field = {'version','revision','timestamp','reviewer_role','annotation_source','scope','pending_reanalysis'}
        path = ['/breaths/artifact_annotation/' field{1}];
        value = state.(field{1});
        if ischar(value) || isstring(value)
            encoded = unicode2native(char(value),'UTF-8')';
            if isempty(encoded), encoded = uint8(0); end
            replace_numeric(filename,path,encoded);
            h5writeatt(filename,path,'encoding','UTF-8');
            h5writeatt(filename,path,'layout','zero_padded_columns');
        else
            replace_numeric(filename,path,value);
        end
    end
    if ~has_path(filename,'/meta/fs') || ~has_path(filename,'/time'), return; end
    fs = double(h5read(filename,'/meta/fs'));
    info = h5info(filename,'/time'); N = prod(info.Dataspace.Size);
    recording = struct('respiratory_artifact_state',state);
    if has_path(filename,'/observations/analysis_respiratory_artifact_revision')
        recording.analysis_respiratory_artifact_revision = double(h5read(filename,'/observations/analysis_respiratory_artifact_revision'));
    end
    qc = respiratory_artifact_qc(recording,N,fs);
    names = fieldnames(qc);
    for k = 1:numel(names)
        if strcmp(names{k},'automatic_respiratory_training_eligible'), continue; end
        replace_numeric(filename,['/qc/respiratory_artifacts/' names{k}],qc.(names{k}));
    end
    if ~has_path(filename,'/signals/ml/time')
        replace_numeric(filename,eligibility_path,qc.automatic_respiratory_training_eligible); return;
    end
    time = double(h5read(filename,'/signals/ml/time'));
    target_fs = double(h5read(filename,'/signals/ml/fs'));
    % Older ML exports used the same default FIR, but did not store its support.
    [p,q] = rat(target_fs/fs,1e-12); guard = 10*max(p,q)/p/fs;
    if p == q, guard = 0; end
    if has_path(filename,'/signals/ml/resampling_filter_half_support_sec')
        guard = double(h5read(filename,'/signals/ml/resampling_filter_half_support_sec'));
    end
    valid = respiratory_artifact_ml_validity(state,N,fs,time,guard);
    replace_numeric(filename,'/signals/ml/respiratory_artifact_valid_mask',valid);
    roles = read_hdf5_text(filename,'/signals/ml/channel_roles');
    data = h5read(filename,'/signals/ml/data');
    base = isfinite(data);
    if has_path(filename,'/signals/ml/source_valid_mask')
        base = base & logical(h5read(filename,'/signals/ml/source_valid_mask'));
    end
    respiratory = ismember(roles,{'lungs','diaph'});
    base(:,respiratory) = base(:,respiratory) & valid(:);
    replace_numeric(filename,'/signals/ml/channel_valid_mask',base);
    signal_valid = false(size(time)); spo2_valid = false(size(time));
    if any(respiratory), signal_valid = valid(:) & all(base(:,respiratory),2); end
    spo2 = strcmp(roles,'spo2');
    if any(spo2), spo2_valid = all(base(:,spo2),2); end
    labels = read_hdf5_text(filename,'/labels/names');
    layers = {'automatic','reviewed'};
    for k = 1:numel(layers)
        path = ['/labels/' layers{k} '/assessable_mask'];
        if ~has_path(filename,path), continue; end
        native = logical(h5read(filename,path));
        if strcmp(layers{k},'reviewed') && has_path(filename,'/labels/reviewed/coverage_mask')
            native = native & logical(h5read(filename,'/labels/reviewed/coverage_mask'));
        end
        training = ml_label_assessability(native,labels,time,fs,target_fs,signal_valid, ...
            qc.automatic_respiratory_training_eligible,spo2_valid);
        replace_numeric(filename,['/labels/' layers{k} '/ml_training_valid_mask'],training);
    end
    replace_numeric(filename,eligibility_path,qc.automatic_respiratory_training_eligible);
end

function exists = has_path(filename,path)
    fid = H5F.open(filename,'H5F_ACC_RDONLY','H5P_DEFAULT');
    cleanup = onCleanup(@() H5F.close(fid)); %#ok<NASGU>
    % H5L.exists requires the intermediate groups to exist too.
    parts = split(string(path),'/'); exists = true; prefix = '';
    for k = 2:numel(parts)
        prefix = [prefix '/' char(parts(k))]; %#ok<AGROW>
        if ~H5L.exists(fid,prefix,'H5P_DEFAULT'), exists = false; return; end
    end
end

function replace_numeric(filename,path,value)
    if has_path(filename,path)
        fid = H5F.open(filename,'H5F_ACC_RDWR','H5P_DEFAULT');
        cleanup = onCleanup(@() H5F.close(fid));
        H5L.delete(fid,path,'H5P_DEFAULT'); clear cleanup;
    end
    if isempty(value)
        h5create(filename,path,[1 1],'Datatype','uint8');
        h5write(filename,path,uint8(0)); h5writeatt(filename,path,'is_empty',uint8(1));
        return;
    end
    if islogical(value), value = uint8(value); end
    options = {};
    if numel(value) > 1024
        chunks = size(value); chunks(1) = min(chunks(1),4096);
        options = {'ChunkSize',chunks,'Deflate',4};
    end
    h5create(filename,path,size(value),'Datatype',class(value),options{:});
    h5write(filename,path,value);
end
