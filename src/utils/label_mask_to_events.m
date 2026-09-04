function events = label_mask_to_events(mask, label_names, fs)
% LABEL_MASK_TO_EVENTS Perform the label mask to events operation.
%
% Syntax:
%   events = label_mask_to_events(mask, label_names, fs)
%
% Inputs:
%   mask - Logical state or selection mask.
%   label_names - Label identifier or label metadata.
%   fs - Sampling frequency in hertz.
%
% Outputs:
%   events - Event structure array.

    label_names = cellstr(string(label_names));
    if size(mask,2) ~= numel(label_names)
        error('MAGMA:Annotations:MaskAlignment', ...
            'mask columns must align with label_names.');
    end
    events = normalize_event_types_and_meta(empty_events());
    for i = 1:numel(label_names)
        column = logical(mask(:,i));
        d = diff([false; column; false]);
        starts = find(d == 1);
        ends = find(d == -1) - 1;
        for j = 1:numel(starts)
            event = struct( ...
                'type', label_names{i}, ...
                'start_idx', starts(j), ...
                'end_idx', ends(j), ...
                'start_t', (starts(j)-1)/fs, ...
                'end_t', ends(j)/fs, ...
                'duration', (ends(j)-starts(j)+1)/fs, ...
                'belt', '');
            events(end+1,1) = event; %#ok<AGROW>
        end
    end
end
