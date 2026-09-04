function value = get_config_value(config, section, name, default_value)
% GET_CONFIG_VALUE Return config value.
%
% Syntax:
%   value = get_config_value(config, section, name, default_value)
%
% Inputs:
%   config - Pipeline configuration structure.
%   section - Duration or window length in seconds.
%   name - Input value `name`.
%   default_value - Input value `default_value`.
%
% Outputs:
%   value - Computed numeric value.

    value = default_value;
    if isfield(config, section) && isfield(config.(section), name)
        value = config.(section).(name);
    end
end
