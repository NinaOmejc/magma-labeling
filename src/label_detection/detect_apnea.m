function [events, diagnostics] = detect_apnea(data, phys_feat, config)
% detect_apnea
% Label 7 - Apnea
%
% Evidence paths:
%   1) Peak-amplitude path: breath amplitudes <= threshold relative to the
%      respiratory amplitude reference.
%   2) Optional raw-flat path: direct low-motion/plateau detection on the
%      preprocessed respiration belts, independent of detected breath peaks.
%
% If both belts are usable, both must support the apnea evidence. If only
% one belt is usable, that belt is used alone. SpO2 does not modify apnea
% events; coincident desaturation remains a separate label.
% A TRUE amplitude endpoint summarizes the preceding amplitude-analysis
% window; that window is backfilled into the inferred state. Raw-flat
% diagnostics already mark their supporting window. The two inferred-state
% paths are unioned and min_dur_sec is applied once. All raw-signal windows
% and returned sample indices use config.fs.

    events = empty_events();

    N = size(data, 1);
    t_grid = phys_feat.resp.time_sec;
    lungs = phys_feat.resp.lungs;
    diaph = phys_feat.resp.diaph;

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
        'raw_flat_state_mask', false(size(t_grid)), ...
        'combined_state_mask', false(size(t_grid)), ...
        'peak_support_belts', support_belts(lungs_breath_valid, diaph_breath_valid), ...
        'raw_flat_support_belts', '', ...
        'amp_ratio_threshold', amp_ratio_thr, ...
        'amp_analysis_window_sec', get_config_value(config, 'Apn', 'amp_analysis_win_sec', min_dur_sec), ...
        'raw_flat_analysis_window_sec', raw_cfg.win_sec, ...
        'min_state_duration_sec', min_dur_sec, ...
        'raw_flat', init_raw_flat_diag(t_grid));

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
        if lungs_breath_valid
            lungs_low = isfinite(lungs.apnea_amp_ratio_session_window_median) & ...
                lungs.apnea_amp_ratio_session_window_median <= amp_ratio_thr;
        end
        diaph_low = false(size(t_grid));
        if diaph_breath_valid
            diaph_low = isfinite(diaph.apnea_amp_ratio_session_window_median) & ...
                diaph.apnea_amp_ratio_session_window_median <= amp_ratio_thr;
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
    raw_diag = init_raw_flat_diag(t_grid);

    if raw_flat_enabled
        [apnea_raw_candidate, raw_diag] = raw_flat_apnea_condition_on_grid( ...
            data, config, t_grid, idx_lungs, idx_diaph, ...
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
    [events, apnea_mask] = sustained_condition_to_events( ...
        apnea_mask_candidate, t_grid, config.fs, N, min_dur_sec, 'apnea');
    diagnostics.combined_state_mask = apnea_mask;
    diagnostics.available = diagnostics.peak_path_available || ...
        diagnostics.raw_flat_path_available;

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
        shade_mask_on_axis(t_grid, apnea_mask);
        yline(0, ':')
        title('Combined apnea mask over lungs raw signal')
        xlabel('Time (s)'); ylabel('Resp-Lungs'); grid on
        hold off

        subplot(4, 1, 2); hold on
        plot_resp_trace_or_message(t_raw, data, idx_diaph, 'Resp-Diaphragm');
        shade_mask_on_axis(t_grid, apnea_mask);
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
        shade_mask_on_axis(t_grid, apnea_mask);
        title('Peak-amplitude ratios (fixed protocol/session reference)')
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
            shade_mask_on_axis(t_grid, apnea_mask);
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
    data, config, t_grid, idx_lungs, idx_diaph, use_lungs, use_diaph, raw_cfg)

    combined_mask = false(size(t_grid));
    diag = init_raw_flat_diag(t_grid);

    if use_lungs
        [lungs_mask, lungs_diag] = raw_flat_belt_mask(data(:, idx_lungs), config, t_grid, raw_cfg);
        diag.lungs = lungs_diag;
        diag.lungs.mask = lungs_mask;
    end

    if use_diaph
        [diaph_mask, diaph_diag] = raw_flat_belt_mask(data(:, idx_diaph), config, t_grid, raw_cfg);
        diag.diaph = diaph_diag;
        diag.diaph.mask = diaph_mask;
    end

    use_lungs = use_lungs && diag.lungs.valid;
    use_diaph = use_diaph && diag.diaph.valid;

    if use_lungs && use_diaph
        combined_mask = diag.lungs.mask & diag.diaph.mask;
    elseif use_lungs
        combined_mask = diag.lungs.mask;
    elseif use_diaph
        combined_mask = diag.diaph.mask;
    end

    diag.combined_candidate = combined_mask;
end

function diag = init_raw_flat_diag(t_grid)
    empty_belt = struct( ...
        'valid', false, ...
        'mask', false(size(t_grid)), ...
        'motion_mask', false(size(t_grid)), ...
        'slope_mask', false(size(t_grid)), ...
        'plateau_mask', false(size(t_grid)), ...
        'motion_ratio', nan(size(t_grid)), ...
        'slope_ratio', nan(size(t_grid)), ...
        'hist_peak_frac', nan(size(t_grid)), ...
        'plateau_run_sec', nan(size(t_grid)) );

    diag = struct();
    diag.lungs = empty_belt;
    diag.diaph = empty_belt;
    diag.combined_candidate = false(size(t_grid));
end

function [mask, diag] = raw_flat_belt_mask(x, config, t_grid, raw_cfg)
    diag = init_raw_flat_diag(t_grid);
    diag = diag.lungs;
    mask = false(size(t_grid));

    x = x(:);
    fs = config.fs;
    N = numel(x);

    if raw_cfg.win_sec <= 0 || N < 3 || numel(t_grid) < 2
        return;
    end

    [baseline_start_idx, baseline_end_idx] = get_static_baseline_interval(N, config);
    baseline_segment = x(baseline_start_idx:baseline_end_idx);
    static_motion_ref = robust_excursion(baseline_segment, raw_cfg);
    static_slope_ref = raw_slope_level(baseline_segment);

    if ~isfinite(static_motion_ref) || static_motion_ref <= 0 || ...
            ~isfinite(static_slope_ref) || static_slope_ref <= 0
        return;
    end

    motion_mask = false(size(t_grid));
    slope_mask = false(size(t_grid));
    plateau_mask = false(size(t_grid));
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

        [motion_ref, slope_ref] = raw_reference_at_time( ...
            x, t, fs, static_motion_ref, static_slope_ref, raw_cfg);

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
        end
    end

    mask = motion_mask & (slope_mask | plateau_mask);
    diag.mask = mask;
    diag.motion_mask = motion_mask;
    diag.slope_mask = slope_mask;
    diag.plateau_mask = plateau_mask;
end

function [motion_ref, slope_ref] = raw_reference_at_time( ...
    x, t, fs, static_motion_ref, static_slope_ref, raw_cfg)

    motion_ref = static_motion_ref;
    slope_ref = static_slope_ref;

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
    end
    if isfinite(candidate_slope) && candidate_slope > 0
        slope_ref = candidate_slope;
    end

    if isfinite(raw_cfg.ref_floor_ratio) && raw_cfg.ref_floor_ratio > 0
        motion_ref = max(motion_ref, raw_cfg.ref_floor_ratio * static_motion_ref);
        slope_ref = max(slope_ref, raw_cfg.ref_floor_ratio * static_slope_ref);
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
