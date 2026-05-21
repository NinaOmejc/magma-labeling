function events = normalize_event_types_and_meta(events)
% normalize_event_types_and_meta
% Convert detector-specific event.type strings into the 9 canonical labels:
%   shallowB, irregB, slowB, rapidB, asyncB, desat, apnea, sigh, CSR
% and extract common modifiers:
%   events(e).subtype  ('lungs'/'diaph'/'both' or modifier+belt composites)
%   events(e).desat    (true/false)
%   events(e).depth    ('shallow'/'deep'/'' )
%
% This keeps the sample mask on the main label columns while retaining
% subtype detail in the event table/struct.
%
% Example conversions:
%   'slow_breathing_shallow_desat' -> type='slowB', subtype='shallow', desat=true
%   'rapid_deep'                   -> type='rapidB', subtype='deep'
%   'rapid_desat'                  -> type='rapidB', subtype='desat', desat=true
%   'apnea_desat'                  -> type='apnea', subtype='', desat=true
%   'desaturation'                 -> type='desat'
%   'sigh'                         -> type='sigh'
%   'periodic_breathing_lungs'      -> type='CSR', subtype='lungs'
%
% Usage:
%   sub_events = merge_events({events_ShB,events_IrB,...});
%   sub_events = normalize_event_types_and_meta(sub_events);

    if isempty(events)
        return;
    end

    for e = 1:numel(events)

        % if ~isfield(events(e),'depth') || isempty(events(e).depth)
        %     events(e).depth = struct();
        % end

        raw_type = '';
        if isfield(events(e),'type') && ~isempty(events(e).type)
            raw_type = events(e).type;
        end

        % normalize string
        s = lower(strtrim(raw_type));
        s = strrep(s, ' ', '_');     % handle "Rapid Breathing" etc
        s = strrep(s, '-', '_');

        base = map_type_to_base_label(s);
        modifier = map_modifier(s, base);
        belt = map_belt(s);

        events(e).desat = contains(s, 'desat');
        if contains(s, 'shallow')
            events(e).depth = 'shallow';
        elseif contains(s, 'deep')
            events(e).depth = 'deep';
        else
            events(e).depth = '';
        end

        events(e).type = base;
        events(e).modifier = modifier;
        events(e).belt = belt;
    end

    events = merge_normalized_belt_events(events);
    for e = 1:numel(events)
        events(e).subtype = compose_subtype(events(e).modifier, events(e).belt);
    end
    events = rmfield(events, {'modifier', 'belt'});
end

% =========================================================
% Helper: map raw type string -> one of 9 canonical labels
% =========================================================
function base = map_type_to_base_label(s)
    % Shallow breathing
    if startsWith(s,'shallow_breathing') || any(strcmp(s, {'shb', 'shallowb'})) || ...
            startsWith(s, 'shb_') || startsWith(s, 'shallowb_') || contains(s,'shallowbreathing')
        base = 'shallowB';
        return;
    end

    % Irregular breathing
    if startsWith(s,'irregular_breathing') || any(strcmp(s, {'irb', 'irregb'})) || ...
            startsWith(s, 'irb_') || startsWith(s, 'irregb_') || contains(s,'irregularbreathing')
        base = 'irregB';
        return;
    end

    % Slow breathing (bradypnea)
    if startsWith(s,'slow_breathing') || any(strcmp(s, {'slb', 'slowb'})) || ...
            startsWith(s, 'slb_') || startsWith(s, 'slowb_') || contains(s,'slowbreathing')
        base = 'slowB';
        return;
    end

    % Rapid breathing (tachypnea)
    if strcmp(s,'rapid') || any(strcmp(s, {'rab', 'rapidb'})) || startsWith(s, 'rab_') || ...
            startsWith(s, 'rapidb_') || strcmp(s,'rapid_breathing') || ...
            contains(s,'rapidbreathing') || contains(s,'tachypnea') || startsWith(s,'rapid_breathing') || ...
            startsWith(s,'rapid_')
        base = 'rapidB';
        return;
    end

    % Respiratory asynchrony
    if startsWith(s,'respiratory_asynchrony') || any(strcmp(s, {'rea', 'asyncb'})) || ...
            startsWith(s, 'rea_') || startsWith(s, 'asyncb_') || contains(s,'asynchron')
        base = 'asyncB';
        return;
    end

    % Desaturation
    if startsWith(s,'desaturation') || any(strcmp(s, {'des', 'desat'})) || ...
            startsWith(s, 'des_') || startsWith(s, 'desat_') || contains(s,'hypoxia')
        base = 'desat';
        return;
    end

    % Apnea
    if startsWith(s,'apnea') || any(strcmp(s, {'apn', 'apnea'})) || startsWith(s, 'apn_')
        base = 'apnea';
        return;
    end

    % Sigh
    if startsWith(s,'sigh') || any(strcmp(s, {'sig', 'sigh'})) || startsWith(s, 'sig_')
        base = 'sigh';
        return;
    end

    % Cheyne-Stokes-like / periodic breathing
    if startsWith(s,'periodic_breathing') || startsWith(s,'cheyne_stokes') || ...
            strcmp(s,'csr') || startsWith(s, 'csr_') || strcmp(s,'csb') || startsWith(s, 'csb_') || ...
            contains(s,'periodicbreathing')
        base = 'CSR';
        return;
    end

    % Fallback: keep original (but ideally you never hit this)
    base = s;
end

function modifier = map_modifier(s, base)
    modifier = '';
    switch base
        case {'rapidB', 'slowB'}
            if contains(s, 'shallow')
                modifier = 'shallow';
            elseif contains(s, 'deep')
                modifier = 'deep';
            elseif strcmp(base, 'rapidB') && contains(s, 'desat')
                modifier = 'desat';
            end
    end
end

function belt = map_belt(s)
    belt = '';
    if contains(s, 'lungs')
        belt = 'lungs';
    elseif contains(s, 'diaph')
        belt = 'diaph';
    end
end

function subtype = compose_subtype(modifier, belt)
    subtype = '';
    if ~isempty(modifier) && ~isempty(belt)
        subtype = [modifier '_' belt];
    elseif ~isempty(modifier)
        subtype = modifier;
    elseif ~isempty(belt)
        subtype = belt;
    end
end

function events = merge_normalized_belt_events(events)
    if numel(events) <= 1
        return;
    end

    types = {events.type}';
    depths = {events.depth}';
    modifiers = {events.modifier}';
    desats = [events.desat]';
    starts = [events.start_t]';
    idx = (1:numel(events))';
    T = table(types, depths, modifiers, desats, starts, idx, ...
        'VariableNames', {'type', 'depth', 'modifier', 'desat', 'start_t', 'idx'});
    T = sortrows(T, {'type', 'depth', 'modifier', 'desat', 'start_t'});
    events = events(T.idx);

    out = events(1);
    for i = 2:numel(events)
        curr = events(i);
        last = out(end);

        same_type = strcmp(curr.type, last.type);
        same_depth = strcmp(curr.depth, last.depth);
        same_desat = isequal(curr.desat, last.desat);
        same_modifier = strcmp(curr.modifier, last.modifier);
        close_enough = curr.start_t <= last.end_t;

        if same_type && same_depth && same_desat && same_modifier && close_enough
            out(end).start_t = min(last.start_t, curr.start_t);
            out(end).end_t = max(last.end_t, curr.end_t);
            out(end).start_idx = min(last.start_idx, curr.start_idx);
            out(end).end_idx = max(last.end_idx, curr.end_idx);
            out(end).duration = out(end).end_t - out(end).start_t;
            out(end).belt = merge_belt_labels(last.belt, curr.belt);
        else
            out(end+1,1) = curr; %#ok<AGROW>
        end
    end

    events = out;
end

function belt = merge_belt_labels(a, b)
    if strcmp(a, b) || isempty(b)
        belt = a;
        return;
    end
    if isempty(a)
        belt = b;
        return;
    end
    belt = 'both';
end
