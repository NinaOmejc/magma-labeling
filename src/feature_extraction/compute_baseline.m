function baseline = compute_baseline(data, config)
% compute_baseline  Compute SpO2 baseline stats from the static segment.
% Respiratory amplitude normalization is stored separately in resp_ref.

    if ~isfield(config, 'channels')
        config = resolve_signal_channels(config);
    end

    idxSpO2 = config.channels.spo2_idx;

    baseline = struct();
    [baseline_start_idx, baseline_end_idx, baseline_start_t, baseline_end_t] = ...
        get_static_baseline_interval(size(data,1), config);
    d0 = data(baseline_start_idx:baseline_end_idx, :);

    baseline.static_baseline_start_idx = baseline_start_idx;
    baseline.static_baseline_end_idx = baseline_end_idx;
    baseline.static_baseline_start_t = baseline_start_t;
    baseline.static_baseline_end_t = baseline_end_t;
    baseline.static_baseline_location = '';
    if isfield(config, 'baseline_location')
        baseline.static_baseline_location = config.baseline_location;
    end
    baseline.SpO2_baseline_start_idx = baseline_start_idx;
    baseline.SpO2_baseline_end_idx = baseline_end_idx;
    baseline.SpO2_baseline_start_t = baseline_start_t;
    baseline.SpO2_baseline_end_t = baseline_end_t;

    if ~isempty(idxSpO2)
        baseline.SpO2_median = median(d0(:, idxSpO2), 'omitnan');
        baseline.SpO2_mean = mean(d0(:, idxSpO2), 'omitnan');
    else
        baseline.SpO2_median = NaN;
        baseline.SpO2_mean = NaN;
    end

end
