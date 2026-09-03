function events = normalize_event_types_and_meta(raw_events, fs)
% normalize_event_types_and_meta
% Convert detector-specific event names to one of the eleven independent
% canonical labels and retain only explicit belt provenance.
%
% Final schema:
%   type, start_idx, end_idx, start_t, end_t, duration, belt
% where belt is '', 'lungs', 'diaph', or 'both'. Times are half-open:
% [start_t,end_t), while start_idx:end_idx are included samples. When fs is
% supplied, indices are authoritative and canonical times are recomputed.
% Overlapping events of the
% same canonical type are merged; overlapping different labels are kept.

    if nargin < 2
        fs = [];
    end

    events = empty_normalized_events();
    if isempty(raw_events)
        return;
    end

    events = repmat(normalized_template(), numel(raw_events), 1);
    for i = 1:numel(raw_events)
        raw_type = required_text_field(raw_events(i), 'type');
        key = normalize_key(raw_type);
        events(i).type = canonical_type(key);
        events(i).belt = belt_from_event(key, raw_events(i));
        events(i).start_idx = round(required_numeric_field(raw_events(i), 'start_idx'));
        events(i).end_idx = round(required_numeric_field(raw_events(i), 'end_idx'));
        if events(i).end_idx < events(i).start_idx
            error('MAGMA:Events:InvalidInterval', ...
                'Event "%s" has an end before its start.', raw_type);
        end
        if isempty(fs)
            events(i).start_t = required_numeric_field(raw_events(i), 'start_t');
            events(i).end_t = required_numeric_field(raw_events(i), 'end_t');
            if events(i).end_t < events(i).start_t
                error('MAGMA:Events:InvalidInterval', ...
                    'Event "%s" has an end before its start.', raw_type);
            end
            events(i).duration = events(i).end_t - events(i).start_t;
        else
            validate_fs(fs);
            events(i).start_t = (events(i).start_idx - 1) / fs;
            events(i).end_t = events(i).end_idx / fs;
            events(i).duration = ...
                (events(i).end_idx - events(i).start_idx + 1) / fs;
        end
    end

    events = merge_normalized_belt_events(events);
end

function template = normalized_template()
    template = struct( ...
        'type', '', ...
        'start_idx', 0, ...
        'end_idx', 0, ...
        'start_t', 0, ...
        'end_t', 0, ...
        'duration', 0, ...
        'belt', '');
end

function events = empty_normalized_events()
    template = normalized_template();
    events = template([]);
end

function key = normalize_key(value)
    key = lower(strtrim(char(string(value))));
    key = strrep(key, ' ', '_');
    key = strrep(key, '-', '_');
end

function type = canonical_type(key)
    if matches_label(key, {'shallow_breathing', 'shallowb', 'shb', 'shallowbreathing'})
        type = 'shallow';
    elseif matches_label(key, {'irregular_breathing', 'irregb', 'irb', 'irregularbreathing'})
        type = 'irregular';
    elseif matches_label(key, {'slow_breathing', 'slowb', 'slb', 'slowbreathing'})
        type = 'slow';
    elseif matches_label(key, {'rapid_breathing', 'rapid', 'rapidb', 'rab', 'rapidbreathing', 'tachypnea'})
        type = 'rapid';
    elseif matches_label(key, {'respiratory_asynchrony', 'asyncb', 'rea', 'respiratoryasynchrony'})
        type = 'async';
    elseif matches_label(key, {'desaturation', 'desat', 'des', 'hypoxia'})
        type = 'desat';
    elseif matches_label(key, {'apnea', 'apn'})
        type = 'apnea';
    elseif matches_label(key, {'sigh', 'sig'})
        type = 'sigh';
    elseif matches_label(key, {'periodic_breathing', 'csr', 'csb', ...
            'cheyne_stokes', 'periodicbreathing', ...
            'periodicbreathingcheynestokeslike'})
        type = 'csr';
    elseif matches_label(key, {'deep_breathing', 'deepb', 'deb', 'deepbreathing'})
        type = 'deep';
    elseif matches_label(key, {'thoracic_dominant_breathing', 'thordomb', ...
            'thoracicdominantbreathing'})
        type = 'thoracic';
    else
        error('MAGMA:Events:UnknownType', ...
            'Unrecognized detector event type "%s".', key);
    end
end

function validate_fs(fs)
    if ~isnumeric(fs) || ~isscalar(fs) || ~isfinite(fs) || fs <= 0
        error('MAGMA:Events:InvalidSamplingRate', ...
            'fs must be a finite positive numeric scalar.');
    end
end

function tf = matches_label(key, bases)
    tf = false;
    suffixes = {'', '_lungs', '_diaph', '_both'};
    for i = 1:numel(bases)
        for j = 1:numel(suffixes)
            if strcmp(key, [bases{i} suffixes{j}])
                tf = true;
                return;
            end
        end
    end
end

function belt = belt_from_event(key, event)
    belt = '';
    if endsWith(key, '_lungs')
        belt = 'lungs';
    elseif endsWith(key, '_diaph')
        belt = 'diaph';
    elseif endsWith(key, '_both')
        belt = 'both';
    elseif isfield(event, 'belt') && ~isempty(event.belt)
        incoming = lower(strtrim(char(string(event.belt))));
        if any(strcmp(incoming, {'lungs', 'diaph', 'both'}))
            belt = incoming;
        end
    end
end

function value = required_text_field(event, field)
    if ~isfield(event, field) || isempty(event.(field))
        error('MAGMA:Events:MissingField', 'Event is missing required field "%s".', field);
    end
    value = char(string(event.(field)));
end

function value = required_numeric_field(event, field)
    if ~isfield(event, field) || ~isnumeric(event.(field)) || ...
            ~isscalar(event.(field)) || ~isfinite(event.(field))
        error('MAGMA:Events:InvalidField', ...
            'Event field "%s" must be a finite numeric scalar.', field);
    end
    value = event.(field);
end

function events = merge_normalized_belt_events(events)
    if numel(events) <= 1
        return;
    end

    types = {events.type}';
    starts = [events.start_t]';
    order = (1:numel(events))';
    T = table(types, starts, order, 'VariableNames', {'type', 'start_t', 'order'});
    T = sortrows(T, {'type', 'start_t'});
    events = events(T.order);

    out = events(1);
    for i = 2:numel(events)
        current = events(i);
        previous = out(end);
        if strcmp(current.type, previous.type) && current.start_t <= previous.end_t
            out(end).start_idx = min(previous.start_idx, current.start_idx);
            out(end).end_idx = max(previous.end_idx, current.end_idx);
            out(end).start_t = min(previous.start_t, current.start_t);
            out(end).end_t = max(previous.end_t, current.end_t);
            out(end).duration = out(end).end_t - out(end).start_t;
            out(end).belt = merge_belt_labels(previous.belt, current.belt);
        else
            out(end+1, 1) = current; %#ok<AGROW>
        end
    end
    events = out;
end

function belt = merge_belt_labels(a, b)
    if strcmp(a, b) || isempty(b)
        belt = a;
    elseif isempty(a)
        belt = b;
    else
        belt = 'both';
    end
end
