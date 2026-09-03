function phys_feat = compute_physiological_features(data, resp_feat, resp_ref, spo2_feat, config)
% compute_physiological_features
% Build a modest common physiological evidence layer from reviewed breaths.
% This function does not detect peaks and does not create labels or events.
%
% Alignment convention:
%   peak_idx(i), peak_t(i), and amp(i) are peak-based. amp(i) is the
%   excursion from peak i to the trough before peak i+1, so the final amp
%   may be NaN. ibi(i) and rr_bpm(i) describe peak i -> peak i+1 and have
%   length numel(peak_t)-1.

    N = size(data, 1);
    t_grid = (0:config.grid_step_sec:(N-1)/config.fs)';
    cfg = evidence_config(config);

    phys_feat = struct();
    phys_feat.version = 'independent_physiological_evidence_v4';
    phys_feat.provenance = struct( ...
        'breath_source', 'reviewed_resp_feat', ...
        'respiratory_reference_source', 'resp_ref', ...
        'spo2_source', 'spo2_feat', ...
        'reference_interval_source', 'common_session_reference_interval', ...
        'redetected_respiratory_peaks', false, ...
        'respiratory_rate_estimator', ...
            '60_over_mean_complete_ibi_in_full_trailing_window', ...
        'version_changes', ['v4: Slow and Rapid use 60-second confirmation windows ' ...
            'with respiratory rate equal to 60/mean(IBI); v3 introduced one common ' ...
            'session-reference interval and modality-specific reference statistics']);

    phys_feat.resp = struct();
    phys_feat.resp.time_sec = t_grid;
    phys_feat.resp.grid_step_sec = config.grid_step_sec;
    phys_feat.resp.alignment_convention = [ ...
        'peak-based amp(i) belongs to peak i; final amp may be NaN; ' ...
        'ibi(i) and rr_bpm(i) describe peak i to peak i+1'];
    phys_feat.resp.rate_windows_sec = struct( ...
        'slow', cfg.slow_win_sec, 'rapid', cfg.rapid_win_sec);
    phys_feat.resp.amplitude_windows_sec = struct( ...
        'shallow', cfg.shallow_win_sec, ...
        'deep', cfg.deep_win_sec, ...
        'apnea', cfg.apnea_win_sec);
    phys_feat.resp.shallow_band_ratio = [cfg.shallow_lo_ratio cfg.shallow_hi_ratio];
    phys_feat.resp.deep_ratio_threshold = cfg.deep_ratio_threshold;
    phys_feat.resp.temporal_semantics = struct( ...
        'evidence_endpoint', 'qualifying trailing analysis window ending at this time', ...
        'candidate_support', 'union of support intervals used only to confirm sustained evidence', ...
        'localized_state', ['detector-specific boundary refinement from reviewed breaths or raw ' ...
            'samples; aggregate windows are not assumed to be exact state intervals'], ...
        'final_state', ['localized shallow, deep, slow, or rapid run retained only when its ' ...
            'localized duration meets the configured final minimum'], ...
        'minimum_event_duration', ['for shallow, deep, slow, and rapid, the configured minimum ' ...
            'duration is applied once to each localized qualifying run; short localized runs ' ...
            'remain QC evidence and are not final labels'], ...
        'uncertain_boundaries', ['irregularity and thoracic dominance retain candidate support ' ...
            'with explicit window-scale uncertainty when no non-arbitrary localizer exists']);

    lungs_ignored = is_lung_belt_ignored(config);
    phys_feat.resp.lungs = build_belt_evidence( ...
        get_belt(resp_feat, 'lungs'), get_belt(resp_ref, 'lungs'), ...
        lungs_ignored, t_grid, cfg, config);
    phys_feat.resp.diaph = build_belt_evidence( ...
        get_belt(resp_feat, 'diaph'), get_belt(resp_ref, 'diaph'), ...
        false, t_grid, cfg, config);
    phys_feat.resp.belt_availability = struct( ...
        'lungs', phys_feat.resp.lungs.available, ...
        'diaph', phys_feat.resp.diaph.available);
    phys_feat.resp.both_belts_available = ...
        phys_feat.resp.lungs.available && phys_feat.resp.diaph.available;
    phys_feat.resp.thoracoabdominal_balance = build_thoracoabdominal_balance( ...
        phys_feat.resp.lungs, phys_feat.resp.diaph, t_grid, cfg);

    phys_feat.spo2 = build_spo2_evidence(spo2_feat);
end

function belt = build_belt_evidence(source, reference, ignored, t_grid, cfg, config)
    belt = empty_belt_evidence(t_grid);
    belt.ignored = logical(ignored);
    if ~isstruct(source)
        return;
    end

    % Direct provenance fields: preserve the reviewed arrays and their
    % trailing-NaN convention exactly as supplied by resp_feat.
    belt.peak_idx = get_field(source, 'peak_idx', []);
    belt.peak_t = get_field(source, 'peak_t', []);
    belt.amp = get_field(source, 'amp', []);
    belt.peak_idx = belt.peak_idx(:);
    belt.peak_t = belt.peak_t(:);
    belt.amp = belt.amp(:);

    belt.available = is_valid_breath_signal(source, false) && ~belt.ignored;
    belt.amplitude_available = is_valid_breath_signal(source, true) && belt.available;

    [belt.ibi, belt.ibi_source] = interval_values( ...
        source, 'ibi', belt.peak_idx, belt.peak_t, config.fs);
    [belt.rr_bpm, belt.rr_source] = rate_values(source, belt.ibi);
    validate_available_alignment(belt);

    [belt.session_reference_value, belt.session_reference_available, ...
        belt.reference_quality] = reference_value(reference, 'session');
    [belt.global_reference_value, belt.global_reference_available] = ...
        reference_value(reference, 'global');
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
    belt.session_amplitude_available = belt.amplitude_available && ...
        belt.session_reference_available;
    belt.global_amplitude_available = belt.amplitude_available && ...
        belt.global_reference_available;

    if belt.available
        belt.rate_slow_window_bpm = breath_rate_trace( ...
            belt.peak_t, t_grid, cfg.slow_win_sec);
        belt.rate_rapid_window_bpm = breath_rate_trace( ...
            belt.peak_t, t_grid, cfg.rapid_win_sec);
    end

    if belt.session_amplitude_available
        [belt.shallow_amplitude_endpoint_mask, belt.shallow_amplitude_mask] = amplitude_band_mask( ...
            belt.peak_t, belt.amp_ratio_session, t_grid, cfg.shallow_win_sec, ...
            cfg.shallow_lo_ratio, cfg.shallow_hi_ratio);
        [belt.deep_amplitude_endpoint_mask, belt.deep_amplitude_mask] = amplitude_threshold_mask( ...
            belt.peak_t, belt.amp_ratio_session, t_grid, cfg.deep_win_sec, ...
            cfg.deep_ratio_threshold);
        [belt.amp_window_median_raw_units, belt.amp_ratio_session_window_median] = ...
            amplitude_window_medians(belt.peak_t, belt.amp, ...
            belt.amp_ratio_session, t_grid, cfg.shallow_win_sec, 1);
        [~, belt.deep_amp_ratio_session_window_median] = ...
            amplitude_window_medians(belt.peak_t, belt.amp, ...
            belt.amp_ratio_session, t_grid, cfg.deep_win_sec, 1);
        [~, belt.apnea_amp_ratio_session_window_median] = ...
            amplitude_window_medians(belt.peak_t, belt.amp, ...
            belt.amp_ratio_session, t_grid, cfg.apnea_win_sec, 2);
        [belt.apnea_amplitude_endpoint_mask, ...
            belt.apnea_amplitude_state_mask] = amplitude_all_le_mask( ...
            belt.peak_t, belt.amp_ratio_session, t_grid, ...
            cfg.apnea_win_sec, cfg.apnea_ratio_threshold, 2);
    elseif belt.amplitude_available
        [belt.amp_window_median_raw_units, ~] = amplitude_window_medians( ...
            belt.peak_t, belt.amp, belt.amp_ratio_session, ...
            t_grid, cfg.shallow_win_sec, 1);
    end

    if belt.available
        irregular_input = struct('ok', true, 'peak_t', belt.peak_t, 'ibi', belt.ibi);
        [belt.irregularity.window_mask, belt.irregularity.cov, ...
            belt.irregularity.robust_cov, belt.irregularity.rmssd_sec, ...
            belt.irregularity.endpoint_mask, ...
            belt.irregularity.pause_exclusion_mask] = compute_irregularity_metrics( ...
            irregular_input, t_grid, cfg.irregularity_win_sec, cfg.cov_thr, ...
            cfg.robust_cov_thr, cfg.rmssd_thr, cfg.pause_thr_sec, ...
            cfg.detection_metric);
        belt.rate_slow_endpoint_mask = isfinite(belt.rate_slow_window_bpm) & ...
            belt.rate_slow_window_bpm <= cfg.slow_rr_threshold;
        belt.rate_slow_state_mask = analysis_window_endpoints_to_state_mask( ...
            belt.rate_slow_endpoint_mask, t_grid, cfg.slow_win_sec);
        belt.rate_rapid_endpoint_mask = isfinite(belt.rate_rapid_window_bpm) & ...
            belt.rate_rapid_window_bpm >= cfg.rapid_rr_threshold;
        belt.rate_rapid_state_mask = analysis_window_endpoints_to_state_mask( ...
            belt.rate_rapid_endpoint_mask, t_grid, cfg.rapid_win_sec);
    end
end

function spo2 = build_spo2_evidence(spo2_feat)
    spo2 = struct( ...
        'available', false, ...
        'signal_available', false, ...
        'reference_available', false, ...
        'reference_quality', 'not_evaluated', ...
        'desaturation_events', empty_events());
    if ~isstruct(spo2_feat)
        return;
    end
    if isfield(spo2_feat, 'spo2')
        x = spo2_feat.spo2(:);
        spo2.signal_available = nnz(isfinite(x)) >= 2;
    end
    if isfield(spo2_feat, 'signal_available')
        spo2.signal_available = logical(spo2_feat.signal_available);
    end
    if isfield(spo2_feat, 'reference_available')
        spo2.reference_available = logical(spo2_feat.reference_available);
    end
    if isfield(spo2_feat, 'reference_quality')
        spo2.reference_quality = char(string(spo2_feat.reference_quality));
    end
    if isfield(spo2_feat, 'detection_available')
        spo2.available = logical(spo2_feat.detection_available);
    else
        spo2.available = false;
    end
    if isfield(spo2_feat, 'desat_events')
        spo2.desaturation_events = spo2_feat.desat_events;
    end
end

function balance = build_thoracoabdominal_balance(lungs, diaph, t_grid, cfg)
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
    [peak_t, values] = paired_peak_values(peak_t, values);
    in_window = peak_t >= start_t & peak_t <= end_t & ...
        isfinite(values) & values > 0;
    values = values(in_window);
end

function belt = empty_belt_evidence(t_grid)
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
            'robust_cov', nan(size(t_grid)), ...
            'rmssd_sec', nan(size(t_grid)), ...
            'pause_exclusion_mask', false(size(t_grid))));
end

function ratio = amplitude_ratio(amp, reference, reference_available)
    ratio = nan(size(amp));
    if ~reference_available || ~isscalar(reference) || ...
            ~isfinite(reference) || reference <= 0
        return;
    end
    valid = isfinite(amp) & amp > 0;
    ratio(valid) = amp(valid) ./ reference;
end

function trace = breath_rate_trace(peak_t, t_grid, win_sec)
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

function [endpoint_mask, state_mask] = amplitude_all_le_mask( ...
    peak_t, ratio, t_grid, win_sec, threshold, min_breaths)

    endpoint_mask = false(size(t_grid));
    [peak_t, ratio] = paired_peak_values(peak_t, ratio);
    for i = 1:numel(t_grid)
        t = t_grid(i);
        lb = t - win_sec;
        if lb < 0
            continue;
        end
        values = ratio(peak_t >= lb & peak_t <= t);
        values = values(isfinite(values) & values > 0);
        endpoint_mask(i) = numel(values) >= min_breaths && ...
            all(values <= threshold);
    end
    state_mask = analysis_window_endpoints_to_state_mask( ...
        endpoint_mask, t_grid, win_sec);
end

function [endpoint_mask, state_mask] = amplitude_band_mask(peak_t, ratio, t_grid, win_sec, r_lo, r_hi)
    endpoint_mask = false(size(t_grid));
    [peak_t, ratio] = paired_peak_values(peak_t, ratio);
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

function [endpoint_mask, state_mask] = amplitude_threshold_mask(peak_t, ratio, t_grid, win_sec, threshold)
    endpoint_mask = false(size(t_grid));
    [peak_t, ratio] = paired_peak_values(peak_t, ratio);
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
        if all(isfinite(values) & values >= threshold)
            endpoint_mask(i) = true;
        end
    end
    state_mask = analysis_window_endpoints_to_state_mask(endpoint_mask, t_grid, win_sec);
end

function [raw_trace, ratio_trace] = amplitude_window_medians( ...
    peak_t, amp, ratio, t_grid, win_sec, min_breaths)

    raw_trace = nan(size(t_grid));
    ratio_trace = nan(size(t_grid));
    [peak_t, amp, ratio] = paired_peak_values(peak_t, amp, ratio);
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

function [varargout] = paired_peak_values(peak_t, varargin)
    n = numel(peak_t);
    for i = 1:numel(varargin)
        n = min(n, numel(varargin{i}));
    end
    varargout = cell(1, numel(varargin) + 1);
    varargout{1} = peak_t(1:n);
    for i = 1:numel(varargin)
        values = varargin{i};
        varargout{i+1} = values(1:n);
    end
end

function [values, source_name] = interval_values(source, field_name, peak_idx, peak_t, fs)
    values = get_field(source, field_name, []);
    source_name = 'resp_feat';
    if isempty(values) && numel(peak_t) >= 2
        if numel(peak_idx) == numel(peak_t)
            values = diff(peak_idx(:)) / fs;
            source_name = 'derived_from_reviewed_peak_idx';
        else
            values = diff(peak_t(:));
            source_name = 'derived_from_reviewed_peak_t';
        end
    end
    values = values(:);
end

function [values, source_name] = rate_values(source, ibi)
    values = get_field(source, 'rr_bpm', []);
    source_name = 'resp_feat';
    if isempty(values) && ~isempty(ibi)
        values = 60 ./ ibi;
        source_name = 'derived_from_reviewed_ibi';
    end
    values = values(:);
end

function validate_available_alignment(belt)
    if ~belt.available
        return;
    end
    n_peaks = numel(belt.peak_t);
    if ~isempty(belt.peak_idx) && numel(belt.peak_idx) ~= n_peaks
        error('MAGMA:PhysFeat:PeakAlignment', ...
            'Reviewed peak_idx and peak_t must have equal lengths.');
    end
    if numel(belt.ibi) ~= n_peaks - 1 || numel(belt.rr_bpm) ~= n_peaks - 1
        error('MAGMA:PhysFeat:IntervalAlignment', ...
            'IBI and RR must each have length numel(peak_t)-1.');
    end
end

function varargout = reference_value(reference, kind)
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
    value = default_value;
    if isstruct(source) && isfield(source, name)
        value = source.(name);
    end
end

function value = get_belt(source, name)
    value = struct();
    if isstruct(source) && isfield(source, name)
        value = source.(name);
    end
end

function cfg = evidence_config(config)
    cfg = struct();
    cfg.slow_win_sec = get_config_value(config, 'SlB', 'analysis_win_sec', 60);
    cfg.rapid_win_sec = get_config_value(config, 'RaB', 'analysis_win_sec', 60);
    cfg.shallow_win_sec = get_config_value(config, 'ShB', 'analysis_win_sec', 30);
    cfg.deep_win_sec = get_config_value(config, 'DeB', 'analysis_win_sec', 30);
    cfg.apnea_win_sec = get_config_value(config, 'Apn', 'amp_analysis_win_sec', 10);
    cfg.apnea_ratio_threshold = get_config_value(config, 'Apn', 'amp_ratio_thr', 0.10);
    cfg.slow_rr_threshold = get_config_value(config, 'SlB', 'rr_thr_bpm', 10);
    cfg.rapid_rr_threshold = get_config_value(config, 'RaB', 'rr_thr_bpm', 20);
    cfg.shallow_lo_ratio = get_config_value(config, 'ShB', 'amp_ratio_low', 0.65);
    cfg.shallow_hi_ratio = get_config_value(config, 'ShB', 'amp_ratio_high', 0.80);
    cfg.deep_ratio_threshold = get_config_value(config, 'DeB', 'amp_ratio_thr', 1.20);
    cfg.irregularity_win_sec = get_config_value(config, 'IrB', 'analysis_win_sec', 60);
    cfg.cov_thr = get_config_value(config, 'IrB', 'cov_thr', 0.3);
    cfg.robust_cov_thr = get_config_value(config, 'IrB', 'robust_cov_thr', 0.25);
    cfg.rmssd_thr = get_config_value(config, 'IrB', 'rmssd_thr', 0.0);
    cfg.pause_thr_sec = get_config_value(config, 'IrB', 'pause_thr_sec', 10);
    cfg.detection_metric = get_config_value(config, 'IrB', 'detection_metric', 'cov');
    cfg.thoracic_balance_win_sec = get_config_value(config, 'TDB', 'analysis_win_sec', 30);
    cfg.thoracic_balance_min_breaths = get_config_value(config, 'TDB', 'min_breaths', 3);
    cfg.thoracic_dominance_ratio_thr = get_config_value(config, 'TDB', 'dominance_ratio_thr', 1.5);
end
