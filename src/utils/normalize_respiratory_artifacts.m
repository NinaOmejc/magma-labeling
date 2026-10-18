function ranges = normalize_respiratory_artifacts(ranges,N)
% NORMALIZE_RESPIRATORY_ARTIFACTS Inclusive sample ranges; merge touching spans.
    if isempty(ranges), ranges = zeros(0,2); return; end
    if ~isnumeric(ranges) || ~isreal(ranges) || ~ismatrix(ranges) || size(ranges,2) ~= 2 || ...
            any(~isfinite(ranges(:))) || any(ranges(:) ~= round(ranges(:))) || ...
            ~isscalar(N) || ~isreal(N) || ~isfinite(N) || N < 1 || N ~= round(N)
        error('MAGMA:Respiration:InvalidArtifacts','Artifacts must be finite integer N-by-2 sample ranges.');
    end
    ranges = sort(max(1,min(N,double(ranges))),2);
    ranges = sortrows(ranges,1);
    merged = ranges(1,:);
    for i = 2:size(ranges,1)
        if ranges(i,1) <= merged(end,2)+1
            merged(end,2) = max(merged(end,2),ranges(i,2));
        else
            merged(end+1,:) = ranges(i,:); %#ok<AGROW>
        end
    end
    ranges = merged;
end
