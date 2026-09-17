function log_message(config, level, message, varargin)
% LOG_MESSAGE Print a formatted pipeline message at the requested verbosity.
% Missing config.verbosity preserves the concise default for older configs.

    verbosity = 1;
    if isstruct(config) && isfield(config, 'verbosity') && ...
            ~isempty(config.verbosity)
        verbosity = config.verbosity;
    end

    if ~(isnumeric(verbosity) || islogical(verbosity)) || ...
            ~isscalar(verbosity) || ~isfinite(verbosity)
        error('MAGMA:Config:InvalidVerbosity', ...
            'config.verbosity must be a finite numeric scalar.');
    end
    if ~(isnumeric(level) || islogical(level)) || ...
            ~isscalar(level) || ~isfinite(level)
        error('MAGMA:Logging:InvalidLevel', ...
            'Logging level must be a finite numeric scalar.');
    end

    if verbosity >= level
        fprintf([char(message) '\n'], varargin{:});
    end
end
