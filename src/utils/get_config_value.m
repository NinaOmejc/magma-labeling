function value = get_config_value(config, section, name, default_value)
% get_config_value
% Read config.<section>.<name> with a fallback default.

    value = default_value;
    if isfield(config, section) && isfield(config.(section), name)
        value = config.(section).(name);
    end
end
