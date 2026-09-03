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
    input_config = build_input_config(channels, config);
    config.input_config = input_config;
end

function input_config = build_input_config(channels, config)
    if ~isfield(config, 'labels') || ~isfield(config.labels, 'short')
        current_config = get_config();
        all_labels = {current_config.labels.short};
    else
        all_labels = {config.labels.short};
    end
    lung_belt_ignored = is_lung_belt_ignored(config);
    effective_has_lungs = channels.has_lungs && ~lung_belt_ignored;
    effective_has_diaph = channels.has_diaph;
    effective_resp_count = double(effective_has_lungs) + double(effective_has_diaph);

    running = {};
    if effective_resp_count >= 1
        running = all_labels(~ismember(all_labels, {'async','thoracic','desat'}));
    end
    if effective_resp_count >= 2
        running = [running, {'async', 'thoracic'}];
    end
    if channels.has_spo2
        running{end+1} = 'desat';
    end

    running = all_labels(ismember(all_labels, running));
    skipped = all_labels(~ismember(all_labels, running));

    if effective_resp_count >= 2 && channels.has_spo2
        description = 'two usable respiratory belts + SpO2';
    elseif effective_resp_count >= 2
        description = 'two usable respiratory belts, no SpO2';
    elseif effective_resp_count == 1 && channels.has_spo2
        description = 'one usable respiratory belt + SpO2';
    elseif effective_resp_count == 1
        description = 'one usable respiratory belt, no SpO2';
    elseif channels.has_spo2
        description = 'no usable respiratory belt + SpO2';
    else
        description = 'no usable respiratory belt, no SpO2';
    end
    if lung_belt_ignored
        description = [description ' (known lung-belt exclusion)'];
    end

    input_config = struct();
    input_config.description = description;
    input_config.running_labels = running;
    input_config.skipped_labels = skipped;
    input_config.resp_count = effective_resp_count;
    input_config.effective_resp_count = effective_resp_count;
    input_config.physical_resp_count = channels.resp_count;
    input_config.has_spo2 = channels.has_spo2;
    input_config.physical_has_lungs = channels.has_lungs;
    input_config.physical_has_diaph = channels.has_diaph;
    input_config.effective_has_lungs = effective_has_lungs;
    input_config.effective_has_diaph = effective_has_diaph;
    input_config.lung_belt_ignored = lung_belt_ignored;
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
