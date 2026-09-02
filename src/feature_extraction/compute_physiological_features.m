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
    phys_feat.version = 'phase3_common_physiological_evidence_v1';
    phys_feat.provenance = struct( ...
        'breath_source', 'reviewed_resp_feat', ...
        'respiratory_reference_source', 'resp_ref', ...
        'spo2_source', 'spo2_feat', ...
        'redetected_respiratory_peaks', false);

    phys_feat.resp = struct();
    phys_feat.resp.time_sec = t_grid;
    phys_feat.resp.grid_step_sec = config.grid_step_sec;
    phys_feat.resp.alignment_convention = [ ...
        'peak-based amp(i) belongs to peak i; final amp may be NaN; ' ...
        'ibi(i) and rr_bpm(i) describe peak i to peak i+1'];
    phys_feat.resp.rate_windows_sec = struct( ...
        'slow', cfg.slow_win_sec, 'rapid', cfg.rapid_win_sec);
    phys_feat.resp.amplitude_windows_sec = struct( ...
        'state', cfg.amplitude_win_sec, 'apnea', cfg.apnea_win_sec);
    phys_feat.resp.shallow_band_ratio = [cfg.shallow_lo_ratio cfg.shallow_hi_ratio];
    phys_feat.resp.temporary_deep_band_ratio = [cfg.deep_lo_ratio cfg.deep_hi_ratio];

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
        belt.shallow_amplitude_mask = amplitude_band_mask( ...
            belt.peak_t, belt.amp_ratio_session, t_grid, cfg.amplitude_win_sec, ...
            cfg.shallow_lo_ratio, cfg.shallow_hi_ratio);
        % Temporary evidence for current subtype compatibility. Final Deep
        % label semantics are intentionally deferred to Phase 4.
        belt.deep_amplitude_mask = amplitude_band_mask( ...
            belt.peak_t, belt.amp_ratio_session, t_grid, cfg.amplitude_win_sec, ...
            cfg.deep_lo_ratio, cfg.deep_hi_ratio);
        [belt.amp_window_median_raw_units, belt.amp_ratio_session_window_median] = ...
            amplitude_window_medians(belt.peak_t, belt.amp, ...
            belt.amp_ratio_session, t_grid, cfg.amplitude_win_sec, 1);
        [~, belt.apnea_amp_ratio_session_window_median] = ...
            amplitude_window_medians(belt.peak_t, belt.amp, ...
            belt.amp_ratio_session, t_grid, cfg.apnea_win_sec, 2);
    elseif belt.amplitude_available
        [belt.amp_window_median_raw_units, ~] = amplitude_window_medians( ...
            belt.peak_t, belt.amp, belt.amp_ratio_session, ...
            t_grid, cfg.amplitude_win_sec, 1);
    end

    if belt.available
        irregular_input = struct('ok', true, 'peak_t', belt.peak_t, 'ibi', belt.ibi);
        [belt.irregularity.window_mask, belt.irregularity.cov, ...
            belt.irregularity.robust_cov, belt.irregularity.rmssd_sec, ...
            belt.irregularity.endpoint_mask] = compute_irregularity_metrics( ...
            irregular_input, t_grid, cfg.irregularity_win_sec, cfg.cov_thr, ...
            cfg.robust_cov_thr, cfg.rmssd_thr, cfg.pause_thr_sec, ...
            cfg.detection_metric);
    end
end

function spo2 = build_spo2_evidence(spo2_feat)
    spo2 = struct( ...
        'available', false, ...
        'desaturation_events', empty_events());
    if ~isstruct(spo2_feat)
        return;
    end
    if isfield(spo2_feat, 'spo2')
        x = spo2_feat.spo2(:);
        spo2.available = any(isfinite(x));
    end
    if isfield(spo2_feat, 'desat_events')
        spo2.desaturation_events = spo2_feat.desat_events;
    end
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
        'amp_window_median_raw_units', nan(size(t_grid)), ...
        'amp_ratio_session_window_median', nan(size(t_grid)), ...
        'apnea_amp_ratio_session_window_median', nan(size(t_grid)), ...
        'shallow_amplitude_mask', false(size(t_grid)), ...
        'deep_amplitude_mask', false(size(t_grid)), ...
        'irregularity', struct( ...
            'window_mask', false(size(t_grid)), ...
            'endpoint_mask', false(size(t_grid)), ...
            'cov', nan(size(t_grid)), ...
            'robust_cov', nan(size(t_grid)), ...
            'rmssd_sec', nan(size(t_grid))));
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
    peak_t = peak_t(isfinite(peak_t));
    for i = 1:numel(t_grid)
        t = t_grid(i);
        lb = t - win_sec;
        if lb < 0
            continue;
        end
        n_breaths = sum(peak_t >= lb & peak_t < t);
        if n_breaths >= 2
            trace(i) = n_breaths / win_sec * 60;
        end
    end
end

function mask = amplitude_band_mask(peak_t, ratio, t_grid, win_sec, r_lo, r_hi)
    mask = false(size(t_grid));
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
            mask(t_grid >= lb & t_grid <= t) = true;
        end
    end
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
    cfg.rapid_win_sec = get_config_value(config, 'RaB', 'min_dur_sec', 30);
    cfg.amplitude_win_sec = get_config_value(config, 'ShB', 'min_dur_sec', 30);
    cfg.apnea_win_sec = get_config_value(config, 'Apn', 'min_dur_sec', 10);
    cfg.shallow_lo_ratio = get_config_value(config, 'ShB', 'amp_ratio_low', 0.65);
    cfg.shallow_hi_ratio = get_config_value(config, 'ShB', 'amp_ratio_high', 0.80);
    cfg.deep_lo_ratio = get_config_value(config, 'RaB', 'deep_lo_ratio', 1.20);
    cfg.deep_hi_ratio = get_config_value(config, 'RaB', 'deep_hi_ratio', 1.35);
    cfg.irregularity_win_sec = get_config_value(config, 'IrB', 'min_dur_sec', 60);
    cfg.cov_thr = get_config_value(config, 'IrB', 'cov_thr', 0.3);
    cfg.robust_cov_thr = get_config_value(config, 'IrB', 'robust_cov_thr', 0.25);
    cfg.rmssd_thr = get_config_value(config, 'IrB', 'rmssd_thr', 0.0);
    cfg.pause_thr_sec = get_config_value(config, 'IrB', 'pause_thr_sec', 10);
    cfg.detection_metric = get_config_value(config, 'IrB', 'detection_metric', 'robust_cov');
end
