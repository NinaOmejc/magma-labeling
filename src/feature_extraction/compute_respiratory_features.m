function resp_features = compute_respiratory_features(data, resp_cycles, resp_ref, config)
% COMPUTE_RESPIRATORY_FEATURES Project breath evidence onto a common time grid.
% data is Nsample-by-Nchannel; resp_cycles supplies per-breath timing/amplitude,
% resp_ref supplies session/global amplitude references, and config defines
% grid spacing, trailing windows, and thresholds. resp_features contains:
%   time_sec/grid_step_sec - Analysis-grid coordinates and spacing in seconds.
%   rate_windows_sec - Slow/rapid trailing-window durations.
%   amplitude_windows_sec - Apnea amplitude-window duration.
%   shallow_band_ratio/deep_ratio_threshold - Stored amplitude criteria.
%   lungs/diaph - Per-belt evidence structs documented by empty_belt_evidence.
%   belt_availability/both_belts_available - Usable timing-evidence flags.
%   thoracoabdominal_balance - Cross-belt amplitude-balance evidence.

    N = size(data, 1);
    t_grid = (0:config.grid_step_sec:(N-1)/config.fs)';
    cfg = evidence_config(config);

    resp_features = struct();
    resp_features.time_sec = t_grid;
    resp_features.grid_step_sec = config.grid_step_sec;
    resp_features.rate_windows_sec = struct( ...
        'slow', cfg.slow_win_sec, 'rapid', cfg.rapid_win_sec);
    resp_features.amplitude_windows_sec = struct('apnea', cfg.apnea_win_sec);
    resp_features.shallow_band_ratio = [cfg.shallow_lo_ratio cfg.shallow_hi_ratio];
    resp_features.deep_ratio_threshold = cfg.deep_ratio_threshold;

    % compute on individual belts 
    lungs_ignored = is_lung_belt_ignored(config);
    resp_features.lungs = build_belt_evidence( ...
        get_belt(resp_cycles, 'lungs'), get_belt(resp_ref, 'lungs'), lungs_ignored, t_grid, cfg, config);
    resp_features.diaph = build_belt_evidence( ...
        get_belt(resp_cycles, 'diaph'), get_belt(resp_ref, 'diaph'), false, t_grid, cfg, config);

    % compute on both belts 
    resp_features.belt_availability = struct( ...
        'lungs', resp_features.lungs.available, 'diaph', resp_features.diaph.available);
    resp_features.both_belts_available = resp_features.lungs.available && resp_features.diaph.available;
    resp_features.thoracoabdominal_balance = build_thoracoabdominal_balance(resp_features.lungs, resp_features.diaph, t_grid, cfg);
end

function belt = build_belt_evidence(source, reference, ignored, t_grid, cfg, config)
% BUILD_BELT_EVIDENCE Derive rate, amplitude, and irregularity evidence for one belt.
% source is one respiratory-cycle struct; reference is its respiratory
% amplitude-reference struct; ignored disables all evidence. t_grid is in
% seconds, cfg holds resolved thresholds/windows, and config supplies fs.
% belt follows the schema initialized by empty_belt_evidence.

    belt = empty_belt_evidence(t_grid);
    belt.ignored = logical(ignored);
    if ~isstruct(source)
        return;
    end

    % Preserve cycle alignment from resp_cycles: amp(i) belongs to peak i
    % (the final amplitude may be NaN), trough i lies between peaks i and
    % i+1, and ibi(i)/rr_bpm(i) span peak i to peak i+1.
    belt.peak_idx = get_field(source, 'peak_idx', []);
    belt.peak_t = get_field(source, 'peak_t', []);
    belt.trough_idx = get_field(source, 'trough_idx', []);
    belt.trough_t = get_field(source, 'trough_t', []);
    belt.amp = get_field(source, 'amp', []);
    belt.peak_idx = belt.peak_idx(:);
    belt.peak_t = belt.peak_t(:);
    belt.trough_idx = belt.trough_idx(:);
    belt.trough_t = belt.trough_t(:);
    belt.amp = belt.amp(:);
    if isempty(belt.trough_t) && ~isempty(belt.trough_idx) && ...
            isscalar(config.fs) && isfinite(config.fs) && config.fs > 0
        belt.trough_t = nan(size(belt.trough_idx));
        valid_trough_idx = isfinite(belt.trough_idx) & ...
            belt.trough_idx >= 1 & belt.trough_idx == round(belt.trough_idx);
        belt.trough_t(valid_trough_idx) = ...
            (belt.trough_idx(valid_trough_idx) - 1) / config.fs;
    end

    belt.available = is_valid_breath_signal(source, false) && ~belt.ignored;
    belt.amplitude_available = is_valid_breath_signal(source, true) && belt.available;

    [belt.ibi, belt.ibi_source] = interval_values(source, 'ibi', belt.peak_idx, belt.peak_t, config.fs);
    [belt.rr_bpm, belt.rr_source] = rate_values(source, belt.ibi);
    validate_available_alignment(belt);

    [belt.session_reference_value, belt.session_reference_available, belt.reference_quality] = reference_value(reference, 'session');
    [belt.global_reference_value, belt.global_reference_available] = reference_value(reference, 'global');
    if belt.ignored
        belt.session_reference_value = NaN;
        belt.session_reference_available = false;
        belt.global_reference_value = NaN;
        belt.global_reference_available = false;
        belt.reference_quality = 'belt_unavailable';
    end

    belt.amp_ratio_session = amplitude_ratio( ...
        belt.amp, belt.session_reference_value, belt.session_reference_available);
    belt.amp_ratio_global = amplitude_ratio( ...
        belt.amp, belt.global_reference_value, belt.global_reference_available);
    belt.session_amplitude_available = belt.amplitude_available && belt.session_reference_available;
    belt.global_amplitude_available = belt.amplitude_available && belt.global_reference_available;

    if belt.available
        belt.rate_slow_window_bpm = respiratory_rate_trace(belt.peak_t, t_grid, cfg.slow_win_sec);
        belt.rate_rapid_window_bpm = respiratory_rate_trace(belt.peak_t, t_grid, cfg.rapid_win_sec);
    end

    if belt.session_amplitude_available
        % Apnea retains its separate trailing-window amplitude criterion.
        [belt.apnea_amplitude_endpoint_mask, belt.apnea_amplitude_state_mask] = amplitude_threshold_mask( ...
            belt.peak_t, belt.amp_ratio_session, t_grid, cfg.apnea_win_sec, cfg.apnea_ratio_threshold, 2, 'le');
        [~, belt.apnea_amp_ratio_session_window_median] = amplitude_window_medians( ...
            belt.peak_t, belt.amp, belt.amp_ratio_session, t_grid, cfg.apnea_win_sec, 2);
    end

    if belt.available
        % irregular breathing features
        irregular_input = struct('ok', true, 'peak_t', belt.peak_t, 'ibi', belt.ibi);
        [belt.irregularity.window_mask, belt.irregularity.cov, ...
            belt.irregularity.robust_cov, belt.irregularity.endpoint_mask] = compute_irregularity_metrics( ...
                irregular_input, t_grid, cfg.irregularity_win_sec, cfg.cov_thr);

        % slow breathing features
        belt.rate_slow_endpoint_mask = isfinite(belt.rate_slow_window_bpm) & belt.rate_slow_window_bpm <= cfg.slow_rr_threshold;
        belt.rate_slow_state_mask = analysis_window_endpoints_to_state_mask(belt.rate_slow_endpoint_mask, t_grid, cfg.slow_win_sec);
        % rapid breathing features
        belt.rate_rapid_endpoint_mask = isfinite(belt.rate_rapid_window_bpm) & belt.rate_rapid_window_bpm >= cfg.rapid_rr_threshold;
        belt.rate_rapid_state_mask = analysis_window_endpoints_to_state_mask(belt.rate_rapid_endpoint_mask, t_grid, cfg.rapid_win_sec);
    end
end

function balance = build_thoracoabdominal_balance(lungs, diaph, t_grid, cfg)
% BUILD_THORACOABDOMINAL_BALANCE Compare normalized belt amplitudes in trailing windows.
% lungs and diaph provide breath times and session-normalized amplitudes;
% t_grid is in seconds. balance fields include availability and configured
% window/minimum/threshold metadata; per-grid belt medians; thoracic-to-
% abdominal ratio, log ratio, and thoracic fraction; and dominance endpoint,
% back-projected state, and compatibility masks.

    balance = struct( ...
        'available', false, ...
        'analysis_window_sec', cfg.thoracic_balance_win_sec, ...
        'min_breaths_per_belt', cfg.thoracic_balance_min_breaths, ...
        'dominance_ratio_threshold', cfg.thoracic_dominance_ratio_thr, ...
        'thoracic_ratio_window_median', nan(size(t_grid)), ...
        'abdominal_ratio_window_median', nan(size(t_grid)), ...
        'thoracic_to_abdominal_ratio', nan(size(t_grid)), ...
        'thoracic_dominance_log_ratio', nan(size(t_grid)), ...
        'thoracic_relative_fraction', nan(size(t_grid)), ...
        'dominance_endpoint_mask', false(size(t_grid)), ...
        'dominance_state_mask', false(size(t_grid)), ...
        'dominance_mask', false(size(t_grid)));

    inputs_available = lungs.session_amplitude_available && ...
        diaph.session_amplitude_available;
    if ~inputs_available
        return;
    end

    for i = 1:numel(t_grid)
        window_end = t_grid(i);
        window_start = window_end - cfg.thoracic_balance_win_sec;
        if window_start < 0
            continue;
        end

        thoracic_values = values_in_window( ...
            lungs.peak_t, lungs.amp_ratio_session, window_start, window_end);
        abdominal_values = values_in_window( ...
            diaph.peak_t, diaph.amp_ratio_session, window_start, window_end);
        if numel(thoracic_values) < cfg.thoracic_balance_min_breaths || ...
                numel(abdominal_values) < cfg.thoracic_balance_min_breaths
            continue;
        end

        thoracic_median = median(thoracic_values, 'omitnan');
        abdominal_median = median(abdominal_values, 'omitnan');
        if ~isfinite(thoracic_median) || thoracic_median <= 0 || ...
                ~isfinite(abdominal_median) || abdominal_median <= 0
            continue;
        end

        ratio = thoracic_median / abdominal_median;
        balance.thoracic_ratio_window_median(i) = thoracic_median;
        balance.abdominal_ratio_window_median(i) = abdominal_median;
        balance.thoracic_to_abdominal_ratio(i) = ratio;
        balance.thoracic_dominance_log_ratio(i) = log(ratio);
        balance.thoracic_relative_fraction(i) = ...
            thoracic_median / (thoracic_median + abdominal_median);
        balance.dominance_endpoint_mask(i) = ...
            ratio >= cfg.thoracic_dominance_ratio_thr;
    end
    balance.available = any(isfinite(balance.thoracic_to_abdominal_ratio));
    balance.dominance_state_mask = analysis_window_endpoints_to_state_mask( ...
        balance.dominance_endpoint_mask, t_grid, cfg.thoracic_balance_win_sec);
    % Compatibility alias: dominance_mask denotes candidate support, not
    % delayed endpoint evidence or a precisely localized final state.
    balance.dominance_mask = balance.dominance_state_mask;
end

function values = values_in_window(peak_t, values, start_t, end_t)
% VALUES_IN_WINDOW Select positive finite breath values by peak time.
% peak_t (s) and values are aligned breath-level vectors; start_t/end_t are
% inclusive bounds in seconds. A length mismatch is an error.

    peak_t = peak_t(:);
    values = values(:);
    if numel(peak_t) ~= numel(values)
        error('MAGMA:RespFeatures:SizeMismatch', ...
            'peak_t and values must have equal lengths.');
    end
    in_window = peak_t >= start_t & peak_t <= end_t & ...
        isfinite(values) & values > 0;
    values = values(in_window);
end

function belt = empty_belt_evidence(t_grid)
% EMPTY_BELT_EVIDENCE Initialize all per-belt evidence fields on t_grid.
% Breath-level fields: peak_idx/peak_t (s), inter-peak trough_idx/trough_t
% (s), amp, amp_ratio_session/global, ibi (s), rr_bpm, and ibi_source/
% rr_source provenance.
% Availability fields distinguish timing, raw amplitude, and session/global
% normalized amplitude; reference fields store values, flags, and quality.
% Grid-level fields include slow/rapid rate traces and endpoint/state masks,
% apnea amplitude evidence, and irregularity cov/robust_cov traces. For
% irregularity, endpoint_mask marks qualifying trailing windows and window_mask
% is their back-projected union. Shallow/deep detection consumes breath-level
% ratios directly.

    belt = struct( ...
        'available', false, ...
        'amplitude_available', false, ...
        'session_amplitude_available', false, ...
        'global_amplitude_available', false, ...
        'ignored', false, ...
        'peak_idx', [], ...
        'peak_t', [], ...
        'trough_idx', [], ...
        'trough_t', [], ...
        'amp', [], ...
        'amp_ratio_session', [], ...
        'amp_ratio_global', [], ...
        'ibi', [], ...
        'rr_bpm', [], ...
        'ibi_source', '', ...
        'rr_source', '', ...
        'session_reference_value', NaN, ...
        'session_reference_available', false, ...
        'global_reference_value', NaN, ...
        'global_reference_available', false, ...
        'reference_quality', 'belt_unavailable', ...
        'rate_slow_window_bpm', nan(size(t_grid)), ...
        'rate_rapid_window_bpm', nan(size(t_grid)), ...
        'rate_slow_endpoint_mask', false(size(t_grid)), ...
        'rate_slow_state_mask', false(size(t_grid)), ...
        'rate_rapid_endpoint_mask', false(size(t_grid)), ...
        'rate_rapid_state_mask', false(size(t_grid)), ...
        'apnea_amp_ratio_session_window_median', nan(size(t_grid)), ...
        'apnea_amplitude_endpoint_mask', false(size(t_grid)), ...
        'apnea_amplitude_state_mask', false(size(t_grid)), ...
        'irregularity', struct( ...
            'window_mask', false(size(t_grid)), ...
            'endpoint_mask', false(size(t_grid)), ...
            'cov', nan(size(t_grid)), ...
            'robust_cov', nan(size(t_grid))));
end

function ratio = amplitude_ratio(amp, reference, reference_available)
% AMPLITUDE_RATIO Normalize positive breath amplitudes by one scalar reference.
% amp is breath-level in belt units; ratio is dimensionless and shape-matched.
% Unavailable/invalid references leave the output NaN.

    ratio = nan(size(amp));
    if ~reference_available || ~isscalar(reference) || ...
            ~isfinite(reference) || reference <= 0
        return;
    end
    valid = isfinite(amp) & amp > 0;
    ratio(valid) = amp(valid) ./ reference;
end

function trace = respiratory_rate_trace(peak_t, t_grid, win_sec)
% RESPIRATORY_RATE_TRACE Estimate trailing-window rate as 60/mean(IBI).
% peak_t contains breath times in seconds; t_grid is the output grid and
% win_sec is the full trailing-window duration. trace is breaths/min and
% requires at least three peaks (two positive IBIs) per complete window.

    trace = nan(size(t_grid));
    peak_t = peak_t(:);
    for i = 1:numel(t_grid)
        t = t_grid(i);
        lb = t - win_sec;
        if lb < 0
            continue;
        end
        idx = find(isfinite(peak_t) & peak_t >= lb & peak_t <= t);
        if numel(idx) < 3
            continue;
        end
        ibi = diff(peak_t(idx));
        ibi = ibi(isfinite(ibi) & ibi > 0);
        if numel(ibi) < 2
            continue;
        end
        mean_ibi = mean(ibi);
        if isfinite(mean_ibi) && mean_ibi > 0
            trace(i) = 60 / mean_ibi;
        end
    end
end

function [endpoint_mask, state_mask] = amplitude_threshold_mask( ...
    peak_t, ratio, t_grid, win_sec, threshold, min_breaths, direction)
% AMPLITUDE_THRESHOLD_MASK Apply an all-breath threshold in trailing windows.
% peak_t (s) and normalized ratio are aligned breath vectors. direction='le'
% requires all positive finite ratios <= threshold; direction='ge' requires
% all values finite and >= threshold. Full windows need min_breaths values.
% endpoint_mask marks passing ends; state_mask covers their source windows.

    direction = string(direction);
    if ~isscalar(direction) || ~any(direction == ["le" "ge"])
        error('MAGMA:RespFeatures:InvalidThresholdDirection', ...
            'direction must be ''le'' or ''ge''.');
    end
    direction = char(direction);

    endpoint_mask = false(size(t_grid));
    peak_t = peak_t(:);
    ratio = ratio(:);
    if numel(peak_t) ~= numel(ratio)
        error('MAGMA:RespFeatures:SizeMismatch', ...
            'peak_t and ratio must have equal lengths.');
    end
    for i = 1:numel(t_grid)
        t = t_grid(i);
        lb = t - win_sec;
        if lb < 0
            continue;
        end
        values = ratio(peak_t <= t & peak_t >= lb);
        if strcmp(direction, 'le')
            values = values(isfinite(values) & values > 0);
            passes_threshold = all(values <= threshold);
        else
            passes_threshold = all(isfinite(values) & values >= threshold);
        end
        endpoint_mask(i) = numel(values) >= min_breaths && passes_threshold;
    end
    state_mask = analysis_window_endpoints_to_state_mask(endpoint_mask, t_grid, win_sec);
end

function [raw_trace, ratio_trace] = amplitude_window_medians(peak_t, amp, ratio, t_grid, win_sec, min_breaths)
% AMPLITUDE_WINDOW_MEDIANS Compute raw and normalized breath medians on t_grid.
% peak_t (s), amp (belt units), and ratio (dimensionless) are aligned breath
% vectors. Each full trailing win_sec window needs min_breaths positive finite
% values independently for raw_trace and ratio_trace.

    raw_trace = nan(size(t_grid));
    ratio_trace = nan(size(t_grid));
    peak_t = peak_t(:);
    amp = amp(:);
    ratio = ratio(:);
    if numel(peak_t) ~= numel(amp) || numel(peak_t) ~= numel(ratio)
        error('MAGMA:RespFeatures:SizeMismatch', ...
            'peak_t, amp, and ratio must have equal lengths.');
    end
    for i = 1:numel(t_grid)
        t = t_grid(i);
        lb = t - win_sec;
        if lb < 0
            continue;
        end
        in_window = peak_t >= lb & peak_t <= t;
        raw_values = amp(in_window);
        ratio_values = ratio(in_window);
        valid_raw = isfinite(raw_values) & raw_values > 0;
        if nnz(valid_raw) >= min_breaths
            raw_trace(i) = median(raw_values(valid_raw), 'omitnan');
        end
        valid_ratio = isfinite(ratio_values) & ratio_values > 0;
        if nnz(valid_ratio) >= min_breaths
            ratio_trace(i) = median(ratio_values(valid_ratio), 'omitnan');
        end
    end
end

function [values, source_name] = interval_values(source, field_name, peak_idx, peak_t, fs)
% INTERVAL_VALUES Obtain an interval vector or derive it from adjacent peaks.
% source is a cycle struct and field_name is normally 'ibi'. If absent,
% aligned peak_idx and fs are preferred over peak_t; values are seconds and
% source_name records the chosen provenance.

    values = get_field(source, field_name, []);
    source_name = 'resp_cycles';
    if isempty(values) && numel(peak_t) >= 2
        if numel(peak_idx) == numel(peak_t)
            values = diff(peak_idx(:)) / fs;
            source_name = 'derived_from_cycle_peak_idx';
        else
            values = diff(peak_t(:));
            source_name = 'derived_from_cycle_peak_t';
        end
    end
    values = values(:);
end

function [values, source_name] = rate_values(source, ibi)
% RATE_VALUES Obtain breathwise RR or derive 60/IBI.
% source may provide rr_bpm; otherwise ibi is an interval vector in seconds.
% values are breaths/min and source_name records whether values were derived.

    values = get_field(source, 'rr_bpm', []);
    source_name = 'resp_cycles';
    if isempty(values) && ~isempty(ibi)
        values = 60 ./ ibi;
        source_name = 'derived_from_cycle_ibi';
    end
    values = values(:);
end

function validate_available_alignment(belt)
% VALIDATE_AVAILABLE_ALIGNMENT Enforce aligned peak, trough, IBI, and RR evidence.
% Checks apply only when the belt's timing evidence is marked available. Each
% supplied trough must correspond to, and lie inside, one adjacent peak pair.

    if ~belt.available
        return;
    end
    n_peaks = numel(belt.peak_t);
    if ~isempty(belt.peak_idx) && numel(belt.peak_idx) ~= n_peaks
        error('MAGMA:PhysFeat:PeakAlignment', ...
            'Respiratory-cycle peak_idx and peak_t must have equal lengths.');
    end
    if numel(belt.ibi) ~= n_peaks - 1 || numel(belt.rr_bpm) ~= n_peaks - 1
        error('MAGMA:PhysFeat:IntervalAlignment', ...
            'IBI and RR must each have length numel(peak_t)-1.');
    end
    if ~isempty(belt.trough_t) && numel(belt.trough_t) ~= n_peaks - 1
        error('MAGMA:PhysFeat:TroughTimeAlignment', ...
            'Respiratory-cycle trough_t must have length numel(peak_t)-1.');
    end
    if ~isempty(belt.trough_idx) && numel(belt.trough_idx) ~= n_peaks - 1
        error('MAGMA:PhysFeat:TroughIndexAlignment', ...
            'Respiratory-cycle trough_idx must have length numel(peak_t)-1.');
    end
    if ~isempty(belt.trough_t)
        finite_trough = isfinite(belt.trough_t);
        between_peaks = belt.peak_t(1:end-1) < belt.trough_t & ...
            belt.trough_t < belt.peak_t(2:end);
        if any(finite_trough & ~between_peaks)
            error('MAGMA:PhysFeat:TroughTimeOrder', ...
                ['Each finite trough_t(i) must lie strictly between ' ...
                 'peak_t(i) and peak_t(i+1).']);
        end
    end
    if ~isempty(belt.peak_idx) && ~isempty(belt.trough_idx)
        between_peak_indices = belt.peak_idx(1:end-1) < belt.trough_idx & ...
            belt.trough_idx < belt.peak_idx(2:end);
        if any(~between_peak_indices)
            error('MAGMA:PhysFeat:TroughIndexOrder', ...
                ['Each trough_idx(i) must lie strictly between ' ...
                 'peak_idx(i) and peak_idx(i+1).']);
        end
    end
end

function varargout = reference_value(reference, kind)
% REFERENCE_VALUE Read a usable session or global amplitude reference.
% reference is one belt reference struct and kind selects its nested part.
% Outputs are positive scalar value, availability flag, and reference quality;
% callers may request only the leading outputs.

    value = NaN;
    available = false;
    quality = 'belt_unavailable';
    if isstruct(reference) && isfield(reference, 'reference_quality')
        quality = char(string(reference.reference_quality));
    end
    if isstruct(reference) && isfield(reference, kind) && ...
            isstruct(reference.(kind))
        part = reference.(kind);
        if isfield(part, 'value') && isfield(part, 'available') && part.available
            value = part.value;
            available = isscalar(value) && isfinite(value) && value > 0;
        end
    end
    if ~available
        value = NaN;
    end
    varargout = {value, available, quality};
    varargout = varargout(1:nargout);
end

function value = get_field(source, name, default_value)
% GET_FIELD Read a struct field, falling back when the struct or field is absent.

    value = default_value;
    if isstruct(source) && isfield(source, name)
        value = source.(name);
    end
end

function value = get_belt(source, name)
% GET_BELT Read a named belt struct, returning an empty struct when absent.

    value = struct();
    if isstruct(source) && isfield(source, name)
        value = source.(name);
    end
end

function cfg = evidence_config(config)
% EVIDENCE_CONFIG Resolve respiratory windows and thresholds with defaults.
% cfg contains label-specific durations (s), RR thresholds (breaths/min),
% normalized amplitude criteria, irregular CoV threshold, and thoracic-balance
% window, minimum-breath, and dominance-ratio settings.

    cfg = struct();
    cfg.slow_win_sec = get_config_value(config, 'slow', 'analysis_win_sec', 60);
    cfg.rapid_win_sec = get_config_value(config, 'rapid', 'analysis_win_sec', 60);
    cfg.apnea_win_sec = get_config_value(config, 'apnea', 'amp_analysis_win_sec', 10);
    cfg.apnea_ratio_threshold = get_config_value(config, 'apnea', 'amp_ratio_thr', 0.10);
    cfg.slow_rr_threshold = get_config_value(config, 'slow', 'rr_thr_bpm', 10);
    cfg.rapid_rr_threshold = get_config_value(config, 'rapid', 'rr_thr_bpm', 20);
    cfg.shallow_lo_ratio = get_config_value(config, 'shallow', 'amp_ratio_low', 0.65);
    cfg.shallow_hi_ratio = get_config_value(config, 'shallow', 'amp_ratio_high', 0.80);
    cfg.deep_ratio_threshold = get_config_value(config, 'deep', 'amp_ratio_thr', 1.20);
    cfg.irregularity_win_sec = get_config_value(config, 'irregular', 'analysis_win_sec', 60);
    cfg.cov_thr = get_config_value(config, 'irregular', 'cov_thr', 0.3);
    cfg.thoracic_balance_win_sec = get_config_value(config, 'thoracic', 'analysis_win_sec', 30);
    cfg.thoracic_balance_min_breaths = get_config_value(config, 'thoracic', 'min_breaths', 3);
    cfg.thoracic_dominance_ratio_thr = get_config_value(config, 'thoracic', 'dominance_ratio_thr', 1.5);
end
