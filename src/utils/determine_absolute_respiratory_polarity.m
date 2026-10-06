function [data, trend, config] = determine_absolute_respiratory_polarity( ...
    data, trend, config, fs)
% DETERMINE_ABSOLUTE_RESPIRATORY_POLARITY Orient both belts by breath timing.
% Run after relative belt correction and before final cycle extraction. The
% landmarks measured here are temporary; downstream extraction detects them
% again on the final signals, including after a polarity flip.

    settings = struct('enabled', true, 'ratio_lower', 0.90, ...
        'ratio_upper', 1.10, 'min_valid_breaths', 10);
    if ~isfield(config, 'preprocessing') || ~isstruct(config.preprocessing)
        config.preprocessing = struct();
    end
    if isfield(config.preprocessing, 'absolute_polarity') && ...
            isstruct(config.preprocessing.absolute_polarity)
        provided = config.preprocessing.absolute_polarity;
        names = fieldnames(settings);
        for i = 1:numel(names)
            if isfield(provided, names{i}) && ~isempty(provided.(names{i}))
                settings.(names{i}) = provided.(names{i});
            end
        end
    end
    validate_settings(settings);
    config.preprocessing.absolute_polarity = settings;

    qc = struct( ...
        'absolute_polarity_checked', false, ...
        'absolute_polarity_flipped', false, ...
        'ie_ratio_lungs', NaN, ...
        'ie_ratio_diaphragm', NaN, ...
        'ie_ratio_combined', NaN, ...
        'n_valid_breaths_lungs', 0, ...
        'n_valid_breaths_diaphragm', 0, ...
        'absolute_polarity_decision', 'insufficient_data', ...
        'channels_used', {{}});
    if ~settings.enabled
        config.preprocessing.absolute_polarity_qc = qc;
        log_message(config, 2, 'Absolute respiratory polarity: disabled.');
        return;
    end

    qc.absolute_polarity_checked = true;
    if isvector(data) || ~isfield(config, 'channels') || ...
            ~isscalar(fs) || ~isfinite(fs) || fs <= 0
        config.preprocessing.absolute_polarity_qc = qc;
        log_message(config, 1, ...
            'Absolute respiratory polarity: insufficient valid breaths, unchanged.');
        return;
    end

    % Use the same automatic peak/trough detector and respiratory QC settings
    % as the final extraction, without its plots or manual review.
    temporary_config = config;
    temporary_config.resp.do_plot = false;
    belts = {'lungs', 'diaph'};
    ratios = nan(1, 2);
    counts = zeros(1, 2);
    indices = nan(1, 2);
    for i = 1:2
        role = belts{i};
        has_field = ['has_' role];
        if strcmp(role, 'diaph')
            has_field = 'has_diaph';
        end
        idx_field = [role '_idx'];
        if ~isfield(config.channels, has_field) || ...
                ~config.channels.(has_field) || ...
                ~isfield(config.channels, idx_field)
            continue;
        end
        idx = config.channels.(idx_field);
        if ~isnumeric(idx) || ~isscalar(idx) || ~isfinite(idx) || ...
                idx ~= fix(idx) || idx < 1 || idx > size(data, 2) || ...
                any(indices(1:i-1) == idx)
            continue;
        end
        indices(i) = idx;
        if strcmp(role, 'lungs') && is_lung_belt_ignored(config)
            continue;
        end
        signal = data(:, idx);
        if nnz(isfinite(signal)) < 3
            continue;
        end
        landmarks = extract_respiration_feature( ...
            signal, temporary_config, role);
        [ratios(i), counts(i)] = median_ie_ratio( ...
            landmarks, signal, fs, config.resp.min_peak_dist_sec);
    end

    qc.ie_ratio_lungs = ratios(1);
    qc.ie_ratio_diaphragm = ratios(2);
    qc.n_valid_breaths_lungs = counts(1);
    qc.n_valid_breaths_diaphragm = counts(2);
    usable = counts >= settings.min_valid_breaths & isfinite(ratios);
    qc.channels_used = belts(usable);
    if any(usable)
        qc.ie_ratio_combined = median(ratios(usable));
        if qc.ie_ratio_combined < settings.ratio_lower
            qc.absolute_polarity_decision = 'kept';
        elseif qc.ie_ratio_combined > settings.ratio_upper
            qc.absolute_polarity_decision = 'flipped';
            for i = 1:2
                if ~isfinite(indices(i))
                    continue;
                end
                idx = indices(i);
                data(:, idx) = -data(:, idx);
                if ~isempty(trend) && ~isvector(trend) && ...
                        size(trend, 1) == size(data, 1) && ...
                        idx <= size(trend, 2)
                    trend(:, idx) = -trend(:, idx);
                end
            end
            qc.absolute_polarity_flipped = true;
        else
            qc.absolute_polarity_decision = 'ambiguous';
        end
    end
    config.preprocessing.absolute_polarity_qc = qc;

    if strcmp(qc.absolute_polarity_decision, 'insufficient_data')
        log_message(config, 1, ...
            ['Absolute respiratory polarity: insufficient valid breaths, ' ...
             'unchanged (lungs = %d, diaphragm = %d).'], counts(1), counts(2));
    else
        label = qc.absolute_polarity_decision;
        if strcmp(label, 'flipped'), label = 'flipped both belts'; end
        if strcmp(label, 'ambiguous'), label = 'ambiguous, unchanged'; end
        log_message(config, 1, ...
            ['Absolute respiratory polarity: %s (median I:E before flip = ' ...
             '%.2f; lungs = %.2f, diaphragm = %.2f; valid breaths = %d / %d; ' ...
             'used: %s).'], label, qc.ie_ratio_combined, ratios(1), ...
            ratios(2), counts(1), counts(2), strjoin(qc.channels_used, ', '));
    end
end

function [ratio, n_valid] = median_ie_ratio(b, signal, fs, min_breath_sec)
% MEDIAN_IE_RATIO Measure complete trough-peak-trough cycles only.

    ratio = NaN;
    n_valid = 0;
    if ~isfield(b, 'peak_idx') || ~isfield(b, 'trough_idx') || ...
            ~isfield(b, 'peak_val') || ~isfield(b, 'trough_val')
        return;
    end
    peaks = b.peak_idx(:);
    troughs = b.trough_idx(:);
    if numel(peaks) < 3 || numel(troughs) ~= numel(peaks) - 1
        return;
    end
    values = nan(numel(peaks) - 2, 1);
    for i = 2:numel(peaks)-1
        before = troughs(i-1);
        peak = peaks(i);
        after = troughs(i);
        if ~all(isfinite([before peak after])) || ...
                ~all(isfinite([b.trough_val(i-1) b.peak_val(i) b.trough_val(i)])) || ...
                before < 1 || after > numel(signal) || ...
                ~(before < peak && peak < after) || ...
                ~all(isfinite(signal(before:after)))
            continue;
        end
        insp = (peak - before) / fs;
        exp = (after - peak) / fs;
        if insp <= 0 || exp <= 0 || insp + exp < min_breath_sec
            continue;
        end
        values(i-1) = insp / exp;
    end
    values = values(isfinite(values));
    n_valid = numel(values);
    if n_valid > 0
        ratio = median(values);
    end
end

function validate_settings(settings)
    if ~(islogical(settings.enabled) || isnumeric(settings.enabled)) || ...
            ~isscalar(settings.enabled) || ~isfinite(settings.enabled) || ...
            ~isnumeric(settings.ratio_lower) || ...
            ~isnumeric(settings.ratio_upper) || ...
            ~isscalar(settings.ratio_lower) || ...
            ~isscalar(settings.ratio_upper) || ...
            ~isfinite(settings.ratio_lower) || ...
            ~isfinite(settings.ratio_upper) || ...
            settings.ratio_lower <= 0 || ...
            settings.ratio_lower >= settings.ratio_upper || ...
            ~isnumeric(settings.min_valid_breaths) || ...
            ~isscalar(settings.min_valid_breaths) || ...
            ~isfinite(settings.min_valid_breaths) || ...
            settings.min_valid_breaths < 1 || ...
            settings.min_valid_breaths ~= fix(settings.min_valid_breaths)
        error('MAGMA:Config:InvalidAbsolutePolarity', ...
            'Invalid config.preprocessing.absolute_polarity settings.');
    end
end
