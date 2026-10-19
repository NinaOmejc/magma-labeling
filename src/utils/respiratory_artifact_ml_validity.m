function valid = respiratory_artifact_ml_validity(state,N,fs,time,filter_half_support_sec)
% RESPIRATORY_ARTIFACT_ML_VALIDITY Exclude any FIR support touching an artifact.
    valid = true(size(time));
    if isfield(state,'annotation_known') && ~state.annotation_known
        valid(:) = false; return;
    end
    ranges = shared_respiratory_artifacts(state,N);
    for i = 1:size(ranges,1)
        first = (ranges(i,1)-1)/fs-filter_half_support_sec;
        last = (ranges(i,2)-1)/fs+filter_half_support_sec;
        tolerance = 10*eps(max(1,abs(last)));
        valid(time >= first-tolerance & time <= last+tolerance) = false;
    end
end
