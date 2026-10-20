function [data, trend, config] = correct_respiratory_belt_polarity( ...
    data, trend, config, fs)
% CORRECT_RESPIRATORY_BELT_POLARITY Review persistent inverse belt correlation.
% Correlation cannot identify which sensor, if either, has reversed polarity.
% Manual mode asks which belt to flip; 'auto' retains the legacy diaphragm
% correction. Deferral raises MAGMA:Respiration:PolarityReviewDeferred before
% downstream feature extraction or saving can take place.

    qc = empty_polarity_qc();
    if ~isfield(config, 'preprocessing') || ...
            ~isstruct(config.preprocessing)
        config.preprocessing = struct();
    end
    if ~isfield(config.preprocessing, 'check_relative_belt_polarity') || ...
            isempty(config.preprocessing.check_relative_belt_polarity)
        config.preprocessing.check_relative_belt_polarity = false;
    end

    enabled = config.preprocessing.check_relative_belt_polarity;
    if ~(islogical(enabled) || isnumeric(enabled)) || ...
            ~isscalar(enabled) || ~isfinite(enabled)
        error('MAGMA:Config:InvalidBeltPolarityCheck', ...
            ['config.preprocessing.check_relative_belt_polarity must be a ' ...
             'finite logical or numeric scalar.']);
    end
    if ~logical(enabled)
        qc.reason = 'disabled';
        config.preprocessing.belt_polarity_qc = qc;
        log_message(config, 2, 'Respiratory belt polarity: check disabled.');
        return;
    end

    if ~isfield(config.preprocessing, 'relative_belt_polarity_mode') || ...
            isempty(config.preprocessing.relative_belt_polarity_mode)
        config.preprocessing.relative_belt_polarity_mode = 'manual';
    end
    mode = config.preprocessing.relative_belt_polarity_mode;
    if ~((ischar(mode) && isrow(mode)) || ...
            (isstring(mode) && isscalar(mode) && ~ismissing(mode))) || ...
            ~any(strcmpi(mode, {'manual', 'auto'}))
        error('MAGMA:Config:InvalidBeltPolarityMode', ...
            ['config.preprocessing.relative_belt_polarity_mode must be ' ...
             '''manual'' or ''auto''.']);
    end
    qc.mode = lower(char(mode));

    if isvector(data)
        qc.reason = 'single_signal_input';
        config.preprocessing.belt_polarity_qc = qc;
        log_message(config, 2, ...
            'Respiratory belt polarity: skipped for single-signal input.');
        return;
    end
    if ~isfield(config, 'channels')
        config = resolve_signal_channels(config);
    end
    channels = config.channels;
    if ~isfield(channels, 'has_lungs') || ~channels.has_lungs || ...
            ~isfield(channels, 'has_diaph') || ~channels.has_diaph
        qc.reason = 'two_respiratory_belts_not_available';
        config.preprocessing.belt_polarity_qc = qc;
        log_message(config, 2, ...
            'Respiratory belt polarity: two usable belts are not available.');
        return;
    end
    if is_lung_belt_ignored(config)
        qc.reason = 'lung_belt_marked_missing';
        config.preprocessing.belt_polarity_qc = qc;
        log_message(config, 2, ...
            'Respiratory belt polarity: lung belt is marked missing.');
        return;
    end

    if minimal_thoracic_excursion(config)
        qc.reason = 'minimal_thoracic_excursion';
        config.preprocessing.belt_polarity_qc = qc;
        return;
    end

    idx_lungs = channels.lungs_idx;
    idx_diaph = channels.diaph_idx;
    if ~valid_channel_index(idx_lungs, size(data, 2)) || ...
            ~valid_channel_index(idx_diaph, size(data, 2)) || ...
            idx_lungs == idx_diaph
        qc.reason = 'belt_index_out_of_range';
        config.preprocessing.belt_polarity_qc = qc;
        log_message(config, 2, ...
            'Respiratory belt polarity: configured belt index is invalid.');
        return;
    end

    qc.checked = true;
    qc.reference_belt = resolved_belt_name(channels, 'lungs');
    lungs = data(:, idx_lungs);
    diaph = data(:, idx_diaph);
    min_usable_samples = max(3, ceil(30 * fs));
    paired_finite = isfinite(lungs) & isfinite(diaph);
    if ~isscalar(fs) || ~isfinite(fs) || fs <= 0 || ...
            fs / 2 <= 0.60 || nnz(paired_finite) < min_usable_samples
        qc.reason = 'insufficient_valid_respiratory_data';
        config.preprocessing.belt_polarity_qc = qc;
        log_message(config, 2, ...
            'Respiratory belt polarity: insufficient valid respiratory data.');
        return;
    end

    [lungs_band, lungs_ok] = respiratory_band_signal(lungs, fs);
    [diaph_band, diaph_ok] = respiratory_band_signal(diaph, fs);
    if ~lungs_ok || ~diaph_ok
        qc.reason = 'insufficient_valid_respiratory_data';
        config.preprocessing.belt_polarity_qc = qc;
        log_message(config, 2, ...
            'Respiratory belt polarity: insufficient valid respiratory data.');
        return;
    end

    window_corr = respiratory_window_correlations( ...
        lungs_band, diaph_band, fs);
    qc.n_windows = numel(window_corr);
    if isempty(window_corr)
        qc.reason = 'too_few_valid_windows';
        config.preprocessing.belt_polarity_qc = qc;
        log_message(config, 2, ...
            'Respiratory belt polarity: no sufficiently valid windows.');
        return;
    end

    informative = abs(window_corr) >= 0.50;
    informative_corr = window_corr(informative);
    qc.n_informative_windows = numel(informative_corr);
    qc.informative_window_fraction = ...
        qc.n_informative_windows / qc.n_windows;
    if ~isempty(informative_corr)
        qc.median_window_corr = median(informative_corr);
        qc.negative_window_fraction = ...
            mean(informative_corr <= -0.50);
    end

    if qc.n_informative_windows < 3
        qc.reason = 'too_few_informative_windows';
        config.preprocessing.belt_polarity_qc = qc;
        log_message(config, 2, ...
            ['Respiratory belt polarity: only %d informative long ' ...
             'window(s); no correction.'], qc.n_informative_windows);
        return;
    end

    should_review = qc.median_window_corr <= -0.65 && ...
        qc.negative_window_fraction >= 0.80 && ...
        qc.informative_window_fraction >= 0.60;
    if should_review
        if strcmp(qc.mode, 'manual')
            choice = review_belt_polarity(config, qc);
            qc.manual_choice = choice;
        else
            choice = 2; % Explicit legacy mode: fixed thoracic reference.
        end
        if choice == 3
            error('MAGMA:Respiration:PolarityReviewDeferred', ...
                'Respiratory belt polarity review deferred for %s.', ...
                recording_name(config));
        elseif choice == 0
            qc.reason = 'manual_keep_both';
            config.preprocessing.belt_polarity_qc = qc;
            log_message(config, 1, ...
                'Respiratory belt polarity: user kept both belts unchanged.');
            return;
        elseif choice == 1
            idx_flip = idx_lungs;
            qc.thoracic_polarity_flipped = true;
            qc.corrected_belt = resolved_belt_name(channels, 'lungs');
            qc.reference_belt = resolved_belt_name(channels, 'diaph');
        else
            idx_flip = idx_diaph;
            qc.diaphragm_polarity_flipped = true;
            qc.corrected_belt = resolved_belt_name(channels, 'diaph');
        end
        data(:, idx_flip) = -data(:, idx_flip);
        if ~isempty(trend) && ~isvector(trend) && ...
                size(trend, 1) == size(data, 1) && ...
                idx_flip <= size(trend, 2)
            trend(:, idx_flip) = -trend(:, idx_flip);
        end
        qc.flipped = true;
        qc.reason = 'persistent_strong_inverse_belt_polarity';
        if strcmp(qc.mode, 'manual')
            qc.reason = 'manual_flip_selected_belt';
        end
        log_message(config, 1, ...
            ['Respiratory belt polarity: flipped %s relative to %s ' ...
             '(median r = %.3f, negative informative windows = %.1f%%).'], ...
            qc.corrected_belt, qc.reference_belt, ...
            qc.median_window_corr, 100 * qc.negative_window_fraction);
    else
        qc.reason = 'no_clear_global_polarity_inversion';
        log_message(config, 2, ...
            ['Respiratory belt polarity: no clear global inversion ' ...
             '(median r = %.3f, negative informative windows = %.1f%%).'], ...
            qc.median_window_corr, 100 * qc.negative_window_fraction);
    end
    config.preprocessing.belt_polarity_qc = qc;
end

function qc = empty_polarity_qc()
% EMPTY_POLARITY_QC Return the stable preprocessing provenance schema.

    qc = struct( ...
        'checked', false, ...
        'flipped', false, ...
        'thoracic_polarity_flipped', false, ...
        'diaphragm_polarity_flipped', false, ...
        'mode', '', ...
        'manual_choice', NaN, ...
        'reference_belt', '', ...
        'corrected_belt', '', ...
        'median_window_corr', NaN, ...
        'negative_window_fraction', NaN, ...
        'informative_window_fraction', NaN, ...
        'n_windows', 0, ...
        'n_informative_windows', 0, ...
        'reason', 'not_evaluated');
end

function choice = review_belt_polarity(config, qc)
% REVIEW_BELT_POLARITY Read text so expressions and malformed input are inert.

    fprintf(['\n--------------------------------------------------\n' ...
        'MAGMA: RESPIRATORY BELT POLARITY REVIEW\n' ...
        'Recording: %s\n\n' ...
        'Persistent negative thoracoabdominal correlation detected.\n' ...
        'Median correlation: %.2f\n' ...
        'Negative informative windows: %.0f%%\n\n' ...
        'This may indicate inverted sensor polarity OR genuine\n' ...
        'paradoxical respiratory movement.\n\n' ...
        'Choose how to proceed:\n\n' ...
        '1 = Flip THORACIC belt (Resp-Lungs) ONLY\n' ...
        '2 = Flip ABDOMINAL belt (Resp-Diaphragm) ONLY\n' ...
        '0 = Keep BOTH belts unchanged\n' ...
        '3 = Defer decision / cancel this recording\n\n'], ...
        recording_name(config), qc.median_window_corr, ...
        100 * qc.negative_window_fraction);
    while true
        answer = strtrim(input('Enter your choice (0/1/2/3): ', 's'));
        if any(strcmp(answer, {'0', '1', '2', '3'}))
            choice = str2double(answer);
            return;
        end
        fprintf('Invalid choice. Enter 0, 1, 2, or 3.\n');
    end
end

function name = recording_name(config)
    name = 'Unknown recording';
    if isfield(config, 'subject') && isfield(config, 'measure')
        name = sprintf('Sub%d_M%d', config.subject, config.measure);
    end
end

function tf = valid_channel_index(idx, n_columns)
% VALID_CHANNEL_INDEX Check that a resolved channel index selects one column.

    tf = isnumeric(idx) && isscalar(idx) && isfinite(idx) && ...
        idx == fix(idx) && idx >= 1 && idx <= n_columns;
end

function name = resolved_belt_name(channels, role)
% RESOLVED_BELT_NAME Return the resolved name with a stable canonical fallback.

    field = [role '_name'];
    if isfield(channels, field) && ~isempty(channels.(field))
        name = char(string(channels.(field)));
    elseif strcmp(role, 'lungs')
        name = 'Resp-Lungs';
    else
        name = 'Resp-Diaphragm';
    end
end

function [band_signal, ok] = respiratory_band_signal(signal, fs)
% RESPIRATORY_BAND_SIGNAL Make a temporary 0.05-0.60 Hz QC representation.

    signal = signal(:);
    finite_mask = isfinite(signal);
    band_signal = nan(size(signal));
    ok = nnz(finite_mask) >= max(3, ceil(30 * fs));
    if ~ok
        return;
    end

    filled = fillmissing(signal, 'linear', 'EndValues', 'nearest');
    [z, p, k] = butter(4, [0.05 0.60] / (fs / 2), 'bandpass');
    [sos, gain] = zp2sos(z, p, k);
    band_signal = filtfilt(sos, gain, filled);
    band_signal(~finite_mask) = NaN;
    ok = any(isfinite(band_signal));
end

function correlations = respiratory_window_correlations(lungs, diaph, fs)
% RESPIRATORY_WINDOW_CORRELATIONS Correlate sufficiently valid long windows.

    n_samples = numel(lungs);
    window_samples = max(1, round(60 * fs));
    step_samples = max(1, round(30 * fs));
    min_short_samples = max(1, ceil(30 * fs));
    if n_samples >= window_samples
        starts = 1:step_samples:(n_samples - window_samples + 1);
        stops = starts + window_samples - 1;
    elseif nnz(isfinite(lungs) & isfinite(diaph)) >= min_short_samples
        starts = 1;
        stops = n_samples;
    else
        correlations = zeros(1, 0);
        return;
    end

    correlations = nan(1, numel(starts));
    keep = false(1, numel(starts));
    for i = 1:numel(starts)
        idx = starts(i):stops(i);
        valid = isfinite(lungs(idx)) & isfinite(diaph(idx));
        if nnz(valid) < ceil(0.80 * numel(idx))
            continue;
        end
        x = lungs(idx);
        y = diaph(idx);
        x = x(valid);
        y = y(valid);
        if ~has_meaningful_variation(x) || ~has_meaningful_variation(y)
            continue;
        end
        x = x - mean(x);
        y = y - mean(y);
        denominator = sqrt(sum(x .^ 2) * sum(y .^ 2));
        if denominator <= 0 || ~isfinite(denominator)
            continue;
        end
        correlations(i) = max(-1, min(1, sum(x .* y) / denominator));
        keep(i) = true;
    end
    correlations = correlations(keep);
end

function tf = has_meaningful_variation(x)
% HAS_MEANINGFUL_VARIATION Reject flat and numerically near-flat windows.

    scale = max(abs(x));
    tolerance = max(1e-12, sqrt(eps) * max(scale, 1e-6));
    tf = isfinite(scale) && std(x) > tolerance;
end
