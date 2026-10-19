function [cycles,changed] = migrate_respiratory_artifacts(cycles,N,legacy_state)
% MIGRATE_RESPIRATORY_ARTIFACTS Canonicalize shared ranges without moving landmarks.
    if nargin < 2, N = []; end
    ranges = shared_respiratory_artifacts(cycles,N);
    if nargin >= 3 && ~isfield(cycles,'artifact_intervals_idx')
        ranges = shared_respiratory_artifacts(struct('artifact_intervals_idx', ...
            [ranges;shared_respiratory_artifacts(legacy_state,N)]),N);
    end
    changed = ~isfield(cycles,'artifact_intervals_idx') || ...
        ~isequaln(cycles.artifact_intervals_idx,ranges);
    cycles.artifact_intervals_idx = ranges;
    for name = {'lungs','diaph'}
        key = name{1};
        if isfield(cycles,key) && isstruct(cycles.(key)) && ...
                isfield(cycles.(key),'artifact_intervals_idx')
            cycles.(key) = rmfield(cycles.(key),'artifact_intervals_idx');
            changed = true;
        end
    end
end
