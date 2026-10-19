function state = respiratory_artifact_checkpoint(action,config,varargin)
% RESPIRATORY_ARTIFACT_CHECKPOINT Read authoritative cache revision and mirror it.
% Cache is the commit point. Results retain their analysis revision and complete
% historical reviews until a successful full analysis saves new outputs.
    stem = sprintf('Sub%d_M%d',config.subject,config.measure);
    folder = fullfile(config.path_results_out,stem);
    if isfield(config,'sub_results_path'), folder = config.sub_results_path; end
    cache_name = [stem '_features.mat']; result_name = [stem '_results.mat'];
    if isfield(config,'sub_features_filename'), cache_name = config.sub_features_filename; end
    if isfield(config,'sub_results_filename'), result_name = config.sub_results_filename; end
    cache_file = fullfile(folder,cache_name);
    defaults_config = config;
    if isfield(defaults_config,'respiratory_artifact_state'), defaults_config = rmfield(defaults_config,'respiratory_artifact_state'); end
    state = respiratory_artifact_state(struct(),defaults_config,0);
    cached = struct();
    if isfile(cache_file)
        cached = load(cache_file);
        if isfield(cached,'feature_cache_meta') && ...
                all(isfield(cached.feature_cache_meta,{'subject','measurement'})) && ...
                (cached.feature_cache_meta.subject ~= config.subject || ...
                 cached.feature_cache_meta.measurement ~= config.measure)
            error('MAGMA:Respiration:ArtifactIdentity','Artifact cache identity mismatch: %s',cache_file);
        end
        if isfield(cached,'respiratory_artifact_state')
            state = cached.respiratory_artifact_state;
            if state.subject ~= config.subject || state.measurement ~= config.measure
                error('MAGMA:Respiration:ArtifactIdentity','Artifact identity mismatch: %s',cache_file);
            end
        end
    else
        result_file = fullfile(folder,result_name);
        if isfile(result_file)
            cached = recording_results('existing',result_file,config);
            if ~isempty(fieldnames(cached)) && ...
                    (cached.subject ~= config.subject || cached.measure ~= config.measure)
                cached = struct(); % A copied config can still name another recording's result.
            end
            if isfield(cached,'respiratory_artifact_state'), state = cached.respiratory_artifact_state; end
        end
    end
    state_config = defaults_config; state_config.respiratory_artifact_state = state;
    cycles = struct();
    if isfield(cached,'resp_cycles'), cycles = cached.resp_cycles; end
    legacy = ~isfield(state,'artifact_intervals_idx') || ...
        (isfield(cached,'resp_cycles') && ~isfield(cycles,'artifact_intervals_idx'));
    state = respiratory_artifact_state(cycles,state_config);
    if legacy && ~isempty(state.artifact_intervals_idx), state.pending_reanalysis = true; end
    if strcmp(action,'load'), return; end
    if strcmp(action,'complete')
        if state.revision ~= varargin{1}
            error('MAGMA:Respiration:ArtifactRevisionChanged', ...
                'Respiratory features changed during analysis. Reopen and rerun this recording.');
        end
        if isempty(fieldnames(cached)) && isfile(cache_file), cached = load(cache_file); end
        state.pending_reanalysis = false;
        if isfield(cached,'resp_cycles')
            cached.resp_cycles = migrate_respiratory_artifacts(cached.resp_cycles,[],state);
            cached.resp_cycles.artifact_annotation = annotation_metadata(state);
            cached.respiratory_artifact_state = state;
        end
    elseif strcmp(action,'publish')
        if ~isempty(varargin)
            state_config.respiratory_artifact_state = varargin{1};
            state = respiratory_artifact_state(struct(),state_config);
        end
    else
        error('MAGMA:Respiration:ArtifactAction','Unknown artifact action: %s',action);
    end
    % Mirror current annotations; physiological labels and history stay unchanged.
    result_file = fullfile(folder,result_name);
    if isfile(result_file)
        previous = recording_results('existing',result_file,config);
        if ~isempty(fieldnames(previous))
            mirror = struct('respiratory_artifact_state',state);
            if isfield(previous,'resp_cycles')
                cycles = previous.resp_cycles;
                cycles.artifact_intervals_idx = state.artifact_intervals_idx;
                mirror.resp_cycles = migrate_respiratory_artifacts(cycles);
                mirror.resp_cycles.artifact_annotation = annotation_metadata(state);
            end
            context = previous; context.respiratory_artifact_state = state;
            N = size(previous.mask_automatic,1);
            mirror.respiratory_artifact_qc = respiratory_artifact_qc(context,N,config.fs);
            recording_results('update',result_file,mirror,previous);
        end
    end
    h5 = fullfile(folder,[stem get_config_value(config,'HDF5','filename_suffix','_results.h5')]);
    if isfile(h5)
        write_respiratory_artifact_hdf5(h5,state);
    end
    % Clear cache pending only after every enabled output mirror succeeds.
    if strcmp(action,'complete') && isfile(cache_file) && isfield(cached,'resp_cycles')
        atomic_save_mat(cache_file,cached);
    end
end

function metadata = annotation_metadata(state)
    metadata = rmfield(state,{'subject','measurement','artifact_intervals_idx','evidence_intervals_idx', ...
        'lungs','diaph','lungs_evidence','diaph_evidence'});
end
