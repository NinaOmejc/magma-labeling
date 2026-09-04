function spo2_ref = compute_spo2_reference(data, session_reference, config)
% COMPUTE_SPO2_REFERENCE Compute spo2 reference.
%
% Syntax:
%   spo2_ref = compute_spo2_reference(data, session_reference, config)
%
% Inputs:
%   data - Input physiological signal data.
%   session_reference - Session-reference metadata.
%   config - Pipeline configuration structure.
%
% Outputs:
%   spo2_ref - SpO2-reference structure.

    if ~isfield(config, 'channels')
        config = resolve_signal_channels(config);
    end

    minimum_valid_samples = 2;
    if isfield(config, 'reference') && ...
            isfield(config.reference, 'spo2_min_valid_samples')
        minimum_valid_samples = config.reference.spo2_min_valid_samples;
    end
    if ~isscalar(minimum_valid_samples) || ~isfinite(minimum_valid_samples) || ...
            minimum_valid_samples < 1 || minimum_valid_samples ~= round(minimum_valid_samples)
        error('MAGMA:SpO2Reference:InvalidMinimumSamples', ...
            'config.reference.spo2_min_valid_samples must be a positive integer.');
    end

    spo2_ref = struct( ...
        'available', false, ...
        'quality', 'not_evaluated', ...
        'median_percent', NaN, ...
        'mean_percent', NaN, ...
        'n_valid_samples', 0, ...
        'n_interval_samples', 0, ...
        'valid_fraction', NaN, ...
        'minimum_valid_samples', minimum_valid_samples, ...
        'source', 'common_session_reference_interval');

    if ~isstruct(session_reference) || ~isfield(session_reference, 'available') || ...
            ~session_reference.available
        spo2_ref.quality = 'reference_interval_unavailable';
        return;
    end

    idx_spo2 = config.channels.spo2_idx;
    if isempty(idx_spo2)
        spo2_ref.quality = 'signal_unavailable';
        return;
    end

    start_idx = session_reference.reference_start_idx;
    end_idx = session_reference.reference_end_idx;
    if start_idx < 1 || end_idx > size(data, 1) || end_idx < start_idx
        spo2_ref.quality = 'reference_interval_unavailable';
        return;
    end

    values = data(start_idx:end_idx, idx_spo2);
    finite_values = values(isfinite(values));
    spo2_ref.n_interval_samples = numel(values);
    spo2_ref.n_valid_samples = numel(finite_values);
    if spo2_ref.n_interval_samples > 0
        spo2_ref.valid_fraction = spo2_ref.n_valid_samples / spo2_ref.n_interval_samples;
    end
    if spo2_ref.n_valid_samples < minimum_valid_samples
        spo2_ref.quality = 'insufficient_valid_samples';
        return;
    end

    spo2_ref.median_percent = median(finite_values, 'omitnan');
    spo2_ref.mean_percent = mean(finite_values, 'omitnan');
    spo2_ref.available = isfinite(spo2_ref.median_percent);
    if spo2_ref.available
        if session_reference.complete
            spo2_ref.quality = 'good';
        else
            spo2_ref.quality = 'warning_truncated_interval';
        end
    else
        spo2_ref.quality = 'invalid_reference_statistic';
    end
end
