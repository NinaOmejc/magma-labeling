function [config, input_config] = resolve_signal_channels(config)
% resolve_signal_channels
% Map user-provided data column names onto the signal roles used by detectors.

    if ~isfield(config, 'data_columns') || isempty(config.data_columns)
        error('config.data_columns must list the input data columns.');
    end

    names = cellstr(string(config.data_columns));

    channels = struct();
    channels.data_columns = names;
    channels.spo2_idx = [];
    channels.spo2_name = '';
    channels.lungs_idx = [];
    channels.lungs_name = '';
    channels.lungs_source = '';
    channels.diaph_idx = [];
    channels.diaph_name = '';
    channels.diaph_source = '';

    generic_idx = [];
    generic_name = {};

    for i = 1:numel(names)
        raw_name = names{i};
        key = normalized_channel_key(raw_name);

        if isempty(channels.spo2_idx) && is_spo2_name(key)
            channels.spo2_idx = i;
            channels.spo2_name = raw_name;
        elseif isempty(channels.lungs_idx) && is_lungs_name(key)
            channels.lungs_idx = i;
            channels.lungs_name = raw_name;
            channels.lungs_source = 'lungs';
        elseif isempty(channels.diaph_idx) && is_diaph_name(key)
            channels.diaph_idx = i;
            channels.diaph_name = raw_name;
            channels.diaph_source = 'diaph';
        elseif is_generic_resp_name(key)
            generic_idx(end+1) = i; %#ok<AGROW>
            generic_name{end+1} = raw_name; %#ok<AGROW>
        end
    end

    for g = 1:numel(generic_idx)
        if isempty(channels.lungs_idx)
            channels.lungs_idx = generic_idx(g);
            channels.lungs_name = generic_name{g};
            channels.lungs_source = 'generic';
        elseif isempty(channels.diaph_idx)
            channels.diaph_idx = generic_idx(g);
            channels.diaph_name = generic_name{g};
            channels.diaph_source = 'generic';
        end
    end

    channels.has_spo2 = ~isempty(channels.spo2_idx);
    channels.has_lungs = ~isempty(channels.lungs_idx);
    channels.has_diaph = ~isempty(channels.diaph_idx);
    channels.resp_count = double(channels.has_lungs) + double(channels.has_diaph);

    if channels.resp_count < 1
        error(['At least one respiratory belt column is required. Accepted respiratory names include ' ...
            'Resp-Lungs, Lungs, Thorax, Chest, Resp-Diaphragm, Diaphragm, Abdomen, Resp, RespiratoryBelt, Respiration.']);
    end

    config.channels = channels;
    input_config = build_input_config(channels);
    config.input_config = input_config;
end

function input_config = build_input_config(channels)
    all_labels = {'shallowB', 'irregB', 'slowB', 'rapidB', 'asyncB', 'desat', 'apnea', 'sigh', 'CSR', 'deepB'};
    running = {'shallowB', 'irregB', 'slowB', 'rapidB', 'apnea', 'sigh', 'CSR', 'deepB'};
    skipped = {};

    if channels.resp_count >= 2
        running{end+1} = 'asyncB';
    else
        skipped{end+1} = 'asyncB';
    end

    if channels.has_spo2
        running{end+1} = 'desat';
    else
        skipped{end+1} = 'desat';
    end

    running = all_labels(ismember(all_labels, running));
    skipped = all_labels(ismember(all_labels, skipped));

    if channels.resp_count >= 2 && channels.has_spo2
        description = 'two respiratory belts + SpO2';
    elseif channels.resp_count >= 2
        description = 'two respiratory belts, no SpO2';
    elseif channels.has_spo2
        description = 'one respiratory belt + SpO2';
    else
        description = 'one respiratory belt, no SpO2';
    end

    input_config = struct();
    input_config.description = description;
    input_config.running_labels = running;
    input_config.skipped_labels = skipped;
    input_config.resp_count = channels.resp_count;
    input_config.has_spo2 = channels.has_spo2;
    input_config.lungs_name = channels.lungs_name;
    input_config.diaph_name = channels.diaph_name;
    input_config.spo2_name = channels.spo2_name;
end

function key = normalized_channel_key(name)
    key = lower(char(string(name)));
    key = regexprep(key, '[^a-z0-9]', '');
end

function tf = is_spo2_name(key)
    tf = contains(key, 'spo') || contains(key, 'sao') || contains(key, 'oxygensaturation');
end

function tf = is_lungs_name(key)
    tf = any(strcmp(key, {'resplungs', 'lungs', 'lung', 'thorax', 'chest', 'respchest', 'respthorax'}));
end

function tf = is_diaph_name(key)
    tf = any(strcmp(key, {'respdiaphragm', 'diaphragm', 'diaph', 'abdomen', 'abdominal', 'respabdomen', 'respabdominal'}));
end

function tf = is_generic_resp_name(key)
    tf = any(strcmp(key, {'resp', 'respiration', 'respiratorybelt', 'belt'})) || ...
        (contains(key, 'resp') && ~is_spo2_name(key) && ~is_lungs_name(key) && ~is_diaph_name(key));
end
