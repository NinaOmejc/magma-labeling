function [start_idx, end_idx, start_t, end_t] = get_static_baseline_interval(N, config)
% get_static_baseline_interval
% Return the sample interval used for the static baseline.

    start_idx = 1;
    end_idx = 0;
    start_t = NaN;
    end_t = NaN;

    if isfield(config, 'new_fs')
        fs = config.new_fs;
    elseif isfield(config, 'fs')
        fs = config.fs;
    else
        fs = NaN;
    end

    if N <= 0 || ~isfinite(fs) || fs <= 0
        return;
    end

    baseline_sec = 60;
    if isfield(config, 'baseline_sec') && isfinite(config.baseline_sec) && config.baseline_sec > 0
        baseline_sec = config.baseline_sec;
    end

    win_samples = max(1, min(N, round(baseline_sec * fs)));
    max_start = max(1, N - win_samples + 1);

    location = 'first';
    if isfield(config, 'baseline_location') && ~isempty(config.baseline_location)
        location = config.baseline_location;
    end

    switch lower(location)
        case 'second'
            desired_start = win_samples + 1;
        case 'last'
            desired_start = max_start;
        case '5/20'
            if isfield(config, 'measure') && (config.measure == 1 || config.measure == 3)
                desired_start = round(5 * 60 * fs) + 1;
            else
                desired_start = round(20 * 60 * fs) + 1;
            end
        otherwise
            desired_start = 1;
    end

    start_idx = min(max(1, desired_start), max_start);
    end_idx = min(N, start_idx + win_samples - 1);
    start_t = (start_idx - 1) / fs;
    end_t = end_idx / fs;
end
