function [events, diagnostics, boundary_info] = detect_apnea( ...
    data, phys_feat, session_reference, config)
% detect_apnea
% Label 6 - Apnea
%
% Evidence paths:
%   1) Peak-amplitude path: every usable breath in the analysis window is
%      <= threshold relative to the respiratory amplitude reference.
%   2) Optional raw-flat path: direct low-motion/plateau detection on the
%      preprocessed respiration belts, independent of detected breath peaks.
%      Its raw motion/slope anchor is estimated from the common session
%      physiological reference interval.
%
% If both belts are usable, both must support the apnea evidence. If only
% one belt is usable, that belt is used alone. SpO2 does not modify apnea
% events; coincident desaturation remains a separate label.
% Rolling evidence confirms candidate episodes. Once confirmed, raw-flat
% plateau timing is preferred for localization; otherwise low-amplitude
% reviewed breath cells localize the episode. Candidate timing is retained
% as an explicit fallback and event existence is never changed by the
% localization step.

    events = empty_events();

    N = size(data, 1);
    t_grid = phys_feat.resp.time_sec;
    lungs = phys_feat.resp.lungs;
    diaph = phys_feat.resp.diaph;
    boundary_info = make_label_boundary_info('apnea', 'detect_apnea', ...
        'not_evaluated', empty_events(), empty_events(), NaN, '', [], [], []);

    if ~isfield(config, 'channels')
        config = resolve_signal_channels(config);
    end
    idx_lungs = config.channels.lungs_idx;
    idx_diaph = config.channels.diaph_idx;

    lungs_broken = lungs.ignored;
    lungs_breath_valid = lungs.session_amplitude_available;
    diaph_breath_valid = diaph.session_amplitude_available;

    lungs_raw_valid = ~lungs_broken && ~isempty(idx_lungs) && any(isfinite(data(:, idx_lungs)));
    diaph_raw_valid = ~isempty(idx_diaph) && any(isfinite(data(:, idx_diaph)));

    % ----------------------------
    % Config defaults
    % ----------------------------
    amp_ratio_thr = get_config_value(config, 'Apn', 'amp_ratio_thr', 0.10);
    min_dur_sec = get_config_value(config, 'Apn', 'min_dur_sec', 10);
    raw_flat_enabled = get_config_value(config, 'Apn', 'raw_flat_enabled', true);

    raw_cfg = struct();
    raw_cfg.win_sec = get_config_value(config, 'Apn', 'raw_flat_win_sec', min_dur_sec);
    raw_cfg.ref_win_sec = get_config_value(config, 'Apn', 'raw_flat_ref_win_sec', 60);
    raw_cfg.ref_lag_sec = get_config_value(config, 'Apn', 'raw_flat_ref_lag_sec', 10);
    raw_cfg.ref_floor_ratio = get_config_value(config, 'Apn', 'raw_flat_ref_floor_ratio', 0.25);
    raw_cfg.motion_ratio_thr = get_config_value(config, 'Apn', 'raw_flat_motion_ratio_thr', 0.10);
    raw_cfg.slope_ratio_thr = get_config_value(config, 'Apn', 'raw_flat_slope_ratio_thr', 0.15);
    raw_cfg.hist_peak_frac_thr = get_config_value(config, 'Apn', 'raw_flat_hist_peak_frac_thr', 0.35);
    raw_cfg.min_plateau_sec = get_config_value(config, 'Apn', 'raw_flat_min_plateau_sec', min(5, min_dur_sec));
    raw_cfg.hist_bins = get_config_value(config, 'Apn', 'raw_flat_hist_bins', 40);
    raw_cfg.prctile_low = 5;
    raw_cfg.prctile_high = 95;
    raw_cfg.hist_band_pad_frac = 0.05;
    raw_cfg.min_ref_sec = min(raw_cfg.ref_win_sec, max(raw_cfg.win_sec, 30));

    diagnostics = struct( ...
        'available', false, ...
        'peak_path_available', lungs_breath_valid || diaph_breath_valid, ...
        'raw_flat_path_available', false, ...
        'peak_endpoint_mask', false(size(t_grid)), ...
        'peak_state_mask', false(size(t_grid)), ...
        'peak_localized_mask', false(size(t_grid)), ...
        'raw_flat_state_mask', false(size(t_grid)), ...
        'raw_flat_localized_mask', false(size(t_grid)), ...
        'combined_state_mask', false(size(t_grid)), ...
        'localized_state_mask', false(size(t_grid)), ...
        'peak_support_belts', support_belts(lungs_breath_valid, diaph_breath_valid), ...
        'raw_flat_support_belts', '', ...
        'amp_ratio_threshold', amp_ratio_thr, ...
        'amp_analysis_window_sec', get_config_value(config, 'Apn', 'amp_analysis_win_sec', min_dur_sec), ...
        'raw_flat_analysis_window_sec', raw_cfg.win_sec, ...
        'min_state_duration_sec', min_dur_sec, ...
        'raw_flat', init_raw_flat_diag(t_grid, N));

    if ~(lungs_breath_valid || diaph_breath_valid || ...
            (raw_flat_enabled && (lungs_raw_valid || diaph_raw_valid)))
        fprintf('Skipping apnea detection: no usable respiratory belt evidence for peak-amplitude or raw-flat apnea logic.\n');
        return;
    end

    % ----------------------------
    % Peak-amplitude apnea path
    % ----------------------------
    apnea_peak = false(size(t_grid));

    if lungs_breath_valid || diaph_breath_valid
        lungs_low = false(size(t_grid));
        if lungs_breath_valid && isfield(lungs, 'apnea_amplitude_endpoint_mask')
            lungs_low = logical(lungs.apnea_amplitude_endpoint_mask);
        end
        diaph_low = false(size(t_grid));
        if diaph_breath_valid && isfield(diaph, 'apnea_amplitude_endpoint_mask')
            diaph_low = logical(diaph.apnea_amplitude_endpoint_mask);
        end
        if lungs_breath_valid && diaph_breath_valid
            apnea_peak_endpoint = lungs_low & diaph_low;
        elseif lungs_breath_valid
            apnea_peak_endpoint = lungs_low;
        else
            apnea_peak_endpoint = diaph_low;
        end

        diagnostics.peak_endpoint_mask = apnea_peak_endpoint;
        apnea_peak = analysis_window_endpoints_to_state_mask( ...
            apnea_peak_endpoint, t_grid, diagnostics.amp_analysis_window_sec);
        diagnostics.peak_state_mask = apnea_peak;
    end

    % ----------------------------
    % Optional raw-flat apnea path
    % ----------------------------
    apnea_raw = false(size(t_grid));
    raw_diag = init_raw_flat_diag(t_grid, N);

    if raw_flat_enabled
        [apnea_raw_candidate, raw_diag] = raw_flat_apnea_condition_on_grid( ...
            data, session_reference, config, t_grid, idx_lungs, idx_diaph, ...
            lungs_raw_valid, diaph_raw_valid, raw_cfg);

        apnea_raw = apnea_raw_candidate;
        diagnostics.raw_flat = raw_diag;
        diagnostics.raw_flat_path_available = ...
            raw_diag.lungs.valid || raw_diag.diaph.valid;
        diagnostics.raw_flat_support_belts = support_belts( ...
            raw_diag.lungs.valid, raw_diag.diaph.valid);
        diagnostics.raw_flat_state_mask = apnea_raw;
    end

    % Merge evidence paths and convert to sample-level events.
    apnea_mask_candidate = apnea_peak | apnea_raw;
    [candidate_events, apnea_mask] = sustained_condition_to_events( ...
        apnea_mask_candidate, t_grid, config.fs, N, min_dur_sec, 'apnea');
    diagnostics.combined_state_mask = apnea_mask;
    diagnostics.available = diagnostics.peak_path_available || ...
        diagnostics.raw_flat_path_available;

    amplitude_local_mask = amplitude_apnea_support_mask( ...
        lungs, diaph, lungs_breath_valid, diaph_breath_valid, ...
        amp_ratio_thr, t_grid);
    raw_local_mask = raw_diag.combined_plateau;
    if ~any(raw_local_mask) && diagnostics.raw_flat_path_available
        % Motion/slope windows still support the event when no histogram
        % plateau is found, but retain their full window-scale uncertainty.
        raw_local_mask = apnea_raw;
    end
    diagnostics.peak_localized_mask = amplitude_local_mask;
    diagnostics.raw_flat_localized_mask = raw_local_mask;
    [events, boundary_records] = localize_apnea_candidates( ...
        candidate_events, amplitude_local_mask, apnea_peak, ...
        raw_diag.combined_plateau_native, raw_local_mask, apnea_raw, ...
        t_grid, N, config.fs, diagnostics.amp_analysis_window_sec, ...
        diagnostics.raw_flat_analysis_window_sec);
    diagnostics.localized_state_mask = events_to_grid_mask(events, t_grid);
    boundary_info = make_label_boundary_info('apnea', 'detect_apnea', ...
        'confirmed_dual_path_evidence_specific_localization', ...
        candidate_events, events, NaN, 'raw_flat_or_breath_amplitude', ...
        diagnostics.peak_endpoint_mask, apnea_mask_candidate, ...
        diagnostics.localized_state_mask);
    boundary_info.events = boundary_records;
    if ~isempty(boundary_records)
        boundary_info.boundary_uncertainty_sec = ...
            [boundary_records.uncertainty_sec]';
    end

    % ----------------------------
    % Optional plot
    % ----------------------------
    if isfield(config, 'Apn') && isfield(config.Apn, 'do_plot') && config.Apn.do_plot
        t_raw = (0:N-1) / config.fs;

        figure('Units', 'pixels', 'Position', near_fullscreen_figure_position(), ...
            'Visible', config.make_figs_visible);
        sgtitle(['APNEA | Subject: ' num2str(config.subject) ' | Measurement: ' num2str(config.measure)])

        subplot(4, 1, 1); hold on
        plot_resp_trace_or_message(t_raw, data, idx_lungs, 'Resp-Lungs');
        shade_mask_on_axis(t_grid, diagnostics.localized_state_mask);
        yline(0, ':')
        title('Combined apnea mask over lungs raw signal')
        xlabel('Time (s)'); ylabel('Resp-Lungs'); grid on
        hold off

        subplot(4, 1, 2); hold on
        plot_resp_trace_or_message(t_raw, data, idx_diaph, 'Resp-Diaphragm');
        shade_mask_on_axis(t_grid, diagnostics.localized_state_mask);
        title('Combined apnea mask over diaphragm raw signal')
        xlabel('Time (s)'); ylabel('Resp-Diaphragm'); grid on
        hold off

        subplot(4, 1, 3); hold on
        lungs_ratio = nan(size(t_grid));
        if lungs_breath_valid
            lungs_ratio = lungs.apnea_amp_ratio_session_window_median;
        end
        diaph_ratio = nan(size(t_grid));
        if diaph_breath_valid
            diaph_ratio = diaph.apnea_amp_ratio_session_window_median;
        end
        plot(t_grid, lungs_ratio, 'k')
        plot(t_grid, diaph_ratio, 'b')
        yline(amp_ratio_thr, 'r--')
        shade_mask_on_axis(t_grid, diagnostics.localized_state_mask);
        title('Peak-amplitude ratios (common session reference)')
        xlabel('Time (s)'); ylabel('Amp ratio'); grid on
        legend('lungs ratio', 'diaph ratio', 'thr', 'Location', 'eastoutside')
        hold off

        subplot(4, 1, 4); hold on
        if raw_flat_enabled
            plot(t_grid, raw_diag.lungs.motion_ratio, 'k')
            plot(t_grid, raw_diag.diaph.motion_ratio, 'b')
            plot(t_grid, raw_diag.lungs.hist_peak_frac, 'Color', [0.2 0.2 0.2], 'LineStyle', ':')
            plot(t_grid, raw_diag.diaph.hist_peak_frac, 'Color', [0.1 0.35 0.9], 'LineStyle', ':')
            yline(raw_cfg.motion_ratio_thr, 'r--')
            yline(raw_cfg.hist_peak_frac_thr, 'm--')
            shade_mask_on_axis(t_grid, diagnostics.localized_state_mask);
            title('Raw-flat diagnostics: movement ratio and histogram plateau score')
            xlabel('Time (s)'); ylabel('Ratio / fraction'); grid on
            legend('lungs motion', 'diaph motion', 'lungs hist peak', 'diaph hist peak', ...
                'motion thr', 'hist thr', 'Location', 'eastoutside')
        else
            text(0.5, 0.5, 'Raw-flat apnea detection disabled', ...
                'Units', 'normalized', 'HorizontalAlignment', 'center')
            axis off
        end
        hold off

        ax = findall(gcf, 'Type', 'axes');
        ax = ax(arrayfun(@(a) ~strcmp(a.Tag, 'legend'), ax));
        linkaxes(ax, 'x');
        xlim(ax(1), [0 t_grid(end)]);
        align_axes_x_widths(ax);

        save_figure(config, 'apnea');
    end
end

function belt = support_belts(use_lungs, use_diaph)
    if use_lungs && use_diaph
        belt = 'both';
    elseif use_lungs
        belt = 'lungs';
    elseif use_diaph
        belt = 'diaph';
    else
        belt = '';
    end
end

% =========================================================
% Raw-flat apnea helpers
% =========================================================

function [combined_mask, diag] = raw_flat_apnea_condition_on_grid( ...
    data, session_reference, config, t_grid, idx_lungs, idx_diaph, ...
    use_lungs, use_diaph, raw_cfg)

    combined_mask = false(size(t_grid));
    diag = init_raw_flat_diag(t_grid, size(data, 1));

    if use_lungs
        [lungs_mask, lungs_diag] = raw_flat_belt_mask( ...
            data(:, idx_lungs), session_reference, config, t_grid, raw_cfg);
        diag.lungs = lungs_diag;
        diag.lungs.mask = lungs_mask;
    end

    if use_diaph
        [diaph_mask, diaph_diag] = raw_flat_belt_mask( ...
            data(:, idx_diaph), session_reference, config, t_grid, raw_cfg);
        diag.diaph = diaph_diag;
        diag.diaph.mask = diaph_mask;
    end

    use_lungs = use_lungs && diag.lungs.valid;
    use_diaph = use_diaph && diag.diaph.valid;

    if use_lungs && use_diaph
        combined_mask = diag.lungs.mask & diag.diaph.mask;
        diag.combined_plateau = diag.lungs.plateau_mask & diag.diaph.plateau_mask;
        diag.combined_plateau_native = ...
            diag.lungs.plateau_mask_native & diag.diaph.plateau_mask_native;
    elseif use_lungs
        combined_mask = diag.lungs.mask;
        diag.combined_plateau = diag.lungs.plateau_mask;
        diag.combined_plateau_native = diag.lungs.plateau_mask_native;
    elseif use_diaph
        combined_mask = diag.diaph.mask;
        diag.combined_plateau = diag.diaph.plateau_mask;
        diag.combined_plateau_native = diag.diaph.plateau_mask_native;
    end

    diag.combined_candidate = combined_mask;
end

function diag = init_raw_flat_diag(t_grid, N)
    if nargin < 2
        N = numel(t_grid);
    end
    empty_belt = struct( ...
        'valid', false, ...
        'reference_available', false, ...
        'reference_quality', 'not_evaluated', ...
        'reference_source', 'common_session_reference_interval', ...
        'reference_n_samples', 0, ...
        'reference_finite_fraction', NaN, ...
        'session_motion_reference', NaN, ...
        'session_slope_reference', NaN, ...
        'mask', false(size(t_grid)), ...
        'motion_mask', false(size(t_grid)), ...
        'slope_mask', false(size(t_grid)), ...
        'plateau_mask', false(size(t_grid)), ...
        'plateau_mask_native', false(N, 1), ...
        'motion_ratio', nan(size(t_grid)), ...
        'slope_ratio', nan(size(t_grid)), ...
        'motion_reference_used', nan(size(t_grid)), ...
        'slope_reference_used', nan(size(t_grid)), ...
        'adaptive_reference_used', false(size(t_grid)), ...
        'hist_peak_frac', nan(size(t_grid)), ...
        'plateau_run_sec', nan(size(t_grid)) );

    diag = struct();
    diag.lungs = empty_belt;
    diag.diaph = empty_belt;
    diag.combined_candidate = false(size(t_grid));
    diag.combined_plateau = false(size(t_grid));
    diag.combined_plateau_native = false(N, 1);
end

function mask = amplitude_apnea_support_mask( ...
    lungs, diaph, use_lungs, use_diaph, threshold, t_grid)

    lungs_mask = breath_amplitude_mask(lungs, threshold, t_grid);
    diaph_mask = breath_amplitude_mask(diaph, threshold, t_grid);
    if use_lungs && use_diaph
        mask = lungs_mask & diaph_mask;
    elseif use_lungs
        mask = lungs_mask;
    elseif use_diaph
        mask = diaph_mask;
    else
        mask = false(size(t_grid));
    end
end

function mask = breath_amplitude_mask(belt, threshold, t_grid)
    mask = false(size(t_grid));
    if ~isstruct(belt) || ~isfield(belt, 'peak_t') || ...
            ~isfield(belt, 'amp_ratio_session')
        return;
    end
    peak_t = belt.peak_t(:);
    ratio = belt.amp_ratio_session(:);
    n = min(numel(peak_t), numel(ratio));
    peak_t = peak_t(1:n);
    ratio = ratio(1:n);
    for i = 1:n
        if ~isfinite(peak_t(i)) || ~isfinite(ratio(i)) || ratio(i) > threshold
            continue;
        end
        if n == 1
            t0 = peak_t(i) - 0.5;
            t1 = peak_t(i) + 0.5;
        else
            if i == 1
                t0 = peak_t(i) - 0.5 * (peak_t(i+1) - peak_t(i));
            else
                t0 = 0.5 * (peak_t(i-1) + peak_t(i));
            end
            if i == n
                t1 = peak_t(i) + 0.5 * (peak_t(i) - peak_t(i-1));
            else
                t1 = 0.5 * (peak_t(i) + peak_t(i+1));
            end
        end
        mask = mask | (t_grid >= t0 & t_grid < t1);
    end
end

function [events, records] = localize_apnea_candidates( ...
    candidates, amplitude_local, amplitude_candidate, raw_plateau_native, ...
    raw_window_local, raw_candidate, t_grid, N, fs, amp_window_sec, raw_window_sec)

    events = empty_events();
    template = struct('label', 'apnea', 'detector', 'detect_apnea', ...
        'boundary_method', '', 'candidate_start_t', NaN, ...
        'candidate_end_t', NaN, 'localized_start_t', NaN, ...
        'localized_end_t', NaN, 'uncertainty_sec', NaN, ...
        'evidence_source', '');
    records = template([]);
    if isempty(candidates)
        return;
    end
    events = repmat(candidates(1), numel(candidates), 1);
    records = repmat(template, numel(candidates), 1);
    if numel(t_grid) > 1
        grid_step = median(diff(t_grid), 'omitnan');
    else
        grid_step = 1;
    end
    t_native = (0:N-1)' / fs;

    for i = 1:numel(candidates)
        candidate = candidates(i);
        in_candidate = t_grid >= candidate.start_t & t_grid < candidate.end_t;
        in_candidate_native = t_native >= candidate.start_t & ...
            t_native < candidate.end_t;
        has_amp = any(amplitude_candidate & in_candidate);
        has_raw = any(raw_candidate & in_candidate);
        source = 'confirmation_window_only';
        method = 'aggregate_window_candidate_fallback';
        uncertainty = max(amp_window_sec, raw_window_sec);
        local_mask = false(size(t_grid));
        found = false;

        if has_raw && any(raw_plateau_native & in_candidate_native)
            native_mask = raw_plateau_native & in_candidate_native;
            [t0, t1, found] = longest_grid_run(native_mask, t_native, 1/fs);
            method = 'raw_flat_native_plateau_localization';
            uncertainty = 1/fs;
            if has_amp
                source = 'both';
            else
                source = 'raw_flat';
            end
        elseif has_raw && any(raw_window_local & in_candidate)
            local_mask = raw_window_local & in_candidate;
            method = 'raw_flat_window_support_localization';
            uncertainty = raw_window_sec;
            if has_amp
                source = 'both';
            else
                source = 'raw_flat';
            end
        elseif has_amp && any(amplitude_local & in_candidate)
            local_mask = amplitude_local & in_candidate;
            method = 'breath_amplitude_midpoint_localization';
            uncertainty = amp_window_sec;
            source = 'breath_amplitude';
        end

        if ~found
            [t0, t1, found] = longest_grid_run(local_mask, t_grid, grid_step);
        end
        if ~found
            t0 = candidate.start_t;
            t1 = candidate.end_t;
        end
        events(i) = event_from_times(candidate, t0, t1, N, fs);
        records(i).boundary_method = method;
        records(i).candidate_start_t = candidate.start_t;
        records(i).candidate_end_t = candidate.end_t;
        records(i).localized_start_t = events(i).start_t;
        records(i).localized_end_t = events(i).end_t;
        records(i).uncertainty_sec = uncertainty;
        records(i).evidence_source = source;
    end
end

function [t0, t1, found] = longest_grid_run(mask, t_grid, grid_step)
    d = diff([false; logical(mask(:)); false]);
    starts = find(d == 1);
    ends = find(d == -1) - 1;
    found = ~isempty(starts);
    t0 = NaN;
    t1 = NaN;
    if ~found, return; end
    [~, best] = max(ends - starts + 1);
    t0 = t_grid(starts(best));
    t1 = t_grid(ends(best)) + grid_step;
end

function event = event_from_times(event, start_t, end_t, N, fs)
    recording_end = N / fs;
    start_t = max(0, min(recording_end, start_t));
    end_t = max(start_t, min(recording_end, end_t));
    event.start_idx = max(1, min(N, round(start_t * fs) + 1));
    event.end_idx = max(event.start_idx, min(N, round(end_t * fs)));
    event.start_t = (event.start_idx - 1) / fs;
    event.end_t = event.end_idx / fs;
    event.duration = (event.end_idx - event.start_idx + 1) / fs;
end

function [mask, diag] = raw_flat_belt_mask( ...
    x, session_reference, config, t_grid, raw_cfg)
    x = x(:);
    fs = config.fs;
    N = numel(x);
    all_diag = init_raw_flat_diag(t_grid, N);
    diag = all_diag.lungs;
    mask = false(size(t_grid));

    if raw_cfg.win_sec <= 0 || N < 3 || numel(t_grid) < 2
        return;
    end

    if ~isstruct(session_reference) || ~isfield(session_reference, 'available') || ...
            ~session_reference.available
        diag.reference_quality = 'reference_interval_unavailable';
        return;
    end
    reference_start_idx = session_reference.reference_start_idx;
    reference_end_idx = session_reference.reference_end_idx;
    if reference_start_idx < 1 || reference_end_idx > N || ...
            reference_end_idx < reference_start_idx
        diag.reference_quality = 'reference_interval_unavailable';
        return;
    end

    reference_segment = x(reference_start_idx:reference_end_idx);
    diag.reference_n_samples = numel(reference_segment);
    diag.reference_finite_fraction = finite_fraction(reference_segment);
    session_motion_ref = robust_excursion(reference_segment, raw_cfg);
    session_slope_ref = raw_slope_level(reference_segment);
    diag.session_motion_reference = session_motion_ref;
    diag.session_slope_reference = session_slope_ref;

    if ~isfinite(session_motion_ref) || session_motion_ref <= 0 || ...
            ~isfinite(session_slope_ref) || session_slope_ref <= 0
        diag.reference_quality = 'unusable_motion_or_slope_reference';
        return;
    end

    motion_mask = false(size(t_grid));
    slope_mask = false(size(t_grid));
    plateau_mask = false(size(t_grid));
    diag.reference_available = true;
    if session_reference.complete
        diag.reference_quality = 'good';
    else
        diag.reference_quality = 'warning_truncated_interval';
    end
    diag.valid = true;

    for i = 1:numel(t_grid)
        t = t_grid(i);
        lb = t - raw_cfg.win_sec;
        if lb < 0
            continue;
        end

        [i1, i2] = time_window_to_indices(lb, t, fs, N);
        if i2 <= i1
            continue;
        end

        segment = x(i1:i2);
        if finite_fraction(segment) < 0.8
            continue;
        end

        [motion_ref, slope_ref, adaptive_reference_used] = raw_reference_at_time( ...
            x, t, fs, session_motion_ref, session_slope_ref, raw_cfg);
        diag.motion_reference_used(i) = motion_ref;
        diag.slope_reference_used(i) = slope_ref;
        diag.adaptive_reference_used(i) = adaptive_reference_used;

        motion = robust_excursion(segment, raw_cfg);
        slope = raw_slope_level(segment);
        if isfinite(motion) && isfinite(motion_ref) && motion_ref > 0
            diag.motion_ratio(i) = motion / motion_ref;
        end
        if isfinite(slope) && isfinite(slope_ref) && slope_ref > 0
            diag.slope_ratio(i) = slope / slope_ref;
        end

        sample_t = ((i1:i2)' - 1) / fs;
        [hist_peak_frac, plateau_start_t, plateau_end_t, plateau_run_sec] = ...
            strongest_histogram_plateau(segment, sample_t, fs, raw_cfg);
        diag.hist_peak_frac(i) = hist_peak_frac;
        diag.plateau_run_sec(i) = plateau_run_sec;

        if isfinite(diag.motion_ratio(i)) && diag.motion_ratio(i) <= raw_cfg.motion_ratio_thr
            motion_mask(mark_time_range_on_grid(t_grid, lb, t)) = true;
        end

        if isfinite(diag.slope_ratio(i)) && diag.slope_ratio(i) <= raw_cfg.slope_ratio_thr
            slope_mask(mark_time_range_on_grid(t_grid, lb, t)) = true;
        end

        plateau_ok = isfinite(hist_peak_frac) && ...
            hist_peak_frac >= raw_cfg.hist_peak_frac_thr && ...
            isfinite(plateau_run_sec) && plateau_run_sec >= raw_cfg.min_plateau_sec;

        if plateau_ok
            plateau_mask(mark_time_range_on_grid(t_grid, plateau_start_t, plateau_end_t)) = true;
            [plateau_start_idx, plateau_end_idx] = time_window_to_indices( ...
                plateau_start_t, plateau_end_t, fs, N);
            diag.plateau_mask_native(plateau_start_idx:plateau_end_idx) = true;
        end
    end

    mask = motion_mask & (slope_mask | plateau_mask);
    diag.mask = mask;
    diag.motion_mask = motion_mask;
    diag.slope_mask = slope_mask;
    diag.plateau_mask = plateau_mask;
end

function [motion_ref, slope_ref, adaptive_reference_used] = raw_reference_at_time( ...
    x, t, fs, session_motion_ref, session_slope_ref, raw_cfg)

    % Preserve the detector's causal local comparator, but require and
    % anchor it to the common session reference. A missing session reference
    % is handled before this function; no other interval substitutes for it.
    motion_ref = session_motion_ref;
    slope_ref = session_slope_ref;
    adaptive_reference_used = false;

    t2 = t - raw_cfg.ref_lag_sec;
    t1 = t2 - raw_cfg.ref_win_sec;
    if t2 <= 0 || (t2 - t1) < raw_cfg.min_ref_sec
        return;
    end

    [i1, i2] = time_window_to_indices(t1, t2, fs, numel(x));
    if i2 <= i1
        return;
    end
    if ((i2 - i1 + 1) / fs) < raw_cfg.min_ref_sec
        return;
    end

    segment = x(i1:i2);
    if finite_fraction(segment) < 0.8
        return;
    end

    candidate_motion = robust_excursion(segment, raw_cfg);
    candidate_slope = raw_slope_level(segment);

    if isfinite(candidate_motion) && candidate_motion > 0
        motion_ref = candidate_motion;
        adaptive_reference_used = true;
    end
    if isfinite(candidate_slope) && candidate_slope > 0
        slope_ref = candidate_slope;
        adaptive_reference_used = true;
    end

    if isfinite(raw_cfg.ref_floor_ratio) && raw_cfg.ref_floor_ratio > 0
        motion_ref = max(motion_ref, raw_cfg.ref_floor_ratio * session_motion_ref);
        slope_ref = max(slope_ref, raw_cfg.ref_floor_ratio * session_slope_ref);
    end
end

function [peak_frac, run_start_t, run_end_t, run_dur_sec] = strongest_histogram_plateau(x, sample_t, fs, raw_cfg)
    peak_frac = NaN;
    run_start_t = NaN;
    run_end_t = NaN;
    run_dur_sec = NaN;

    x = x(:);
    sample_t = sample_t(:);
    finite_x = x(isfinite(x));
    if numel(finite_x) < 3
        return;
    end

    xmin = min(finite_x);
    xmax = max(finite_x);
    span = xmax - xmin;

    if ~isfinite(span) || span <= eps(max(abs([xmin xmax 1])))
        center = median(finite_x, 'omitnan');
        tol = max(1e-12, 16 * eps(max(abs(center), 1)));
        inside = isfinite(x) & abs(x - center) <= tol;
        peak_frac = nnz(inside) / numel(finite_x);
    else
        hist_bins = max(5, round(raw_cfg.hist_bins));
        edges = linspace(xmin, xmax, hist_bins + 1);
        counts = histcounts(finite_x, edges);
        if isempty(counts) || ~any(counts)
            return;
        end

        [peak_count, peak_bin] = max(counts);
        peak_frac = peak_count / numel(finite_x);

        band_pad = raw_cfg.hist_band_pad_frac * robust_excursion(finite_x, raw_cfg);
        if ~isfinite(band_pad) || band_pad <= 0
            band_pad = span / hist_bins;
        end

        band_low = edges(peak_bin) - band_pad;
        band_high = edges(peak_bin + 1) + band_pad;
        inside = isfinite(x) & x >= band_low & x <= band_high;
    end

    [run_start_idx, run_end_idx, run_dur_sec] = longest_true_run(inside, fs);
    if isfinite(run_dur_sec) && run_dur_sec > 0
        run_start_t = sample_t(run_start_idx);
        run_end_t = sample_t(run_end_idx);
    end
end

function r = robust_excursion(x, raw_cfg)
    x = x(isfinite(x));
    if numel(x) < 3
        r = NaN;
        return;
    end
    r = prctile(x, raw_cfg.prctile_high) - prctile(x, raw_cfg.prctile_low);
end

function s = raw_slope_level(x)
    x = x(:);
    x = x(isfinite(x));
    if numel(x) < 3
        s = NaN;
        return;
    end
    s = median(abs(diff(x)), 'omitnan');
end

function f = finite_fraction(x)
    if isempty(x)
        f = 0;
    else
        f = nnz(isfinite(x)) / numel(x);
    end
end

function [i1, i2] = time_window_to_indices(t1, t2, fs, N)
    i1 = max(1, floor(t1 * fs) + 1);
    i2 = min(N, floor(t2 * fs) + 1);
end

function grid_idx = mark_time_range_on_grid(t_grid, t0, t1)
    if ~isfinite(t0) || ~isfinite(t1)
        grid_idx = false(size(t_grid));
        return;
    end

    if numel(t_grid) > 1
        tol = 0.5 * median(diff(t_grid), 'omitnan');
    else
        tol = 0;
    end

    grid_idx = t_grid >= (t0 - tol) & t_grid <= (t1 + tol);
end

function [run_start_idx, run_end_idx, run_dur_sec] = longest_true_run(mask, fs)
    mask = mask(:) ~= 0;
    d = diff([false; mask; false]);
    starts = find(d == 1);
    ends = find(d == -1) - 1;

    if isempty(starts)
        run_start_idx = NaN;
        run_end_idx = NaN;
        run_dur_sec = NaN;
        return;
    end

    [run_len, best_idx] = max(ends - starts + 1);
    run_start_idx = starts(best_idx);
    run_end_idx = ends(best_idx);
    run_dur_sec = run_len / fs;
end

function plot_resp_trace_or_message(t_raw, data, idx, label_text)
    if isempty(idx)
        text(0.5, 0.5, [label_text ' channel not found'], ...
            'Units', 'normalized', 'HorizontalAlignment', 'center')
    else
        plot(t_raw, data(:, idx), 'k')
    end
end
