function ev = runs_to_events(cond, fs_like, min_sec, label)
% RUNS_TO_EVENTS Perform the runs to events operation.
%
% Syntax:
%   ev = runs_to_events(cond, fs_like, min_sec, label)
%
% Inputs:
%   cond - Input value `cond`.
%   fs_like - Input value `fs_like`.
%   min_sec - Duration or window length in seconds.
%   label - Label identifier or label metadata.
%
% Outputs:
%   ev - Event structure array.

    cond = cond(:) ~= 0;

    d = diff([false; cond; false]);
    st = find(d == 1);
    en = find(d == -1) - 1;

    ev = empty_events();

    for i = 1:numel(st)
        dur = (en(i) - st(i) + 1) / fs_like;

        if dur >= min_sec
            ev(end+1,1) = struct( ...
                'type', label, ...
                'start_idx', st(i), ...
                'end_idx', en(i), ...
                'start_t', (st(i)-1) / fs_like, ...
                'end_t',   en(i) / fs_like, ...
                'duration', dur );
        end
    end
end