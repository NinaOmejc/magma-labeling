function state = respiratory_artifact_state(cycles,config,N)
% RESPIRATORY_ARTIFACT_STATE Compact current feature annotation and revision.
    if nargin < 3
        N = 0;
        for name = {'lungs','diaph'}
            if isfield(cycles,name{1}) && isfield(cycles.(name{1}),'x0')
                N = max(N,numel(cycles.(name{1}).x0));
            end
        end
    end
    state = struct('version','respiratory_artifacts_v1','subject',NaN,'measurement',NaN, ...
        'revision',0,'timestamp','','reviewer_role','','annotation_source','legacy_default', ...
        'scope','recording_per_belt','pending_reanalysis',false, ...
        'lungs',zeros(0,2),'diaph',zeros(0,2), ...
        'lungs_evidence',zeros(0,2),'diaph_evidence',zeros(0,2));
    if isfield(config,'subject'), state.subject = config.subject; end
    if isfield(config,'measure'), state.measurement = config.measure; end
    if isfield(config,'respiratory_artifact_state'), state = config.respiratory_artifact_state; end
    if isfield(cycles,'artifact_annotation')
        meta = cycles.artifact_annotation;
        for field = {'revision','timestamp','reviewer_role','annotation_source','pending_reanalysis'}
            if isfield(meta,field{1}), state.(field{1}) = meta.(field{1}); end
        end
    end
    for name = {'lungs','diaph'}
        key = name{1};
        if ~isfield(cycles,key), continue; end
        belt = cycles.(key);
        if isfield(belt,'artifact_intervals_idx')
            state.(key) = normalize_respiratory_artifacts(belt.artifact_intervals_idx,N);
        else
            state.(key) = zeros(0,2);
        end
        masks = respiratory_artifact_masks(belt,N,config.fs);
        state.([key '_evidence']) = masks.evidence_intervals_idx;
    end
end
