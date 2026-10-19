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
    state = struct('version','respiratory_artifacts_v2','subject',NaN,'measurement',NaN, ...
        'revision',0,'timestamp','','reviewer_role','','annotation_source','legacy_default', ...
        'scope','recording','pending_reanalysis',false, ...
        'artifact_intervals_idx',zeros(0,2),'evidence_intervals_idx',zeros(0,2), ...
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
    has_ranges = isfield(cycles,'artifact_intervals_idx');
    for name = {'lungs','diaph'}
        has_ranges = has_ranges || (isfield(cycles,name{1}) && ...
            isstruct(cycles.(name{1})) && isfield(cycles.(name{1}),'artifact_intervals_idx'));
    end
    if has_ranges
        ranges = shared_respiratory_artifacts(cycles,N);
        if ~isfield(cycles,'artifact_intervals_idx')
            ranges = shared_respiratory_artifacts(struct('artifact_intervals_idx', ...
                [ranges;shared_respiratory_artifacts(state,N)]),N);
        end
        evidence = ranges;
    else
        ranges = shared_respiratory_artifacts(state,N);
        evidence = ranges;
        fields = {'evidence_intervals_idx'};
        if ~isfield(state,'evidence_intervals_idx'), fields = {'lungs_evidence','diaph_evidence'}; end
        if ~isempty(ranges)
            for field = fields
                if isfield(state,field{1}), evidence = [evidence;state.(field{1})]; end %#ok<AGROW>
            end
        end
    end
    if N == 0
        extent = evidence(:);
        for name = {'lungs','diaph'}
            if ~isfield(cycles,name{1}), continue; end
            belt = cycles.(name{1});
            for field = {'peak_idx','trough_idx'}
                if isfield(belt,field{1}), extent = [extent;belt.(field{1})(:)]; end %#ok<AGROW>
            end
        end
        N = max([1;extent(isfinite(extent))]);
    end
    for name = {'lungs','diaph'}
        key = name{1};
        if ~isfield(cycles,key), continue; end
        belt = cycles.(key);
        masks = respiratory_artifact_masks(belt,N,config.fs,ranges);
        evidence = [evidence;masks.evidence_intervals_idx]; %#ok<AGROW>
    end
    state.version = 'respiratory_artifacts_v2'; state.scope = 'recording';
    state.artifact_intervals_idx = ranges;
    state.evidence_intervals_idx = normalize_respiratory_artifacts(evidence,N);
    % Read-only compatibility aliases: both belts always have the same ranges.
    state.lungs = ranges; state.diaph = ranges;
    state.lungs_evidence = state.evidence_intervals_idx;
    state.diaph_evidence = state.evidence_intervals_idx;
end
