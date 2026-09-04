function resp_features = compute_respiratory_features(data, resp_cycles, resp_ref, config)
% COMPUTE_RESPIRATORY_FEATURES Compute respiratory features.
%
% Syntax:
%   resp_features = compute_respiratory_features(data, resp_cycles, resp_ref, config)
%
% Inputs:
%   data - Input physiological signal data.
%   resp_cycles - Respiratory-cycle structure.
%   resp_ref - Respiratory-reference structure.
%   config - Pipeline configuration structure.
%
% Outputs:
%   resp_features - Respiratory-feature structure.

    N = size(data, 1);
    t_grid = (0:config.grid_step_sec:(N-1)/config.fs)';
    cfg = evidence_config(config);

    resp_features = struct();
    resp_features.resp = struct();
    resp_features.resp.time_sec = t_grid;
    resp_features.resp.grid_step_sec = config.grid_step_sec;
    resp_features.resp.rate_windows_sec = struct( ...
        'slow', cfg.slow_win_sec, 'rapid', cfg.rapid_win_sec);
    resp_features.resp.amplitude_windows_sec = struct( ...
        'shallow', cfg.shallow_win_sec, ...
        'deep', cfg.deep_win_sec, ...
        'apnea', cfg.apnea_win_sec);
    resp_features.resp.shallow_band_ratio = [cfg.shallow_lo_ratio cfg.shallow_hi_ratio];
    resp_features.resp.deep_ratio_threshold = cfg.deep_ratio_threshold;

    % compute on individual belts 
    lungs_ignored = is_lung_belt_ignored(config);
    resp_features.resp.lungs = build_belt_evidence( ...
        get_belt(resp_cycles, 'lungs'), get_belt(resp_ref, 'lungs'), lungs_ignored, t_grid, cfg, config);
    resp_features.resp.diaph = build_belt_evidence( ...
        get_belt(resp_cycles, 'diaph'), get_belt(resp_ref, 'diaph'), false, t_grid, cfg, config);

    % compute on both belts 
    resp_features.resp.belt_availability = struct( ...
        'lungs', resp_features.resp.lungs.available, 'diaph', resp_features.resp.diaph.available);
    resp_features.resp.both_belts_available = resp_features.resp.lungs.available && resp_features.resp.diaph.available;
    resp_features.resp.thoracoabdominal_balance = build_thoracoabdominal_balance(resp_features.resp.lungs, resp_features.resp.diaph, t_grid, cfg);
end

function belt = build_belt_evidence(source, reference, ignored, t_grid, cfg, config)
% BUILD_BELT_EVIDENCE Build belt evidence.
%
% Syntax:
%   belt = build_belt_evidence(source, reference, ignored, t_grid, cfg, config)
%
% Inputs:
%   source - Input value `source`.
%   reference - Session-reference metadata.
%   ignored - Input value `ignored`.
%   t_grid - Time coordinates in seconds.
%   cfg - Pipeline configuration structure.
%   config - Pipeline configuration structure.
%
% Outputs:
%   belt - Updated respiratory-cycle or belt structure.

    belt = empty_belt_evidence(t_grid);
    belt.ignored = logical(ignored);
    if ~isstruct(source)
        return;
    end

    % Preserve cycle alignment from resp_cycles: amp(i) belongs to peak i
    % (the final amplitude may be NaN), while ibi(i) and rr_bpm(i) span
    % peak i to peak i+1.
    belt.peak_idx = get_field(source, 'peak_idx', []);
    belt.peak_t = get_field(source, 'peak_t', []);
    belt.amp = get_field(source, 'amp', []);
    belt.peak_idx = belt.peak_idx(:);
    belt.peak_t = belt.peak_t(:);
    belt.amp = belt.amp(:);

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
        % All-breath criterion: every valid breath in the window must satisfy the threshold.
        % for shallow breathing
        % [belt.shallow_amplitude_endpoint_mask, belt.shallow_amplitude_mask] = amplitude_band_mask( ...
        %     belt.peak_t, belt.amp_ratio_session, t_grid, cfg.shallow_win_sec, cfg.shallow_lo_ratio, cfg.shallow_hi_ratio);
        [belt.shallow_amplitude_endpoint_mask, belt.shallow_amplitude_mask] = amplitude_threshold_mask( ...
            belt.peak_t, belt.amp_ratio_session, t_grid, cfg.shallow_win_sec, cfg.shallow_hi_ratio, 3, 'le');
        % deep breathing
        [belt.deep_amplitude_endpoint_mask, belt.deep_amplitude_mask] = amplitude_threshold_mask( ...
            belt.peak_t, belt.amp_ratio_session, t_grid, cfg.deep_win_sec, cfg.deep_ratio_threshold, 3, 'ge');
        % apnea
        [belt.apnea_amplitude_endpoint_mask, belt.apnea_amplitude_state_mask] = amplitude_threshold_mask( ...
            belt.peak_t, belt.amp_ratio_session, t_grid, cfg.apnea_win_sec, cfg.apnea_ratio_threshold, 2, 'le');

        % Window-summary criterion  (more soft but more robust to normal breath-to-breath variability)
        % shallow breathing 
        [belt.amp_window_median_raw_units, belt.amp_ratio_session_window_median] = amplitude_window_medians( ...
            belt.peak_t, belt.amp, belt.amp_ratio_session, t_grid, cfg.shallow_win_sec, 3);
        % deep breathing
        [~, belt.deep_amp_ratio_session_window_median] = amplitude_window_medians( ...
            belt.peak_t, belt.amp, belt.amp_ratio_session, t_grid, cfg.deep_win_sec, 3);
        % apnea
        [~, belt.apnea_amp_ratio_session_window_median] = amplitude_window_medians( ...
            belt.peak_t, belt.amp, belt.amp_ratio_session, t_grid, cfg.apnea_win_sec, 2);

    elseif belt.amplitude_available % (for when we have valid breath amplitudes, BUT no usable session reference.)
        [belt.amp_window_median_raw_units, ~] = amplitude_window_medians( ...
            belt.peak_t, belt.amp, belt.amp_ratio_session, t_grid, cfg.shallow_win_sec, 3);
    end

    if belt.available
        % irregular breathing features
        irregular_input = struct('ok', true, 'peak_t', belt.peak_t, 'ibi', belt.ibi);
        [belt.irregularity.window_mask, belt.irregularity.cov, ...
            belt.irregularity.robust_cov, belt.irregularity.endpoint_mask] = ...
            compute_irregularity_metrics( ...
                irregular_input, t_grid, cfg.irregularity_win_sec, cfg.cov_thr);

        % slow and rapid breathing features
        belt.rate_slow_endpoint_mask = isfinite(belt.rate_slow_window_bpm) & belt.rate_slow_window_bpm <= cfg.slow_rr_threshold;
        belt.rate_slow_state_mask = analysis_window_endpoints_to_state_mask(belt.rate_slow_endpoint_mask, t_grid, cfg.slow_win_sec);
        belt.rate_rapid_endpoint_mask = isfinite(belt.rate_rapid_window_bpm) & belt.rate_rapid_window_bpm >= cfg.rapid_rr_threshold;
        belt.rate_rapid_state_mask = analysis_window_endpoints_to_state_mask(belt.rate_rapid_endpoint_mask, t_grid, cfg.rapid_win_sec);
    end
end

function balance = build_thoracoabdominal_balance(lungs, diaph, t_grid, cfg)
% BUILD_THORACOABDOMINAL_BALANCE Build thoracoabdominal balance.
%
% Syntax:
%   balance = build_thoracoabdominal_balance(lungs, diaph, t_grid, cfg)
%
% Inputs:
%   lungs - Respiratory-cycle or belt-evidence structure.
%   diaph - Respiratory-cycle or belt-evidence structure.
%   t_grid - Time coordinates in seconds.
%   cfg - Pipeline configuration structure.
%
% Outputs:
%   balance - Computed output value `balance`.

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
% VALUES_IN_WINDOW Perform the values in window operation.
%
% Syntax:
%   values = values_in_window(peak_t, values, start_t, end_t)
%
% Inputs:
%   peak_t - Input value `peak_t`.
%   values - Input value `values`.
%   start_t - Input value `start_t`.
%   end_t - Input value `end_t`.
%
% Outputs:
%   values - Computed numeric value.

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
% EMPTY_BELT_EVIDENCE Create an empty belt evidence value.
%
% Syntax:
%   belt = empty_belt_evidence(t_grid)
%
% Inputs:
%   t_grid - Time coordinates in seconds.
%
% Outputs:
%   belt - Updated respiratory-cycle or belt structure.

    belt = struct( ...
        'available', false, ...
        'amplitude_available', false, ...
        'session_amplitude_available', false, ...
        'global_amplitude_available', false, ...
        'ignored', false, ...
        'peak_idx', [], ...
        'peak_t', [], ...
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
        'amp_window_median_raw_units', nan(size(t_grid)), ...
        'amp_ratio_session_window_median', nan(size(t_grid)), ...
        'deep_amp_ratio_session_window_median', nan(size(t_grid)), ...
        'apnea_amp_ratio_session_window_median', nan(size(t_grid)), ...
        'shallow_amplitude_mask', false(size(t_grid)), ...
        'shallow_amplitude_endpoint_mask', false(size(t_grid)), ...
        'deep_amplitude_mask', false(size(t_grid)), ...
        'deep_amplitude_endpoint_mask', false(size(t_grid)), ...
        'apnea_amplitude_endpoint_mask', false(size(t_grid)), ...
        'apnea_amplitude_state_mask', false(size(t_grid)), ...
        'irregularity', struct( ...
            'window_mask', false(size(t_grid)), ...
            'endpoint_mask', false(size(t_grid)), ...
            'cov', nan(size(t_grid)), ...
            'robust_cov', nan(size(t_grid))));
end

function ratio = amplitude_ratio(amp, reference, reference_available)
% AMPLITUDE_RATIO Perform the amplitude ratio operation.
%
% Syntax:
%   ratio = amplitude_ratio(amp, reference, reference_available)
%
% Inputs:
%   amp - Input value `amp`.
%   reference - Session-reference metadata.
%   reference_available - Session-reference metadata.
%
% Outputs:
%   ratio - Computed numeric value.

    ratio = nan(size(amp));
    if ~reference_available || ~isscalar(reference) || ...
            ~isfinite(reference) || reference <= 0
        return;
    end
    valid = isfinite(amp) & amp > 0;
    ratio(valid) = amp(valid) ./ reference;
end

function trace = respiratory_rate_trace(peak_t, t_grid, win_sec)
% RESPIRATORY_RATE_TRACE - Perform the respiratory rate trace operation:
% RR = 60 / mean(IBI)
%
% Syntax:
%   trace = respiratory_rate_trace(peak_t, t_grid, win_sec)
%
% Inputs:
%   peak_t - Input value `peak_t`.
%   t_grid - Time coordinates in seconds.
%   win_sec - Duration or window length in seconds.
%
% Outputs:
%   trace - Computed output value `trace`.

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

function [endpoint_mask, state_mask] = amplitude_band_mask(peak_t, ratio, t_grid, win_sec, r_lo, r_hi)
% AMPLITUDE_BAND_MASK Perform the amplitude band mask operation.
%
% Syntax:
%   [endpoint_mask, state_mask] = amplitude_band_mask(peak_t, ratio, t_grid, win_sec, r_lo, r_hi)
%
% Inputs:
%   peak_t - Input value `peak_t`.
%   ratio - Input value `ratio`.
%   t_grid - Time coordinates in seconds.
%   win_sec - Duration or window length in seconds.
%   r_lo - Input value `r_lo`.
%   r_hi - Input value `r_hi`.
%
% Outputs:
%   endpoint_mask - Logical output mask.
%   state_mask - Logical output mask.

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
        if numel(values) < 3
            continue;
        end
        if all(isfinite(values) & values >= r_lo & values <= r_hi)
            endpoint_mask(i) = true;
        end
    end
    state_mask = analysis_window_endpoints_to_state_mask(endpoint_mask, t_grid, win_sec);
end

function [endpoint_mask, state_mask] = amplitude_threshold_mask( ...
    peak_t, ratio, t_grid, win_sec, threshold, min_breaths, direction)
% AMPLITUDE_THRESHOLD_MASK Perform the amplitude threshold mask operation.
%
% Syntax:
%   [endpoint_mask, state_mask] = amplitude_threshold_mask(peak_t, ratio, t_grid, win_sec, threshold, min_breaths, direction)
%
% Inputs:
%   peak_t - Input value `peak_t`.
%   ratio - Input value `ratio`.
%   t_grid - Time coordinates in seconds.
%   win_sec - Duration or window length in seconds.
%   threshold - Selection threshold value.
%   min_breaths - Minimum number of valid breaths in the window.
%   direction - Threshold direction: 'le' or 'ge'.
%
% Outputs:
%   endpoint_mask - Logical output mask.
%   state_mask - Logical output mask.

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
% AMPLITUDE_WINDOW_MEDIANS Perform the amplitude window medians operation.
% This function creates rolling median breathing-amplitude traces.
%
% Syntax:
%   [raw_trace, ratio_trace] = amplitude_window_medians(peak_t, amp, ratio, t_grid, win_sec, min_breaths)
%
% Inputs:
%   peak_t - Input value `peak_t`.
%   amp - Input value `amp`.
%   ratio - Input value `ratio`.
%   t_grid - Time coordinates in seconds.
%   win_sec - Duration or window length in seconds.
%   min_breaths - Input value `min_breaths`.
%
% Outputs:
%   raw_trace - Computed output value `raw_trace`.
%   ratio_trace - Computed numeric value.

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
% INTERVAL_VALUES Perform the interval values operation.
%
% Syntax:
%   [values, source_name] = interval_values(source, field_name, peak_idx, peak_t, fs)
%
% Inputs:
%   source - Input value `source`.
%   field_name - Input value `field_name`.
%   peak_idx - Input value `peak_idx`.
%   peak_t - Input value `peak_t`.
%   fs - Sampling frequency in hertz.
%
% Outputs:
%   values - Computed numeric value.
%   source_name - Output text or identifier.

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
% RATE_VALUES Perform the rate values operation.
%
% Syntax:
%   [values, source_name] = rate_values(source, ibi)
%
% Inputs:
%   source - Input value `source`.
%   ibi - Input value `ibi`.
%
% Outputs:
%   values - Computed numeric value.
%   source_name - Output text or identifier.

    values = get_field(source, 'rr_bpm', []);
    source_name = 'resp_cycles';
    if isempty(values) && ~isempty(ibi)
        values = 60 ./ ibi;
        source_name = 'derived_from_cycle_ibi';
    end
    values = values(:);
end

function validate_available_alignment(belt)
% VALIDATE_AVAILABLE_ALIGNMENT Validate available alignment.
%
% Syntax:
%   validate_available_alignment(belt)
%
% Inputs:
%   belt - Respiratory-cycle or belt-evidence structure.

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
end

function varargout = reference_value(reference, kind)
% REFERENCE_VALUE Perform the reference value operation.
%
% Syntax:
%   varargout = reference_value(reference, kind)
%
% Inputs:
%   reference - Session-reference metadata.
%   kind - Input value `kind`.
%
% Outputs:
%   varargout - Optional function outputs.

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
% GET_FIELD Return field.
%
% Syntax:
%   value = get_field(source, name, default_value)
%
% Inputs:
%   source - Input value `source`.
%   name - Input value `name`.
%   default_value - Input value `default_value`.
%
% Outputs:
%   value - Computed numeric value.

    value = default_value;
    if isstruct(source) && isfield(source, name)
        value = source.(name);
    end
end

function value = get_belt(source, name)
% GET_BELT Return belt.
%
% Syntax:
%   value = get_belt(source, name)
%
% Inputs:
%   source - Input value `source`.
%   name - Input value `name`.
%
% Outputs:
%   value - Computed numeric value.

    value = struct();
    if isstruct(source) && isfield(source, name)
        value = source.(name);
    end
end

function cfg = evidence_config(config)
% EVIDENCE_CONFIG Perform the evidence config operation.
%
% Syntax:
%   cfg = evidence_config(config)
%
% Inputs:
%   config - Pipeline configuration structure.
%
% Outputs:
%   cfg - Computed output value `cfg`.

    cfg = struct();
    cfg.slow_win_sec = get_config_value(config, 'slow', 'analysis_win_sec', 60);
    cfg.rapid_win_sec = get_config_value(config, 'rapid', 'analysis_win_sec', 60);
    cfg.shallow_win_sec = get_config_value(config, 'shallow', 'analysis_win_sec', 30);
    cfg.deep_win_sec = get_config_value(config, 'deep', 'analysis_win_sec', 30);
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
