function value = get_config_value(config, section, name, default_value)
% GET_CONFIG_VALUE Read config.(section).(name) with an explicit fallback.
% Values are returned unchanged; missing sections or fields use default_value.

    value = default_value;
    if isfield(config, section) && isfield(config.(section), name)
        value = config.(section).(name);
    end
end
