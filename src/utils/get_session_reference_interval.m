function reference = get_session_reference_interval(N, config)
% get_session_reference_interval
% Resolve the one common physiological reference interval on config.fs.
%
% The returned interval follows the repository's half-open convention:
%   start_t = (start_idx - 1) / fs
%   end_t   = end_idx / fs
%   samples = start_idx:end_idx
%
% M1/M3 use 3-6 min and M2/M4 use 19-22 min by default. A recording
% ending inside the requested interval is explicitly marked as truncated;
% the interval is never shifted to another part of the recording.

    validate_inputs(N, config);
    cfg = reference_config(config);

    switch config.measure
        case {1, 3}
            requested_start_min = cfg.pre_start_min;
            requested_end_min = cfg.pre_end_min;
            protocol_phase = 'pre_stress';
        case {2, 4}
            requested_start_min = cfg.post_start_min;
            requested_end_min = cfg.post_end_min;
            protocol_phase = 'post_stress';
        otherwise
            error('MAGMA:SessionReference:UnsupportedMeasurement', ...
                'No session physiological reference interval is defined for measurement %g.', ...
                config.measure);
    end

    validate_minutes(requested_start_min, requested_end_min, protocol_phase);
    fs = config.fs;
    requested_start_idx = round(60 * requested_start_min * fs) + 1;
    requested_end_idx = round(60 * requested_end_min * fs);
    requested_start_t = (requested_start_idx - 1) / fs;
    requested_end_t = requested_end_idx / fs;

    reference = struct( ...
        'reference_start_idx', 1, ...
        'reference_end_idx', 0, ...
        'reference_start_t', NaN, ...
        'reference_end_t', NaN, ...
        'reference_duration_sec', 0, ...
        'requested_start_idx', requested_start_idx, ...
        'requested_end_idx', requested_end_idx, ...
        'requested_start_t', requested_start_t, ...
        'requested_end_t', requested_end_t, ...
        'requested_duration_sec', requested_end_t - requested_start_t, ...
        'protocol_phase', protocol_phase, ...
        'measurement', config.measure, ...
        'available', false, ...
        'complete', false, ...
        'truncated', false, ...
        'quality', 'unavailable', ...
        'truncation_reason', '', ...
        'reference_schema_version', 'session_physiological_reference_v1');

    if N < requested_start_idx
        reference.truncated = true;
        reference.quality = 'recording_ends_before_reference_start';
        reference.truncation_reason = 'recording_ends_before_reference_start';
        return;
    end

    start_idx = requested_start_idx;
    end_idx = min(N, requested_end_idx);
    reference.reference_start_idx = start_idx;
    reference.reference_end_idx = end_idx;
    reference.reference_start_t = (start_idx - 1) / fs;
    reference.reference_end_t = end_idx / fs;
    reference.reference_duration_sec = (end_idx - start_idx + 1) / fs;
    reference.available = end_idx >= start_idx;
    reference.complete = end_idx == requested_end_idx;
    reference.truncated = ~reference.complete;

    if reference.complete
        reference.quality = 'good';
    else
        reference.quality = 'truncated_recording';
        reference.truncation_reason = 'recording_ends_inside_reference_interval';
    end
end

function cfg = reference_config(config)
    cfg = struct( ...
        'pre_start_min', 3, ...
        'pre_end_min', 6, ...
        'post_start_min', 19, ...
        'post_end_min', 22);
    if isfield(config, 'reference') && isstruct(config.reference)
        names = fieldnames(cfg);
        for i = 1:numel(names)
            if isfield(config.reference, names{i})
                cfg.(names{i}) = config.reference.(names{i});
            end
        end
    end
end

function validate_inputs(N, config)
    if ~isscalar(N) || ~isnumeric(N) || ~isfinite(N) || N < 0 || N ~= round(N)
        error('MAGMA:SessionReference:InvalidLength', ...
            'N must be a nonnegative integer sample count.');
    end
    if ~isstruct(config) || ~isfield(config, 'fs') || ...
            ~isscalar(config.fs) || ~isfinite(config.fs) || config.fs <= 0
        error('MAGMA:SessionReference:InvalidSamplingRate', ...
            'config.fs must be a finite positive scalar.');
    end
    if ~isfield(config, 'measure') || ~isscalar(config.measure) || ...
            ~isfinite(config.measure)
        error('MAGMA:SessionReference:MissingMeasurement', ...
            'config.measure is required to select the session reference interval.');
    end
end

function validate_minutes(start_min, end_min, interval_name)
    if ~isscalar(start_min) || ~isscalar(end_min) || ...
            ~isfinite(start_min) || ~isfinite(end_min) || ...
            start_min < 0 || end_min <= start_min
        error('MAGMA:SessionReference:InvalidInterval', ...
            'config.reference %s interval must have 0 <= start < end.', ...
            interval_name);
    end
end
