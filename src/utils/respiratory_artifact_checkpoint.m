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
        names = who('-file',cache_file);
        if ismember('respiratory_artifact_state',names)
            saved = load(cache_file,'respiratory_artifact_state','feature_cache_meta');
            if isfield(saved,'feature_cache_meta') && ...
                    (saved.feature_cache_meta.subject ~= config.subject || ...
                     saved.feature_cache_meta.measurement ~= config.measure)
                error('MAGMA:Respiration:ArtifactIdentity','Artifact cache identity mismatch: %s',cache_file);
            end
            state = saved.respiratory_artifact_state;
            if state.subject ~= config.subject || state.measurement ~= config.measure
                error('MAGMA:Respiration:ArtifactIdentity','Artifact identity mismatch: %s',cache_file);
            end
        elseif ~strcmp(action,'load')
            cached = load(cache_file);
            state = respiratory_artifact_state(cached.resp_cycles,config);
        end
    end
    if strcmp(action,'load'), return; end
    if strcmp(action,'complete')
        if state.revision ~= varargin{1}
            error('MAGMA:Respiration:ArtifactRevisionChanged', ...
                'Respiratory features changed during analysis. Reopen and rerun this recording.');
        end
        if isempty(fieldnames(cached)) && isfile(cache_file), cached = load(cache_file); end
        state.pending_reanalysis = false;
        if isfield(cached,'resp_cycles')
            cached.resp_cycles.artifact_annotation = annotation_metadata(state);
            cached.respiratory_artifact_state = state;
        end
    elseif strcmp(action,'publish')
        if ~isempty(varargin), state = varargin{1}; end
    else
        error('MAGMA:Respiration:ArtifactAction','Unknown artifact action: %s',action);
    end
    % Only compact current metadata changes here: no labels or historical edits.
    result_file = fullfile(folder,result_name);
    if isfile(result_file)
        mirror = struct('respiratory_artifact_state',state);
        save(result_file,'-struct','mirror','-append');
    end
    h5 = fullfile(folder,[stem get_config_value(config,'HDF5','filename_suffix','_results.h5')]);
    if isfile(h5)
        write_respiratory_artifact_hdf5(h5,state);
    end
    % Clear cache pending only after every enabled output mirror succeeds.
    if strcmp(action,'complete') && isfield(cached,'resp_cycles')
        atomic_save_mat(cache_file,cached);
    end
end

function metadata = annotation_metadata(state)
    metadata = rmfield(state,{'subject','measurement','lungs','diaph','lungs_evidence','diaph_evidence'});
end
