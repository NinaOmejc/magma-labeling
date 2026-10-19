function valid = ml_label_assessability(native,labels,time,fs,target_fs,artifact_valid,respiratory_current,spo2_valid)
% ML_LABEL_ASSESSABILITY Conservatively project native assessability to ML bins.
% Desaturation remains independent of respiratory artifacts and their revisions.
    N = size(native,1);
    if nargin < 8, spo2_valid = true(size(time)); end
    first = max(1,floor((time-0.5/target_fs)*fs)+1);
    last = min(N,ceil((time+0.5/target_fs)*fs)+1);
    valid = false(numel(time),numel(labels));
    for j = 1:numel(labels)
        bad = [0;cumsum(~logical(native(:,j)))];
        valid(:,j) = bad(last+1)-bad(first) == 0;
        if ~strcmp(labels{j},'desat')
            valid(:,j) = valid(:,j) & artifact_valid(:) & respiratory_current;
        else
            valid(:,j) = valid(:,j) & spo2_valid(:);
        end
    end
end
