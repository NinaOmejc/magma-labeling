function events = normalize_event_types_and_meta(raw_events, fs)
% NORMALIZE_EVENT_TYPES_AND_META Normalize event types and meta.
%
% Syntax:
%   events = normalize_event_types_and_meta(raw_events, fs)
%
% Inputs:
%   raw_events - Event structure data.
%   fs - Sampling frequency in hertz.
%
% Outputs:
%   events - Event structure array.

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

    events = merge_normalized_belt_events(events, fs);
end

function template = normalized_template()
% NORMALIZED_TEMPLATE Perform the normalized template operation.
%
% Syntax:
%   template = normalized_template()
%
% Outputs:
%   template - Computed output value `template`.

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
% EMPTY_NORMALIZED_EVENTS Create an empty normalized events value.
%
% Syntax:
%   events = empty_normalized_events()
%
% Outputs:
%   events - Event structure array.

    template = normalized_template();
    events = template([]);
end

function key = normalize_key(value)
% NORMALIZE_KEY Normalize key.
%
% Syntax:
%   key = normalize_key(value)
%
% Inputs:
%   value - Input value `value`.
%
% Outputs:
%   key - Computed output value `key`.

    key = lower(strtrim(char(string(value))));
    key = strrep(key, ' ', '_');
    key = strrep(key, '-', '_');
end

function type = canonical_type(key)
% CANONICAL_TYPE Perform the canonical type operation.
%
% Syntax:
%   type = canonical_type(key)
%
% Inputs:
%   key - Input value `key`.
%
% Outputs:
%   type - Computed output value `type`.

    if matches_label(key, {'shallow', 'shallow_breathing', 'shallowb', 'shb', 'shallowbreathing'})
        type = 'shallow';
    elseif matches_label(key, {'irregular', 'irregular_breathing', 'irregb', 'irb', 'irregularbreathing'})
        type = 'irregular';
    elseif matches_label(key, {'slow', 'slow_breathing', 'slowb', 'slb', 'slowbreathing'})
        type = 'slow';
    elseif matches_label(key, {'rapid_breathing', 'rapid', 'rapidb', 'rab', 'rapidbreathing', 'tachypnea'})
        type = 'rapid';
    elseif matches_label(key, {'async', 'respiratory_asynchrony', 'asyncb', 'rea', 'respiratoryasynchrony'})
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
    elseif matches_label(key, {'deep', 'deep_breathing', 'deepb', 'deb', 'deepbreathing'})
        type = 'deep';
    elseif matches_label(key, {'thoracic', 'thoracic_dominant_breathing', 'thordomb', ...
            'thoracicdominantbreathing'})
        type = 'thoracic';
    else
        error('MAGMA:Events:UnknownType', ...
            'Unrecognized detector event type "%s".', key);
    end
end

function validate_fs(fs)
% VALIDATE_FS Validate fs.
%
% Syntax:
%   validate_fs(fs)
%
% Inputs:
%   fs - Sampling frequency in hertz.

    if ~isnumeric(fs) || ~isscalar(fs) || ~isfinite(fs) || fs <= 0
        error('MAGMA:Events:InvalidSamplingRate', ...
            'fs must be a finite positive numeric scalar.');
    end
end

function tf = matches_label(key, bases)
% MATCHES_LABEL Perform the matches label operation.
%
% Syntax:
%   tf = matches_label(key, bases)
%
% Inputs:
%   key - Input value `key`.
%   bases - Input value `bases`.
%
% Outputs:
%   tf - Computed output value `tf`.

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
% BELT_FROM_EVENT Perform the belt from event operation.
%
% Syntax:
%   belt = belt_from_event(key, event)
%
% Inputs:
%   key - Input value `key`.
%   event - Event structure data.
%
% Outputs:
%   belt - Updated respiratory-cycle or belt structure.

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
% REQUIRED_TEXT_FIELD Perform the required text field operation.
%
% Syntax:
%   value = required_text_field(event, field)
%
% Inputs:
%   event - Event structure data.
%   field - Input value `field`.
%
% Outputs:
%   value - Computed numeric value.

    if ~isfield(event, field) || isempty(event.(field))
        error('MAGMA:Events:MissingField', 'Event is missing required field "%s".', field);
    end
    value = char(string(event.(field)));
end

function value = required_numeric_field(event, field)
% REQUIRED_NUMERIC_FIELD Perform the required numeric field operation.
%
% Syntax:
%   value = required_numeric_field(event, field)
%
% Inputs:
%   event - Event structure data.
%   field - Input value `field`.
%
% Outputs:
%   value - Computed numeric value.

    if ~isfield(event, field) || ~isnumeric(event.(field)) || ...
            ~isscalar(event.(field)) || ~isfinite(event.(field))
        error('MAGMA:Events:InvalidField', ...
            'Event field "%s" must be a finite numeric scalar.', field);
    end
    value = event.(field);
end

function events = merge_normalized_belt_events(events, fs)
% MERGE_NORMALIZED_BELT_EVENTS Merge normalized belt events.
%
% Syntax:
%   events = merge_normalized_belt_events(events, fs)
%
% Inputs:
%   events - Event structure data.
%   fs - Sampling frequency in hertz.
%
% Outputs:
%   events - Event structure array.

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
            if isempty(fs)
                out(end).start_t = min(previous.start_t, current.start_t);
                out(end).end_t = max(previous.end_t, current.end_t);
                out(end).duration = out(end).end_t - out(end).start_t;
            else
                out(end).start_t = (out(end).start_idx - 1) / fs;
                out(end).end_t = out(end).end_idx / fs;
                out(end).duration = ...
                    (out(end).end_idx - out(end).start_idx + 1) / fs;
            end
            out(end).belt = merge_belt_labels(previous.belt, current.belt);
        else
            out(end+1, 1) = current; %#ok<AGROW>
        end
    end
    events = out;
end

function belt = merge_belt_labels(a, b)
% MERGE_BELT_LABELS Merge belt labels.
%
% Syntax:
%   belt = merge_belt_labels(a, b)
%
% Inputs:
%   a - Input value `a`.
%   b - Respiratory-cycle or belt-evidence structure.
%
% Outputs:
%   belt - Updated respiratory-cycle or belt structure.

    if strcmp(a, b) || isempty(b)
        belt = a;
    elseif isempty(a)
        belt = b;
    else
        belt = 'both';
    end
end
