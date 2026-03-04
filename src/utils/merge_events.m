function sub_events = merge_events(event_lists, merge_gap_sec)
% merge_events
% Concatenate and merge overlapping/adjacent events WITHIN the same type.
% Different types are allowed to overlap and are never merged together.
%
% merge_gap_sec: optional; merge if curr.start_t <= last.end_t + merge_gap_sec
% default = 0 (overlap/abut only)

    if nargin < 2 || isempty(merge_gap_sec)
        merge_gap_sec = 0;
    end

    sub_events = empty_events();

    if isempty(event_lists), return; end

    % 1) Concatenate
    all_events = [];
    for i = 1:numel(event_lists)
        if ~isempty(event_lists{i})
            all_events = [all_events; event_lists{i}(:)];
        end
    end
    if isempty(all_events), return; end

    % 2) Sort by (type, start_t) so same-type events merge correctly
    types = {all_events.type}';
    starts = [all_events.start_t]';
    idx = (1:numel(all_events))';
    T = table(types, starts, idx, 'VariableNames', {'type','start_t','idx'});
    T = sortrows(T, {'type','start_t'});
    all_events = all_events(T.idx);

    % 3) Merge within same type
    sub_events = all_events(1);
    for i = 2:numel(all_events)
        curr = all_events(i);
        last = sub_events(end);

        same_type = strcmp(curr.type, last.type);
        close_enough = curr.start_t <= (last.end_t + merge_gap_sec);

        if same_type && close_enough
            sub_events(end).end_t   = max(last.end_t, curr.end_t);
            sub_events(end).end_idx = max(last.end_idx, curr.end_idx);

            % optional: if you later add meta, you can merge it here too
        else
            sub_events(end+1,1) = curr;
        end
    end
end
