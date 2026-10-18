function masks = respiratory_artifact_masks(belt,N,fs)
% RESPIRATORY_ARTIFACT_MASKS Derive validity without changing saved landmarks.
    ranges = zeros(0,2);
    if isfield(belt,'artifact_intervals_idx'), ranges = belt.artifact_intervals_idx; end
    ranges = normalize_respiratory_artifacts(ranges,N);
    bad = false(N,1);
    for i = 1:size(ranges,1), bad(ranges(i,1):ranges(i,2)) = true; end
    peaks = [];
    if isfield(belt,'peak_idx'), peaks = belt.peak_idx(:); end
    if isempty(peaks) && isfield(belt,'peak_t'), peaks = round(belt.peak_t(:)*fs)+1; end
    if isempty(ranges)
        masks = struct('sample_valid',true(N,1),'breath_valid',true(size(peaks)), ...
            'ibi_valid',true(max(0,numel(peaks)-1),1),'evidence_intervals_idx',zeros(0,2));
        return;
    end
    troughs = [];
    if isfield(belt,'trough_idx'), troughs = belt.trough_idx(:); end
    if isempty(troughs) && isfield(belt,'trough_t'), troughs = round(belt.trough_t(:)*fs)+1; end
    breath_valid = true(size(peaks)); ibi_valid = true(max(0,numel(peaks)-1),1);
    expanded = bad;
    cumulative = [0;cumsum(bad)];
    for i = 1:numel(peaks)
        first = peaks(i); last = peaks(i);
        if i > 1 && i-1 <= numel(troughs), first = troughs(i-1); end
        if i <= numel(troughs), last = troughs(i); end
        if ~isfinite(first) || ~isfinite(last), breath_valid(i) = false; continue; end
        first = max(1,min(N,round(first))); last = max(first,min(N,round(last)));
        breath_valid(i) = cumulative(last+1)-cumulative(first) == 0;
        if ~breath_valid(i), expanded(first:last) = true; end
        if i < numel(peaks)
            first = max(1,min(N,round(peaks(i)))); last = max(first,min(N,round(peaks(i+1))));
            ibi_valid(i) = cumulative(last+1)-cumulative(first) == 0;
            if ~ibi_valid(i), expanded(first:last) = true; end
        end
    end
    d = diff([false;expanded;false]);
    masks = struct('sample_valid',~bad,'breath_valid',breath_valid,'ibi_valid',ibi_valid, ...
        'evidence_intervals_idx',[find(d==1),find(d==-1)-1]);
end
