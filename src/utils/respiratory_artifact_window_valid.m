function valid = respiratory_artifact_window_valid(ranges,end_t,window_sec,fs)
% RESPIRATORY_ARTIFACT_WINDOW_VALID Reject any overlap, including one sample.
    valid = true(size(end_t));
    first = floor((end_t-window_sec)*fs)+1;
    last = floor(end_t*fs)+1;
    for i = 1:size(ranges,1)
        valid = valid & ~(first <= ranges(i,2) & last >= ranges(i,1));
    end
end
