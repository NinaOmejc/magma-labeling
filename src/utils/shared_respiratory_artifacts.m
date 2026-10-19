function ranges = shared_respiratory_artifacts(source,N)
% SHARED_RESPIRATORY_ARTIFACTS Read authoritative ranges or union legacy belts.
% An existing shared field, including an empty one, takes precedence.

    ranges = zeros(0,2);
    if isfield(source,'artifact_intervals_idx')
        ranges = source.artifact_intervals_idx;
    else
        for name = {'lungs','diaph'}
            if ~isfield(source,name{1}), continue; end
            belt = source.(name{1});
            if isstruct(belt) && isfield(belt,'artifact_intervals_idx')
                ranges = [ranges;belt.artifact_intervals_idx]; %#ok<AGROW>
            elseif isnumeric(belt)
                ranges = [ranges;belt]; %#ok<AGROW> % Legacy compact state.
            end
        end
    end
    if nargin < 2 || isempty(N) || N == 0, N = max([1;ranges(:)]); end
    ranges = normalize_respiratory_artifacts(ranges,N);
end
