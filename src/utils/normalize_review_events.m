function events = normalize_review_events(raw_events, fs)
% NORMALIZE_REVIEW_EVENTS Keep each reviewed sigh identity, including touching breaths.
% Other labels retain their ordinary interval normalization. A point sigh uses
% start_idx=end_idx at its peak; start_t is the peak timestamp, and its one-
% sample duration exists only for compatibility with the MAT/HDF5 event schema.
    if nargin < 2, fs = []; end
    events = normalize_event_types_and_meta(empty_events(), fs);
    if iscell(raw_events)
        for i = 1:numel(raw_events)
            events = [events; normalize_review_events(raw_events{i}, fs)]; %#ok<AGROW>
        end
        raw_events = events;
    end
    if isempty(raw_events), return; end
    types = canonicalize_label_names({raw_events.type});
    sigh = strcmp(types, 'sigh');
    events = normalize_event_types_and_meta(raw_events(~sigh), fs);
    indices = find(sigh);
    for i = reshape(indices, 1, [])
        % Normalize singly: the interval merger must never join distinct sighs.
        events = [events; normalize_event_types_and_meta(raw_events(i), fs)]; %#ok<AGROW>
    end
    if isempty(events), return; end
    T = table(string({events.type})', [events.start_idx]', [events.end_idx]', ...
        (1:numel(events))', 'VariableNames', {'type','first','last','index'});
    T = sortrows(T, {'type','first','last'});
    events = events(T.index);
    % The same peak is one sigh even if it is supplied by both panels/layers.
    keep = true(numel(events), 1);
    last_sigh = 0;
    for i = 1:numel(events)
        if ~strcmp(events(i).type, 'sigh'), continue; end
        if last_sigh > 0 && events(i).start_idx == events(last_sigh).start_idx && ...
                events(i).end_idx == events(last_sigh).end_idx
            sources = {events(i).belt, events(last_sigh).belt};
            sources = unique(sources(~cellfun(@isempty, sources)));
            if numel(sources) > 1, events(last_sigh).belt = 'both';
            elseif numel(sources) == 1, events(last_sigh).belt = sources{1}; end
            keep(i) = false;
        else
            last_sigh = i;
        end
    end
    events = events(keep);
    events = events(:);
end
