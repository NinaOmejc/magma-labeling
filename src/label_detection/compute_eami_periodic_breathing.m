function diagnostics = compute_eami_periodic_breathing(data, config)
% COMPUTE_EAMI_PERIODIC_BREATHING Compute eAMI from each usable raw belt.
% Implements Fernandez Tellez et al., Sleep 2015, using zero-phase filtering,
% 1-Hz finite-region resampling, locally mean-removed moving-window energies,
% and the published 0.65 threshold. MAGMA combines belts dynamically and uses
% twice the energy-window duration as the sustained event requirement.

    cfg = validate_eami_config(config.csr.eami, config.fs);
    N = size(data, 1);
    recording_end_t = max(0, (N - 1) / config.fs);
    if ~isfield(config, 'channels')
        config = resolve_signal_channels(config);
    end
    lungs_ignored = is_lung_belt_ignored(config);

    lungs = empty_eami_belt(recording_end_t, cfg);
    if ~lungs_ignored && valid_channel(config.channels.lungs_idx, size(data, 2))
        lungs = compute_eami_belt( ...
            data(:, config.channels.lungs_idx), N, config.fs, cfg);
    end
    diaph = empty_eami_belt(recording_end_t, cfg);
    if valid_channel(config.channels.diaph_idx, size(data, 2))
        diaph = compute_eami_belt( ...
            data(:, config.channels.diaph_idx), N, config.fs, cfg);
    end

    min_event_duration_sec = 2 * cfg.energy_win_sec;
    combined_generic = combine_periodic_belt_evidence( ...
        lungs.t_sec, lungs.evaluable_mask, lungs.threshold_mask, ...
        diaph.evaluable_mask, diaph.threshold_mask, ...
        min_event_duration_sec, N, config.fs);
    combined = struct( ...
        'available', combined_generic.available, ...
        't_sec', combined_generic.t_sec, ...
        'evaluable_mask', combined_generic.evaluable_mask, ...
        'threshold_mask', combined_generic.positive_mask, ...
        'candidate_mask', combined_generic.candidate_mask, ...
        'events', combined_generic.events);

    diagnostics = struct( ...
        'available', combined.available, ...
        'method_name', 'eAMI', ...
        'reference_doi', '10.5665/sleep.4494', ...
        'implementation', 'MAGMA implementation from published method', ...
        'energy_window_note', ['The 60-s default is a MAGMA comparison ' ...
            'choice, not a published optimum; the paper reports stable ' ...
            'behavior above approximately 40 s.'], ...
        'belt_combination', ['MAGMA dynamic rule: require both belts when both ' ...
            'are evaluable; otherwise use the single evaluable belt.'], ...
        'resp_band_hz', cfg.resp_band_hz, ...
        'bandpass_order', cfg.bandpass_order, ...
        'resample_hz', cfg.resample_hz, ...
        'envelope_lowpass_hz', cfg.envelope_lowpass_hz, ...
        'envelope_lowpass_order', cfg.envelope_lowpass_order, ...
        'energy_win_sec', cfg.energy_win_sec, ...
        'threshold', cfg.threshold, ...
        'min_event_duration_sec', min_event_duration_sec, ...
        'lungs', lungs, ...
        'diaph', diaph, ...
        'combined', combined);
end

function diagnostics = compute_eami_belt(raw_signal, N, fs, cfg)
% COMPUTE_EAMI_BELT Filter one raw belt and compute centered eAMI windows.

    recording_end_t = max(0, (N - 1) / fs);
    diagnostics = empty_eami_belt(recording_end_t, cfg);
    [resp_filtered, signal_t_sec] = bandpass_and_resample_finite_regions( ...
        raw_signal, fs, recording_end_t, cfg);
    amplitude_rectified = abs(resp_filtered);
    amplitude_envelope = lowpass_finite_regions( ...
        amplitude_rectified, cfg.resample_hz, ...
        cfg.envelope_lowpass_hz, cfg.envelope_lowpass_order);

    diagnostics.signal_t_sec = signal_t_sec;
    diagnostics.t_sec = signal_t_sec;
    diagnostics.resp_filtered = resp_filtered;
    diagnostics.amplitude_envelope = amplitude_envelope;
    diagnostics.energy_resp = nan(size(signal_t_sec));
    diagnostics.energy_am = nan(size(signal_t_sec));
    diagnostics.eami = nan(size(signal_t_sec));
    diagnostics.evaluable_mask = false(size(signal_t_sec));
    diagnostics.threshold_mask = false(size(signal_t_sec));

    n_window_samples = round(cfg.energy_win_sec * cfg.resample_hz) + 1;
    last_start = numel(signal_t_sec) - n_window_samples + 1;
    if last_start < 1
        return;
    end
    center_offset = floor((n_window_samples - 1) / 2);
    for start_index = 1:last_start
        idx = start_index:start_index + n_window_samples - 1;
        center_index = start_index + center_offset;
        resp_window = resp_filtered(idx);
        am_window = amplitude_envelope(idx);
        if any(~isfinite(resp_window)) || any(~isfinite(am_window))
            continue;
        end
        resp_window = resp_window - mean(resp_window);
        am_window = am_window - mean(am_window);
        energy_resp = mean(resp_window .^ 2);
        energy_am = mean(am_window .^ 2);
        if ~isfinite(energy_resp) || ~isfinite(energy_am) || ...
                energy_resp <= 0 || energy_am <= 0
            continue;
        end
        diagnostics.energy_resp(center_index) = energy_resp;
        diagnostics.energy_am(center_index) = energy_am;
        diagnostics.eami(center_index) = ...
            1 - 0.5 * log(energy_resp / energy_am);
        diagnostics.evaluable_mask(center_index) = ...
            isfinite(diagnostics.eami(center_index));
    end
    diagnostics.threshold_mask = diagnostics.evaluable_mask & ...
        diagnostics.eami >= cfg.threshold;
    single = combine_periodic_belt_evidence( ...
        diagnostics.t_sec, diagnostics.evaluable_mask, ...
        diagnostics.threshold_mask, false(size(diagnostics.t_sec)), ...
        false(size(diagnostics.t_sec)), 2 * cfg.energy_win_sec, N, fs);
    diagnostics.candidate_mask = single.candidate_mask;
    diagnostics.events = single.events;
    diagnostics.available = any(diagnostics.evaluable_mask);
end

function [output, t_output] = bandpass_and_resample_finite_regions( ...
    x, fs, recording_end_t, cfg)
% BANDPASS_AND_RESAMPLE_FINITE_REGIONS Avoid filtering across missing regions.

    t_output = (0:1 / cfg.resample_hz:recording_end_t)';
    output = nan(size(t_output));
    x = double(x(:));
    if isempty(x)
        return;
    end
    % MATLAB's band-pass transformation doubles the prototype order, so a
    % sixth-order prototype realizes the configured overall order of twelve.
    prototype_order = cfg.bandpass_order / 2;
    [z, p, k] = butter(prototype_order, ...
        cfg.resp_band_hz / (fs / 2), 'bandpass');
    [sos, gain] = zp2sos(z, p, k);
    runs = finite_runs(isfinite(x));
    for i = 1:size(runs, 1)
        idx = runs(i, 1):runs(i, 2);
        try
            filtered = filtfilt(sos, gain, x(idx));
        catch
            continue;
        end
        [p_rate, q_rate] = rat(cfg.resample_hz / fs, 1e-12);
        if p_rate == q_rate
            resampled = filtered;
            realized_fs = fs;
        else
            resampled = resample(filtered, p_rate, q_rate);
            realized_fs = fs * p_rate / q_rate;
        end
        segment_t = (idx(1) - 1) / fs + ...
            (0:numel(resampled) - 1)' / realized_fs;
        target = t_output >= segment_t(1) & ...
            t_output <= min(segment_t(end), (idx(end) - 1) / fs);
        if numel(segment_t) >= 2 && any(target)
            output(target) = interp1( ...
                segment_t, resampled, t_output(target), 'linear');
        end
    end
end

function output = lowpass_finite_regions(x, fs, cutoff_hz, order)
% LOWPASS_FINITE_REGIONS Zero-phase filter each contiguous supported region.

    output = nan(size(x));
    [z, p, k] = butter(order, cutoff_hz / (fs / 2), 'low');
    [sos, gain] = zp2sos(z, p, k);
    runs = finite_runs(isfinite(x));
    for i = 1:size(runs, 1)
        idx = runs(i, 1):runs(i, 2);
        try
            output(idx) = filtfilt(sos, gain, x(idx));
        catch
            continue;
        end
    end
end

function runs = finite_runs(mask)
% FINITE_RUNS Return inclusive bounds of contiguous true samples.

    changes = diff([false; logical(mask(:)); false]);
    runs = [find(changes == 1), find(changes == -1) - 1];
end

function diagnostics = empty_eami_belt(recording_end_t, cfg)
% EMPTY_EAMI_BELT Return one stable per-belt eAMI diagnostic schema.

    t_sec = (0:1 / cfg.resample_hz:recording_end_t)';
    diagnostics = struct( ...
        'available', false, ...
        'signal_t_sec', t_sec, ...
        't_sec', t_sec, ...
        'evaluable_mask', false(size(t_sec)), ...
        'resp_filtered', nan(size(t_sec)), ...
        'amplitude_envelope', nan(size(t_sec)), ...
        'energy_resp', nan(size(t_sec)), ...
        'energy_am', nan(size(t_sec)), ...
        'eami', nan(size(t_sec)), ...
        'threshold', cfg.threshold, ...
        'threshold_mask', false(size(t_sec)), ...
        'candidate_mask', false(size(t_sec)), ...
        'events', empty_events(), ...
        'reference_doi', '10.5665/sleep.4494', ...
        'paper_apneic_reference', 0.9);
end

function tf = valid_channel(index, n_columns)
% VALID_CHANNEL Check a resolved scalar data-column index.

    tf = ~isempty(index) && isscalar(index) && isfinite(index) && ...
        index == round(index) && index >= 1 && index <= n_columns;
end

function cfg = validate_eami_config(cfg, fs)
% VALIDATE_EAMI_CONFIG Validate filter, rate, energy, and threshold settings.

    required = {'resp_band_hz', 'bandpass_order', 'resample_hz', ...
        'envelope_lowpass_hz', 'envelope_lowpass_order', ...
        'energy_win_sec', 'threshold'};
    if ~isstruct(cfg) || ~all(isfield(cfg, required))
        error('MAGMA:CSR:InvalidEAMIConfig', ...
            'config.csr.eami is incomplete.');
    end
    cfg.resp_band_hz = cfg.resp_band_hz(:)';
    if numel(cfg.resp_band_hz) ~= 2 || any(~isfinite(cfg.resp_band_hz)) || ...
            cfg.resp_band_hz(1) <= 0 || ...
            cfg.resp_band_hz(2) <= cfg.resp_band_hz(1) || ...
            cfg.resp_band_hz(2) >= fs / 2
        error('MAGMA:CSR:InvalidEAMIConfig', ...
            'The eAMI respiratory band must lie strictly inside (0, fs/2).');
    end
    if ~isscalar(cfg.bandpass_order) || cfg.bandpass_order < 2 || ...
            cfg.bandpass_order ~= round(cfg.bandpass_order) || ...
            mod(cfg.bandpass_order, 2) ~= 0
        error('MAGMA:CSR:InvalidEAMIConfig', ...
            'The eAMI overall band-pass order must be a positive even integer.');
    end
    positive_scalars = {'resample_hz', 'envelope_lowpass_hz', ...
        'envelope_lowpass_order', 'energy_win_sec'};
    for i = 1:numel(positive_scalars)
        value = cfg.(positive_scalars{i});
        if ~isscalar(value) || ~isfinite(value) || value <= 0
            error('MAGMA:CSR:InvalidEAMIConfig', ...
                'config.csr.eami.%s must be positive.', positive_scalars{i});
        end
    end
    if cfg.resample_hz > fs || cfg.envelope_lowpass_hz >= cfg.resample_hz / 2
        error('MAGMA:CSR:InvalidEAMIConfig', ...
            'The eAMI resampling rate must support its envelope low-pass cutoff.');
    end
    if cfg.envelope_lowpass_order ~= round(cfg.envelope_lowpass_order)
        error('MAGMA:CSR:InvalidEAMIConfig', ...
            'The eAMI envelope low-pass order must be an integer.');
    end
    if ~isscalar(cfg.threshold) || ~isfinite(cfg.threshold)
        error('MAGMA:CSR:InvalidEAMIConfig', ...
            'The eAMI threshold must be a finite scalar.');
    end
end
