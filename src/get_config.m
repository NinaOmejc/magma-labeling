function config = get_config()
% GET_CONFIG Return the user-facing MAGMA configuration.
% Customize this small wrapper for local paths/subjects while keeping the
% complete scientific and export defaults in get_config_defaults.m.

    config = get_config_defaults();
end
