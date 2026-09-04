function summary = compute_recording_label_burden( ...
    mask, label_names, label_available, events, fs, assessable_mask)
% COMPUTE_RECORDING_LABEL_BURDEN Compute recording label burden.
%
% Syntax:
%   summary = compute_recording_label_burden(mask, label_names, label_available, events, fs, assessable_mask)
%
% Inputs:
%   mask - Logical state or selection mask.
%   label_names - Label identifier or label metadata.
%   label_available - Label identifier or label metadata.
%   events - Event structure data.
%   fs - Sampling frequency in hertz.
%   assessable_mask - Logical state or selection mask.
%
% Outputs:
%   summary - Computed summary or metadata structure.

    label_names = cellstr(string(label_names));
    label_available = logical(label_available(:)');
    if size(mask, 2) ~= numel(label_names) || ...
            numel(label_available) ~= numel(label_names)
        error('MAGMA:Burden:LabelAlignment', ...
            'mask, label_names, and label_available must align.');
    end
    if nargin < 6 || isempty(assessable_mask)
        assessable_mask = repmat(label_available, size(mask, 1), 1);
    end
    if ~isequal(size(assessable_mask), size(mask))
        error('MAGMA:Burden:AssessableMaskSize', ...
            'assessable_mask must have the same size as mask.');
    end
    assessable_mask = logical(assessable_mask);

    summary = struct();
    summary.version = 'recording_label_burden_v1';
    summary.recording_duration_sec = size(mask, 1) / fs;
    summary.by_label = struct();

    for i = 1:numel(label_names)
        name = label_names{i};
        available = label_available(i) && any(assessable_mask(:, i));
        entry = struct('available', available, 'duration_sec', NaN, ...
            'fraction', NaN, 'event_count', NaN, ...
            'assessable_duration_sec', NaN);
        if available
            valid = assessable_mask(:, i);
            labeled = logical(mask(:, i)) & valid;
            entry.duration_sec = nnz(labeled) / fs;
            entry.assessable_duration_sec = nnz(valid) / fs;
            entry.fraction = nnz(labeled) / nnz(valid);
            entry.event_count = count_events(events, name);
        end
        summary.by_label.(name) = entry;
    end

    sigh = summary.by_label.sigh;
    summary.sigh_count = sigh.event_count;
    summary.sighs_per_15_min = NaN;
    if sigh.available && sigh.assessable_duration_sec > 0
        summary.sighs_per_15_min = ...
            sigh.event_count / (sigh.assessable_duration_sec / (15 * 60));
    end
end

function count = count_events(events, label)
% COUNT_EVENTS Perform the count events operation.
%
% Syntax:
%   count = count_events(events, label)
%
% Inputs:
%   events - Event structure data.
%   label - Label identifier or label metadata.
%
% Outputs:
%   count - Computed index or count value.

    count = 0;
    if ~isempty(events) && isfield(events, 'type')
        count = nnz(strcmp({events.type}, label));
    end
end
