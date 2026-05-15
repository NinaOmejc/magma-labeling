function events = normalize_event_types_and_meta(events)
% normalize_event_types_and_meta
% Convert detector-specific event.type strings into the 8 canonical labels:
%   ShB, IrB, SlB, RaB, ReA, Des, Apn, Sig
% and extract common modifiers:
%   events(e).subtype  ('shallow'/'deep'/'desat'/'' )
%   events(e).desat    (true/false)
%   events(e).depth    ('shallow'/'deep'/'' )
%
% This keeps the sample mask on the main 8 label columns while retaining
% subtype detail in the event table/struct.
%
% Example conversions:
%   'slow_breathing_shallow_desat' -> type='SlB', subtype='shallow', desat=true
%   'rapid_deep'                   -> type='RaB', subtype='deep'
%   'rapid_desat'                  -> type='RaB', subtype='desat', desat=true
%   'apnea_desat'                  -> type='Apn', subtype='', desat=true
%   'desaturation'                 -> type='Des'
%   'sigh'                         -> type='Sig'
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

        events(e).subtype = map_subtype(s, base);
        events(e).desat = contains(s, 'desat');
        if contains(s, 'shallow')
            events(e).depth = 'shallow';
        elseif contains(s, 'deep')
            events(e).depth = 'deep';
        else
            events(e).depth = '';
        end

        events(e).type = base;
    end
end

% =========================================================
% Helper: map raw type string -> one of 8 canonical labels
% =========================================================
function base = map_type_to_base_label(s)
    % Shallow breathing
    if startsWith(s,'shallow_breathing') || strcmp(s,'shb') || contains(s,'shallowbreathing')
        base = 'ShB';
        return;
    end

    % Irregular breathing
    if startsWith(s,'irregular_breathing') || strcmp(s,'irb') || contains(s,'irregularbreathing')
        base = 'IrB';
        return;
    end

    % Slow breathing (bradypnea)
    if startsWith(s,'slow_breathing') || strcmp(s,'slb') || contains(s,'slowbreathing')
        base = 'SlB';
        return;
    end

    % Rapid breathing (tachypnea)
    if strcmp(s,'rapid') || strcmp(s,'rab') || strcmp(s,'rapid_breathing') || ...
            contains(s,'rapidbreathing') || contains(s,'tachypnea') || startsWith(s,'rapid_breathing') || ...
            startsWith(s,'rapid_')
        base = 'RaB';
        return;
    end

    % Respiratory asynchrony
    if startsWith(s,'respiratory_asynchrony') || strcmp(s,'rea') || contains(s,'asynchron')
        base = 'ReA';
        return;
    end

    % Desaturation
    if startsWith(s,'desaturation') || strcmp(s,'des') || contains(s,'hypoxia')
        base = 'Des';
        return;
    end

    % Apnea
    if startsWith(s,'apnea') || strcmp(s,'apn')
        base = 'Apn';
        return;
    end

    % Sigh
    if startsWith(s,'sigh') || strcmp(s,'sig')
        base = 'Sig';
        return;
    end

    % Fallback: keep original (but ideally you never hit this)
    base = s;
end

function subtype = map_subtype(s, base)
    subtype = '';

    switch base
        case {'RaB', 'SlB'}
            if contains(s, 'shallow')
                subtype = 'shallow';
            elseif contains(s, 'deep')
                subtype = 'deep';
            elseif strcmp(base, 'RaB') && contains(s, 'desat')
                subtype = 'desat';
            end
        otherwise
            subtype = '';
    end
end
