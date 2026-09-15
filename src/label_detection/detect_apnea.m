function [events, diagnostics, boundary_info] = detect_apnea( ...
    data, resp_features, resp_ref, config)
% DETECT_APNEA Combine low breath amplitude and raw-belt flatness evidence.
% data is Nsample-by-Nchannel; resp_features provides normalized breath
% amplitudes on t_grid; resp_ref supplies independent fixed raw excursion and
% slope references; config supplies channel, sampling, window, duration, and
% threshold settings.
% events are localized sample/time intervals. diagnostics records availability,
% peak/raw/combined grid masks, supporting belts, thresholds/windows, and the
% nested raw_flat diagnostics documented by init_raw_flat_diag. boundary_info
% retains candidate, localized, and final support plus per-event uncertainty.

    events = empty_events();

    N = size(data, 1);
    t_grid = resp_features.time_sec;
    lungs = resp_features.lungs;
    diaph = resp_features.diaph;
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

    lungs_raw_ref = raw_reference_for_belt(resp_ref, 'lungs');
    diaph_raw_ref = raw_reference_for_belt(resp_ref, 'diaph');
    lungs_raw_valid = ~lungs_broken && raw_signal_available(data, idx_lungs) && ...
        raw_reference_is_usable(lungs_raw_ref);
    diaph_raw_valid = raw_signal_available(data, idx_diaph) && ...
        raw_reference_is_usable(diaph_raw_ref);

    % ----------------------------
    % Config defaults
    % ----------------------------
    amp_ratio_thr = get_config_value(config, 'apnea', 'amp_ratio_thr', 0.10);
    min_dur_sec = get_config_value(config, 'apnea', 'min_dur_sec', 10);

    raw_cfg = struct();
    raw_cfg.win_sec = get_config_value(config, 'apnea', 'raw_flat_win_sec', min_dur_sec);
    raw_cfg.ref_win_sec = get_config_value(config, 'apnea', 'raw_flat_ref_win_sec', 60);
    raw_cfg.ref_lag_sec = get_config_value(config, 'apnea', 'raw_flat_ref_lag_sec', 10);
    raw_cfg.ref_floor_ratio = get_config_value(config, 'apnea', 'raw_flat_ref_floor_ratio', 0.25);
    raw_cfg.excursion_ratio_thr = get_config_value(config, 'apnea', 'raw_flat_motion_ratio_thr', 0.10);
    raw_cfg.slope_ratio_thr = get_config_value(config, 'apnea', 'raw_flat_slope_ratio_thr', 0.15);
    raw_cfg.hist_peak_frac_thr = get_config_value(config, 'apnea', 'raw_flat_hist_peak_frac_thr', 0.35);
    raw_cfg.min_plateau_sec = get_config_value(config, 'apnea', 'raw_flat_min_plateau_sec', min(5, min_dur_sec));
    raw_cfg.hist_bins = get_config_value(config, 'apnea', 'raw_flat_hist_bins', 40);
    raw_cfg.hist_band_pad_frac = 0.05;
    raw_cfg.min_ref_sec = min(raw_cfg.ref_win_sec, max(raw_cfg.win_sec, 30));

    raw_diag = init_raw_flat_diag( ...
        t_grid, N, lungs_raw_ref, diaph_raw_ref);

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
        'amp_analysis_window_sec', get_config_value(config, 'apnea', 'amp_analysis_win_sec', min_dur_sec), ...
        'raw_flat_analysis_window_sec', raw_cfg.win_sec, ...
        'min_state_duration_sec', min_dur_sec, ...
        'raw_flat', raw_diag);

    if ~(lungs_breath_valid || diaph_breath_valid || ...
            lungs_raw_valid || diaph_raw_valid)
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
    % Raw-flat apnea path
    % ----------------------------
    apnea_raw = false(size(t_grid));
    [apnea_raw_candidate, raw_diag] = raw_flat_apnea_condition_on_grid( ...
        data, config, t_grid, idx_lungs, idx_diaph, ...
        lungs_raw_ref, diaph_raw_ref, lungs_raw_valid, diaph_raw_valid, raw_cfg);

    apnea_raw = apnea_raw_candidate;
    diagnostics.raw_flat = raw_diag;
    diagnostics.raw_flat_path_available = ...
        raw_diag.lungs.valid || raw_diag.diaph.valid;
    diagnostics.raw_flat_support_belts = support_belts( ...
        raw_diag.lungs.valid, raw_diag.diaph.valid);
    diagnostics.raw_flat_state_mask = apnea_raw;

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
    if isfield(config, 'apnea') && isfield(config.apnea, 'do_plot') && config.apnea.do_plot
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

        ax_amplitude = subplot(4, 1, 3); hold on
        h_lungs_breaths = plot_breath_amplitude_points( ...
            ax_amplitude, lungs, lungs_breath_valid, 'k', 'lungs breaths');
        h_diaph_breaths = plot_breath_amplitude_points( ...
            ax_amplitude, diaph, diaph_breath_valid, 'b', 'diaphragm breaths');
        h_amp_threshold = yline(ax_amplitude, amp_ratio_thr, 'r--', ...
            'DisplayName', 'amplitude threshold');
        shade_mask_on_axis(t_grid, diagnostics.localized_state_mask);
        title('Breath-amplitude apnea evidence')
        xlabel('Time (s)'); ylabel('Breath amplitude / session reference'); grid on
        amplitude_handles = [h_lungs_breaths; h_diaph_breaths; h_amp_threshold];
        legend(ax_amplitude, amplitude_handles(isgraphics(amplitude_handles)), ...
            'Location', 'eastoutside')
        hold off

        ax_raw_flat = subplot(4, 1, 4); hold on
        if diagnostics.raw_flat_path_available
            [h_lungs_excursion, h_lungs_slope, h_lungs_plateau] = ...
                plot_raw_flat_belt_evidence( ...
                    ax_raw_flat, t_grid, raw_diag.lungs, ...
                    raw_cfg.excursion_ratio_thr, raw_cfg.slope_ratio_thr, ...
                    'k', 'lungs', 'v', 0.08);
            [h_diaph_excursion, h_diaph_slope, h_diaph_plateau] = ...
                plot_raw_flat_belt_evidence( ...
                    ax_raw_flat, t_grid, raw_diag.diaph, ...
                    raw_cfg.excursion_ratio_thr, raw_cfg.slope_ratio_thr, ...
                    'b', 'diaphragm', '^', 0.16);
            h_criterion = yline(ax_raw_flat, 1, 'r--', ...
                'DisplayName', 'criterion threshold');
            shade_mask_on_axis(t_grid, diagnostics.localized_state_mask);
            title('Raw-flat apnea evidence')
            xlabel('Time (s)'); ylabel('Value / criterion threshold'); grid on
            raw_handles = [h_lungs_excursion; h_diaph_excursion; ...
                h_lungs_slope; h_diaph_slope; h_criterion; ...
                h_lungs_plateau; h_diaph_plateau];
            legend(ax_raw_flat, raw_handles(isgraphics(raw_handles)), ...
                'Location', 'eastoutside')
        else
            ylim(ax_raw_flat, [0 1]);
            shade_mask_on_axis(t_grid, diagnostics.localized_state_mask);
            text(ax_raw_flat, 0.5, 0.5, 'Raw-flat apnea evidence unavailable', ...
                'Units', 'normalized', 'HorizontalAlignment', 'center')
            title('Raw-flat apnea evidence')
            xlabel('Time (s)'); ylabel('Value / criterion threshold'); grid on
        end
        hold off

        ax = findall(gcf, 'Type', 'axes');
        ax = ax(arrayfun(@(a) ~strcmp(a.Tag, 'legend'), ax));
        linkaxes(ax, 'x');
        recording_end_t = (N - 1) / config.fs;
        if recording_end_t > 0
            xlim(ax(1), [0 recording_end_t]);
        end
        align_axes_x_widths(ax);

        save_figure(config, 'apnea');
    end
end

function handle = plot_breath_amplitude_points( ...
    ax, belt, available, color, display_name)
% PLOT_BREATH_AMPLITUDE_POINTS Plot valid normalized breaths as markers.

    handle = gobjects(0, 1);
    if ~available || ~isstruct(belt) || ~isfield(belt, 'peak_t') || ...
            ~isfield(belt, 'amp_ratio_session')
        return;
    end
    peak_t = belt.peak_t(:);
    ratio = belt.amp_ratio_session(:);
    if numel(peak_t) ~= numel(ratio)
        error('MAGMA:ApneaPlot:SizeMismatch', ...
            'peak_t and amp_ratio_session must have equal lengths.');
    end
    valid = isfinite(peak_t) & isfinite(ratio) & ratio > 0;
    if ~any(valid)
        return;
    end
    handle = plot(ax, peak_t(valid), ratio(valid), '.', ...
        'LineStyle', 'none', 'Color', color, 'MarkerSize', 11, ...
        'DisplayName', display_name);
end

function [h_excursion, h_slope, h_plateau] = ...
    plot_raw_flat_belt_evidence( ...
        ax, t_grid, belt_diag, excursion_threshold, slope_threshold, ...
        color, belt_name, plateau_marker, plateau_y)
% PLOT_RAW_FLAT_BELT_EVIDENCE Plot one belt's threshold-relative criteria.
% Excursion and slope scores are visualization-only; values <=1 satisfy the
% corresponding detector threshold. Plateau markers show canonical qualifying
% plateau support without plotting the internal histogram fraction trace.

    h_excursion = gobjects(0, 1);
    h_slope = gobjects(0, 1);
    h_plateau = gobjects(0, 1);
    if ~isstruct(belt_diag) || ~isfield(belt_diag, 'valid') || ...
            ~belt_diag.valid
        return;
    end

    excursion_score = belt_diag.excursion_ratio ./ excursion_threshold;
    slope_score = belt_diag.slope_ratio ./ slope_threshold;
    h_excursion = plot(ax, t_grid, excursion_score, '-', ...
        'Color', color, 'DisplayName', [belt_name ' excursion']);
    h_slope = plot(ax, t_grid, slope_score, '--', ...
        'Color', color, 'DisplayName', [belt_name ' slope']);

    plateau_mask = logical(belt_diag.plateau_mask(:));
    if any(plateau_mask)
        h_plateau = plot(ax, t_grid(plateau_mask), ...
            plateau_y * ones(nnz(plateau_mask), 1), plateau_marker, ...
            'LineStyle', 'none', 'Color', color, ...
            'MarkerFaceColor', color, 'MarkerSize', 4, ...
            'DisplayName', [belt_name ' plateau']);
    end
end

function belt = support_belts(use_lungs, use_diaph)
% SUPPORT_BELTS Encode two belt-availability flags as 'both', one name, or ''.

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
    data, config, t_grid, idx_lungs, idx_diaph, lungs_raw_ref, diaph_raw_ref, ...
    use_lungs, use_diaph, raw_cfg)
% RAW_FLAT_APNEA_CONDITION_ON_GRID Combine usable raw-flat evidence across belts.
% data and idx_* select sample-level belt signals; use_* gates each path.
% The per-belt raw references provide fixed normalization; config/raw_cfg
% define sampling plus current and adaptive trailing windows.
% combined_mask is on t_grid and requires both valid belts when both are used;
% diag contains per-belt and combined candidate/plateau masks.

    combined_mask = false(size(t_grid));
    diag = init_raw_flat_diag( ...
        t_grid, size(data, 1), lungs_raw_ref, diaph_raw_ref);

    if use_lungs
        [lungs_mask, lungs_diag] = raw_flat_belt_mask( ...
            data(:, idx_lungs), lungs_raw_ref, config.fs, t_grid, raw_cfg);
        diag.lungs = lungs_diag;
        diag.lungs.mask = lungs_mask;
    end

    if use_diaph
        [diaph_mask, diaph_diag] = raw_flat_belt_mask( ...
            data(:, idx_diaph), diaph_raw_ref, config.fs, t_grid, raw_cfg);
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

function diag = init_raw_flat_diag(t_grid, N, lungs_raw_ref, diaph_raw_ref)
% INIT_RAW_FLAT_DIAG Initialize raw-belt apnea diagnostics at grid and sample levels.
% diag.lungs/diaph each contain path validity; fixed reference values copied
% from resp_ref; grid-level candidate component masks, ratios, references used,
% adaptive-reference flags, histogram peak fraction, and plateau duration;
% plus plateau_mask_native over N raw samples.
% Combined fields hold the cross-belt grid candidate/plateau masks and the
% Nsample native plateau mask.

    if nargin < 2
        N = numel(t_grid);
    end
    if nargin < 3
        lungs_raw_ref = raw_reference_for_belt(struct(), 'lungs');
    end
    if nargin < 4
        diaph_raw_ref = raw_reference_for_belt(struct(), 'diaph');
    end
    empty_belt = struct( ...
        'valid', false, ...
        'reference_available', false, ...
        'reference_quality', 'not_evaluated', ...
        'reference_source', 'common_session_reference_interval', ...
        'reference_n_samples', 0, ...
        'reference_finite_fraction', NaN, ...
        'session_excursion_reference', NaN, ...
        'session_slope_reference', NaN, ...
        'mask', false(size(t_grid)), ...
        'excursion_mask', false(size(t_grid)), ...
        'slope_mask', false(size(t_grid)), ...
        'plateau_mask', false(size(t_grid)), ...
        'plateau_mask_native', false(N, 1), ...
        'excursion_ratio', nan(size(t_grid)), ...
        'slope_ratio', nan(size(t_grid)), ...
        'excursion_reference_used', nan(size(t_grid)), ...
        'slope_reference_used', nan(size(t_grid)), ...
        'adaptive_reference_used', false(size(t_grid)), ...
        'hist_peak_frac', nan(size(t_grid)), ...
        'plateau_run_sec', nan(size(t_grid)) );

    diag = struct();
    diag.lungs = copy_raw_reference_to_diag(empty_belt, lungs_raw_ref);
    diag.diaph = copy_raw_reference_to_diag(empty_belt, diaph_raw_ref);
    diag.combined_candidate = false(size(t_grid));
    diag.combined_plateau = false(size(t_grid));
    diag.combined_plateau_native = false(N, 1);
end

function diag = copy_raw_reference_to_diag(diag, raw_ref)
% COPY_RAW_REFERENCE_TO_DIAG Copy fixed-reference provenance without recomputing it.

    raw_ref = normalize_raw_reference(raw_ref);
    diag.reference_available = raw_reference_is_usable(raw_ref);
    diag.reference_quality = raw_ref.quality;
    diag.reference_n_samples = raw_ref.n_samples;
    diag.reference_finite_fraction = raw_ref.finite_fraction;
    diag.session_excursion_reference = raw_ref.excursion;
    diag.session_slope_reference = raw_ref.slope;
end

function raw_ref = raw_reference_for_belt(resp_ref, belt_name)
% RAW_REFERENCE_FOR_BELT Return one belt's canonical fixed raw reference.
% Missing or malformed input produces an unavailable reference so the
% independent breath-amplitude path can still be evaluated.

    raw_ref = normalize_raw_reference([]);
    if isstruct(resp_ref) && isscalar(resp_ref) && ...
            isfield(resp_ref, belt_name) && ...
            isstruct(resp_ref.(belt_name)) && ...
            isscalar(resp_ref.(belt_name)) && ...
            isfield(resp_ref.(belt_name), 'raw')
        raw_ref = normalize_raw_reference(resp_ref.(belt_name).raw);
    end
end

function raw_ref = normalize_raw_reference(value)
% NORMALIZE_RAW_REFERENCE Fill the fixed raw-reference schema safely.

    raw_ref = struct( ...
        'available', false, ...
        'quality', 'raw_reference_unavailable', ...
        'n_samples', 0, ...
        'finite_fraction', NaN, ...
        'excursion', NaN, ...
        'slope', NaN);
    if ~isstruct(value) || ~isscalar(value)
        return;
    end

    names = fieldnames(raw_ref);
    for i = 1:numel(names)
        if isfield(value, names{i})
            raw_ref.(names{i}) = value.(names{i});
        end
    end
end

function tf = raw_reference_is_usable(raw_ref)
% RAW_REFERENCE_IS_USABLE Validate fixed raw excursion and slope references.

    raw_ref = normalize_raw_reference(raw_ref);
    tf = isequal(raw_ref.available, true) && ...
        isscalar(raw_ref.excursion) && isfinite(raw_ref.excursion) && ...
        raw_ref.excursion > 0 && ...
        isscalar(raw_ref.slope) && isfinite(raw_ref.slope) && ...
        raw_ref.slope > 0;
end

function tf = raw_signal_available(data, channel_idx)
% RAW_SIGNAL_AVAILABLE Check that a resolved belt column has finite samples.

    tf = isnumeric(data) && ~isempty(data) && ...
        isscalar(channel_idx) && isfinite(channel_idx) && ...
        channel_idx == round(channel_idx) && channel_idx >= 1 && ...
        channel_idx <= size(data, 2) && any(isfinite(data(:, channel_idx)));
end

function mask = amplitude_apnea_support_mask( ...
    lungs, diaph, use_lungs, use_diaph, threshold, t_grid)
% AMPLITUDE_APNEA_SUPPORT_MASK Combine breath-localized low-amplitude support.
% Each used belt contributes session-normalized breath ratios <= threshold;
% both masks must agree when both belts are enabled. mask is on t_grid.

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
% BREATH_AMPLITUDE_MASK Map qualifying breath ratios to midpoint-bounded cells.
% belt supplies peak_t in seconds and session-normalized amplitude ratios;
% mask marks each qualifying breath's cell on t_grid.

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
% LOCALIZE_APNEA_CANDIDATES Refine window candidates using the strongest local support.
% Inputs are candidate events; grid-level amplitude/raw masks; native-sample
% plateau support; t_grid (s); recording N/fs; and source-window durations.
% Native plateaus take precedence, then raw window support, then breath cells,
% with candidate bounds as fallback. records store label/detector, method,
% candidate/localized times (s), uncertainty (s), and evidence source.

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
% LONGEST_GRID_RUN Return half-open time bounds of the longest true grid run.
% mask aligns with t_grid in seconds; grid_step extends the final grid point
% to its cell end. found is false and bounds are NaN when no run exists.

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
% EVENT_FROM_TIMES Clamp time bounds and rewrite canonical sample/time fields.
% N and fs define the recording; duration is the inclusive sample count in seconds.

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
    x, raw_ref, fs, t_grid, raw_cfg)
% RAW_FLAT_BELT_MASK Detect low excursion with low slope or a held plateau.
% x is one sample-level raw belt signal; raw_ref supplies fixed session
% excursion/slope levels; fs and raw_cfg define trailing/adaptive references
% and thresholds. mask is on t_grid; diag includes time-varying metrics and
% native plateau support plus copied fixed-reference provenance.

    x = x(:);
    N = numel(x);
    all_diag = init_raw_flat_diag(t_grid, N, raw_ref, []);
    diag = all_diag.lungs;
    mask = false(size(t_grid));

    if raw_cfg.win_sec <= 0 || N < 3 || numel(t_grid) < 2
        return;
    end
    if ~raw_reference_is_usable(raw_ref)
        return;
    end

    session_excursion_ref = raw_ref.excursion;
    session_slope_ref = raw_ref.slope;
    excursion_mask = false(size(t_grid));
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

        [excursion_ref, slope_ref, adaptive_reference_used] = raw_reference_at_time( ...
            x, t, fs, session_excursion_ref, session_slope_ref, raw_cfg);
        diag.excursion_reference_used(i) = excursion_ref;
        diag.slope_reference_used(i) = slope_ref;
        diag.adaptive_reference_used(i) = adaptive_reference_used;

        excursion = robust_resp_excursion(segment);
        slope = raw_resp_slope_level(segment);
        if isfinite(excursion) && isfinite(excursion_ref) && excursion_ref > 0
            diag.excursion_ratio(i) = excursion / excursion_ref;
        end
        if isfinite(slope) && isfinite(slope_ref) && slope_ref > 0
            diag.slope_ratio(i) = slope / slope_ref;
        end

        sample_t = ((i1:i2)' - 1) / fs;
        [hist_peak_frac, plateau_start_t, plateau_end_t, plateau_run_sec] = ...
            strongest_histogram_plateau(segment, sample_t, fs, raw_cfg);
        diag.hist_peak_frac(i) = hist_peak_frac;
        diag.plateau_run_sec(i) = plateau_run_sec;

        if isfinite(diag.excursion_ratio(i)) && ...
                diag.excursion_ratio(i) <= raw_cfg.excursion_ratio_thr
            excursion_mask(mark_time_range_on_grid(t_grid, lb, t)) = true;
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

    mask = excursion_mask & (slope_mask | plateau_mask);
    diag.mask = mask;
    diag.excursion_mask = excursion_mask;
    diag.slope_mask = slope_mask;
    diag.plateau_mask = plateau_mask;
end

function [excursion_ref, slope_ref, adaptive_reference_used] = raw_reference_at_time( ...
    x, t, fs, session_excursion_ref, session_slope_ref, raw_cfg)
% RAW_REFERENCE_AT_TIME Choose lagged local or session raw-belt references.
% x is sampled at fs; t is the analysis endpoint in seconds. Local robust
% excursion and median absolute slope are used only with sufficient finite
% history and are floored relative to the session reference.

    excursion_ref = session_excursion_ref;
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

    candidate_excursion = robust_resp_excursion(segment);
    candidate_slope = raw_resp_slope_level(segment);

    if isfinite(candidate_excursion) && candidate_excursion > 0
        excursion_ref = candidate_excursion;
        adaptive_reference_used = true;
    end
    if isfinite(candidate_slope) && candidate_slope > 0
        slope_ref = candidate_slope;
        adaptive_reference_used = true;
    end

    if isfinite(raw_cfg.ref_floor_ratio) && raw_cfg.ref_floor_ratio > 0
        excursion_ref = max(excursion_ref, ...
            raw_cfg.ref_floor_ratio * session_excursion_ref);
        slope_ref = max(slope_ref, raw_cfg.ref_floor_ratio * session_slope_ref);
    end
end

function [peak_frac, run_start_t, run_end_t, run_dur_sec] = strongest_histogram_plateau(x, sample_t, fs, raw_cfg)
% STRONGEST_HISTOGRAM_PLATEAU Find the longest run near a window's modal level.
% x and sample_t are aligned samples; fs is hertz. peak_frac is the fraction
% of finite values in the modal histogram bin. Run times/duration are seconds,
% or NaN when fewer than three finite samples prevent estimation.

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

        band_pad = raw_cfg.hist_band_pad_frac * robust_resp_excursion(finite_x);
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

function f = finite_fraction(x)
% FINITE_FRACTION Return the fraction of array elements that are finite.

    if isempty(x)
        f = 0;
    else
        f = nnz(isfinite(x)) / numel(x);
    end
end

function [i1, i2] = time_window_to_indices(t1, t2, fs, N)
% TIME_WINDOW_TO_INDICES Convert second-based bounds to clamped sample indices.

    i1 = max(1, floor(t1 * fs) + 1);
    i2 = min(N, floor(t2 * fs) + 1);
end

function grid_idx = mark_time_range_on_grid(t_grid, t0, t1)
% MARK_TIME_RANGE_ON_GRID Mark grid cells intersecting a finite time interval.
% A half-grid tolerance includes endpoints represented between grid samples.

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
% LONGEST_TRUE_RUN Locate the longest contiguous true sample run.
% fs converts its inclusive sample count to duration in seconds; empty masks
% return NaN indices and duration.

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
% PLOT_RESP_TRACE_OR_MESSAGE Plot one raw respiratory channel or an absent-channel note.
% t_raw is sample time in seconds; idx selects a column of data.

    if isempty(idx)
        text(0.5, 0.5, [label_text ' channel not found'], ...
            'Units', 'normalized', 'HorizontalAlignment', 'center')
    else
        plot(t_raw, data(:, idx), 'k')
    end
end
