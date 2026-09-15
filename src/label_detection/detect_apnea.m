function [events, diagnostics, candidate_events] = detect_apnea( ...
    data, resp_features, resp_ref, config)
% DETECT_APNEA Prefer breath amplitude and fall back to raw excursion per window.
% data is Nsample-by-Nchannel; resp_features provides per-belt normalized-breath
% window results on t_grid; resp_ref supplies fixed raw-excursion references;
% and config supplies channel, sampling, duration, threshold, and finite-data
% settings. Each belt uses raw excursion only where its breath-amplitude window
% is unevaluable. Both evaluable belts must support a window before it contributes
% to the final duration-filtered events.
% diagnostics retains unique per-belt fallback and combined evidence.
% candidate_events contains localized pre-final intervals.

    events = empty_events();
    candidate_events = empty_candidate_events();

    N = size(data, 1);
    t_grid = resp_features.time_sec;
    lungs = resp_features.lungs;
    diaph = resp_features.diaph;
    if ~isfield(config, 'channels')
        config = resolve_signal_channels(config);
    end
    idx_lungs = config.channels.lungs_idx;
    idx_diaph = config.channels.diaph_idx;

    % One duration governs both evidence windows and final event retention.
    amp_ratio_thr = get_config_value(config, 'apnea', 'amp_ratio_thr', 0.10);
    min_dur_sec = get_config_value(config, 'apnea', 'min_dur_sec', 10);
    raw_cfg = struct();
    raw_cfg.win_sec = min_dur_sec;
    raw_cfg.excursion_ratio_thr = get_config_value( ...
        config, 'apnea', 'raw_excursion_ratio_thr', 0.10);
    raw_cfg.min_finite_fraction = respiratory_raw_min_finite_fraction(config);

    lungs_broken = lungs.ignored;
    lungs_amplitude_available = lungs.session_amplitude_available;
    diaph_amplitude_available = diaph.session_amplitude_available;

    lungs_raw_ref = raw_reference_for_belt(resp_ref, 'lungs');
    diaph_raw_ref = raw_reference_for_belt(resp_ref, 'diaph');
    lungs_raw_available = ~lungs_broken && ...
        raw_signal_available(data, idx_lungs) && ...
        raw_reference_is_usable(lungs_raw_ref, raw_cfg.min_finite_fraction);
    diaph_raw_available = raw_signal_available(data, idx_diaph) && ...
        raw_reference_is_usable(diaph_raw_ref, raw_cfg.min_finite_fraction);

    raw_excursion = raw_excursion_diagnostics_on_grid( ...
        data, config.fs, t_grid, idx_lungs, idx_diaph, ...
        lungs_raw_ref, diaph_raw_ref, lungs_raw_available, ...
        diaph_raw_available, raw_cfg);

    lungs_evidence = select_belt_apnea_evidence( ...
        lungs, lungs_amplitude_available, raw_excursion.lungs, t_grid);
    diaph_evidence = select_belt_apnea_evidence( ...
        diaph, diaph_amplitude_available, raw_excursion.diaph, t_grid);
    [combined_endpoint_mask, combined_evaluable_endpoint_mask] = ...
        combine_belt_evidence(lungs_evidence, diaph_evidence);

    amplitude_endpoint_mask = combined_endpoint_mask & ...
        (lungs_evidence.amplitude_evaluable_endpoint_mask | ...
         diaph_evidence.amplitude_evaluable_endpoint_mask);
    raw_fallback_endpoint_mask = combined_endpoint_mask & ...
        (lungs_evidence.raw_fallback_used_endpoint_mask | ...
         diaph_evidence.raw_fallback_used_endpoint_mask);
    amplitude_state_mask = analysis_window_endpoints_to_state_mask( ...
        amplitude_endpoint_mask, t_grid, min_dur_sec);
    raw_fallback_state_mask = analysis_window_endpoints_to_state_mask( ...
        raw_fallback_endpoint_mask, t_grid, min_dur_sec);
    candidate_state_mask = analysis_window_endpoints_to_state_mask( ...
        combined_endpoint_mask, t_grid, min_dur_sec);

    diagnostics = struct( ...
        'available', lungs_amplitude_available || diaph_amplitude_available || ...
            raw_excursion.lungs.valid || raw_excursion.diaph.valid, ...
        'amplitude_path_available', ...
            lungs_amplitude_available || diaph_amplitude_available, ...
        'raw_excursion_path_available', ...
            raw_excursion.lungs.valid || raw_excursion.diaph.valid, ...
        'amplitude_support_belts', support_belts( ...
            lungs_amplitude_available, diaph_amplitude_available), ...
        'raw_excursion_support_belts', support_belts( ...
            raw_excursion.lungs.valid, raw_excursion.diaph.valid), ...
        'amplitude_endpoint_mask', amplitude_endpoint_mask, ...
        'raw_fallback_endpoint_mask', raw_fallback_endpoint_mask, ...
        'combined_evaluable_endpoint_mask', combined_evaluable_endpoint_mask, ...
        'combined_endpoint_mask', combined_endpoint_mask, ...
        'amplitude_state_mask', amplitude_state_mask, ...
        'raw_fallback_state_mask', raw_fallback_state_mask, ...
        'candidate_state_mask', candidate_state_mask, ...
        'combined_state_mask', false(size(t_grid)), ...
        'localized_state_mask', false(size(t_grid)), ...
        'amplitude_localized_mask', false(size(t_grid)), ...
        'raw_fallback_localized_mask', false(size(t_grid)), ...
        'amp_ratio_threshold', amp_ratio_thr, ...
        'raw_excursion_ratio_threshold', raw_cfg.excursion_ratio_thr, ...
        'amp_analysis_window_sec', min_dur_sec, ...
        'raw_excursion_analysis_window_sec', min_dur_sec, ...
        'min_state_duration_sec', min_dur_sec, ...
        'belt_evidence', struct('lungs', lungs_evidence, ...
            'diaph', diaph_evidence), ...
        'raw_excursion', raw_excursion);

    if ~diagnostics.available
        fprintf(['Skipping apnea detection: no usable respiratory belt ' ...
            'evidence for breath-amplitude or raw-excursion fallback logic.\n']);
        diagnostics = compact_apnea_diagnostics(diagnostics);
        return;
    end

    % Back-projected qualifying windows must still satisfy the final duration guard.
    [rolling_candidates, apnea_mask] = sustained_condition_to_events( ...
        candidate_state_mask, t_grid, config.fs, N, min_dur_sec, 'apnea');
    diagnostics.combined_state_mask = apnea_mask;

    amplitude_local_mask = amplitude_localization_mask( ...
        lungs, diaph, lungs_evidence, diaph_evidence, ...
        amp_ratio_thr, t_grid, min_dur_sec) & amplitude_state_mask;
    raw_local_mask = raw_fallback_state_mask;
    diagnostics.amplitude_localized_mask = amplitude_local_mask;
    diagnostics.raw_fallback_localized_mask = raw_local_mask;
    [events, candidate_events] = localize_apnea_candidates( ...
        rolling_candidates, amplitude_local_mask, amplitude_state_mask, ...
        raw_local_mask, raw_fallback_state_mask, t_grid, N, config.fs, ...
        min_dur_sec);
    diagnostics.localized_state_mask = events_to_grid_mask(events, t_grid);

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
            ax_amplitude, lungs, lungs_amplitude_available, 'k', 'lungs breaths');
        h_diaph_breaths = plot_breath_amplitude_points( ...
            ax_amplitude, diaph, diaph_amplitude_available, 'b', 'diaphragm breaths');
        h_amp_threshold = yline(ax_amplitude, amp_ratio_thr, 'r--', ...
            'DisplayName', 'amplitude threshold');
        shade_mask_on_axis(t_grid, diagnostics.localized_state_mask);
        title('Breath-amplitude apnea evidence')
        xlabel('Time (s)'); ylabel('Breath amplitude / session reference'); grid on
        amplitude_handles = [h_lungs_breaths; h_diaph_breaths; h_amp_threshold];
        legend(ax_amplitude, amplitude_handles(isgraphics(amplitude_handles)), ...
            'Location', 'eastoutside')
        hold off

        ax_raw_excursion = subplot(4, 1, 4); hold on
        if diagnostics.raw_excursion_path_available
            h_lungs_excursion = plot_raw_excursion_evidence( ...
                ax_raw_excursion, t_grid, raw_excursion.lungs, ...
                'k', 'lungs raw excursion');
            h_diaph_excursion = plot_raw_excursion_evidence( ...
                ax_raw_excursion, t_grid, raw_excursion.diaph, ...
                'b', 'diaphragm raw excursion');
            h_threshold = yline(ax_raw_excursion, ...
                raw_cfg.excursion_ratio_thr, 'r--', ...
                'DisplayName', 'raw excursion threshold');
            shade_mask_on_axis(t_grid, diagnostics.localized_state_mask);
            title('Raw-excursion apnea fallback')
            xlabel('Time (s)'); ylabel('Raw excursion / session reference'); grid on
            raw_handles = [h_lungs_excursion; h_diaph_excursion; h_threshold];
            legend(ax_raw_excursion, raw_handles(isgraphics(raw_handles)), ...
                'Location', 'eastoutside')
        else
            ylim(ax_raw_excursion, [0 1]);
            shade_mask_on_axis(t_grid, diagnostics.localized_state_mask);
            text(ax_raw_excursion, 0.5, 0.5, ...
                'Raw-excursion apnea fallback unavailable', ...
                'Units', 'normalized', 'HorizontalAlignment', 'center')
            title('Raw-excursion apnea fallback')
            xlabel('Time (s)'); ylabel('Raw excursion / session reference'); grid on
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
    diagnostics = compact_apnea_diagnostics(diagnostics);
end

function compact = compact_apnea_diagnostics(full)
% COMPACT_APNEA_DIAGNOSTICS Keep unique scientific evidence without finals/config.

    compact = struct( ...
        'available', full.available, ...
        'amplitude_path_available', full.amplitude_path_available, ...
        'raw_excursion_path_available', full.raw_excursion_path_available, ...
        'amplitude_support_belts', full.amplitude_support_belts, ...
        'raw_excursion_support_belts', full.raw_excursion_support_belts, ...
        'amplitude_state_mask', full.amplitude_state_mask, ...
        'raw_fallback_state_mask', full.raw_fallback_state_mask, ...
        'combined_evaluable_endpoint_mask', ...
            full.combined_evaluable_endpoint_mask, ...
        'combined_endpoint_mask', full.combined_endpoint_mask, ...
        'belt_evidence', struct( ...
            'lungs', compact_belt_selection(full.belt_evidence.lungs), ...
            'diaph', compact_belt_selection(full.belt_evidence.diaph)), ...
        'raw_excursion', struct( ...
            'lungs', compact_raw_excursion(full.raw_excursion.lungs), ...
            'diaph', compact_raw_excursion(full.raw_excursion.diaph)));
end

function compact = compact_belt_selection(full)
% COMPACT_BELT_SELECTION Retain source use and the final per-belt decision.

    compact = struct( ...
        'raw_fallback_used_endpoint_mask', ...
            full.raw_fallback_used_endpoint_mask, ...
        'combined_belt_evaluable_endpoint_mask', ...
            full.combined_belt_evaluable_endpoint_mask, ...
        'combined_belt_endpoint_mask', full.combined_belt_endpoint_mask);
end

function compact = compact_raw_excursion(full)
% COMPACT_RAW_EXCURSION Keep the unique continuous fallback evidence.

    compact = struct( ...
        'valid', full.valid, ...
        'reference_available', full.reference_available, ...
        'reference_quality', full.reference_quality, ...
        'evaluable_endpoint_mask', full.evaluable_endpoint_mask, ...
        'excursion_ratio', full.excursion_ratio);
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

function handle = plot_raw_excursion_evidence( ...
    ax, t_grid, belt_diag, color, display_name)
% PLOT_RAW_EXCURSION_EVIDENCE Plot current/fixed raw-excursion ratios.
% Ratios are shown for every complete finite-data window where the raw metric
% is evaluable, even when breath-amplitude evidence takes classification priority.

    handle = gobjects(0, 1);
    if ~isstruct(belt_diag) || ~isfield(belt_diag, 'valid') || ...
            ~belt_diag.valid
        return;
    end
    handle = plot(ax, t_grid, belt_diag.excursion_ratio, '-', ...
        'Color', color, 'DisplayName', display_name);
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
% Per-window evidence selection
% =========================================================

function evidence = select_belt_apnea_evidence( ...
    belt, amplitude_available, raw_diag, t_grid)
% SELECT_BELT_APNEA_EVIDENCE Prefer amplitude and use raw only as fallback.
% All masks are window-endpoint masks on t_grid. A failed evaluable amplitude
% result remains negative even when raw excursion passes at the same endpoint.

    evidence = empty_belt_evidence_selection(t_grid);
    if amplitude_available
        evidence.amplitude_evaluable_endpoint_mask = endpoint_mask_field( ...
            belt, 'apnea_amplitude_evaluable_endpoint_mask', t_grid);
        evidence.amplitude_pass_endpoint_mask = endpoint_mask_field( ...
            belt, 'apnea_amplitude_endpoint_mask', t_grid) & ...
            evidence.amplitude_evaluable_endpoint_mask;
    end
    evidence.raw_excursion_evaluable_endpoint_mask = ...
        logical(raw_diag.evaluable_endpoint_mask);
    evidence.raw_excursion_pass_endpoint_mask = ...
        logical(raw_diag.pass_endpoint_mask) & ...
        evidence.raw_excursion_evaluable_endpoint_mask;
    evidence.raw_fallback_used_endpoint_mask = ...
        ~evidence.amplitude_evaluable_endpoint_mask & ...
        evidence.raw_excursion_evaluable_endpoint_mask;
    evidence.combined_belt_evaluable_endpoint_mask = ...
        evidence.amplitude_evaluable_endpoint_mask | ...
        evidence.raw_fallback_used_endpoint_mask;
    evidence.combined_belt_endpoint_mask = ...
        (evidence.amplitude_evaluable_endpoint_mask & ...
         evidence.amplitude_pass_endpoint_mask) | ...
        (evidence.raw_fallback_used_endpoint_mask & ...
         evidence.raw_excursion_pass_endpoint_mask);
end

function evidence = empty_belt_evidence_selection(t_grid)
% EMPTY_BELT_EVIDENCE_SELECTION Initialize per-endpoint apnea source masks.

    evidence = struct( ...
        'amplitude_evaluable_endpoint_mask', false(size(t_grid)), ...
        'amplitude_pass_endpoint_mask', false(size(t_grid)), ...
        'raw_excursion_evaluable_endpoint_mask', false(size(t_grid)), ...
        'raw_excursion_pass_endpoint_mask', false(size(t_grid)), ...
        'raw_fallback_used_endpoint_mask', false(size(t_grid)), ...
        'combined_belt_evaluable_endpoint_mask', false(size(t_grid)), ...
        'combined_belt_endpoint_mask', false(size(t_grid)));
end

function mask = endpoint_mask_field(source, field_name, t_grid)
% ENDPOINT_MASK_FIELD Read and validate one logical time-grid mask.

    mask = false(size(t_grid));
    if ~isstruct(source) || ~isfield(source, field_name)
        return;
    end
    value = source.(field_name);
    if numel(value) ~= numel(t_grid)
        error('MAGMA:Apnea:MaskAlignment', ...
            '%s must align one-to-one with resp_features.time_sec.', field_name);
    end
    mask = reshape(logical(value), size(t_grid));
end

function [combined, evaluable] = combine_belt_evidence(lungs, diaph)
% COMBINE_BELT_EVIDENCE Require agreement from every evaluable belt per window.

    lungs_evaluable = lungs.combined_belt_evaluable_endpoint_mask;
    diaph_evaluable = diaph.combined_belt_evaluable_endpoint_mask;
    both_evaluable = lungs_evaluable & diaph_evaluable;
    evaluable = lungs_evaluable | diaph_evaluable;
    combined = ...
        (both_evaluable & lungs.combined_belt_endpoint_mask & ...
            diaph.combined_belt_endpoint_mask) | ...
        (lungs_evaluable & ~diaph_evaluable & ...
            lungs.combined_belt_endpoint_mask) | ...
        (~lungs_evaluable & diaph_evaluable & ...
            diaph.combined_belt_endpoint_mask);
end

% =========================================================
% Raw-excursion fallback
% =========================================================

function diag = raw_excursion_diagnostics_on_grid( ...
    data, fs, t_grid, idx_lungs, idx_diaph, lungs_raw_ref, diaph_raw_ref, ...
    use_lungs, use_diaph, raw_cfg)
% RAW_EXCURSION_DIAGNOSTICS_ON_GRID Evaluate fixed-reference raw excursion.
% Excursion ratios are calculated independently of amplitude availability so
% they remain diagnostic, but select_belt_apnea_evidence gates their use.

    diag = init_raw_excursion_diag( ...
        t_grid, lungs_raw_ref, diaph_raw_ref, raw_cfg.min_finite_fraction);
    if use_lungs
        diag.lungs = raw_excursion_belt_diagnostics( ...
            data(:, idx_lungs), lungs_raw_ref, fs, t_grid, raw_cfg);
    end
    if use_diaph
        diag.diaph = raw_excursion_belt_diagnostics( ...
            data(:, idx_diaph), diaph_raw_ref, fs, t_grid, raw_cfg);
    end
end

function diag = init_raw_excursion_diag( ...
    t_grid, lungs_raw_ref, diaph_raw_ref, min_finite_fraction)
% INIT_RAW_EXCURSION_DIAG Initialize fixed-reference raw-excursion diagnostics.
% Each belt records reference provenance, endpoint evaluability/pass masks, and
% the current-window excursion ratio on t_grid.

    empty_belt = empty_raw_excursion_belt_diag(t_grid);
    diag = struct();
    diag.lungs = copy_raw_reference_to_diag( ...
        empty_belt, lungs_raw_ref, min_finite_fraction);
    diag.diaph = copy_raw_reference_to_diag( ...
        empty_belt, diaph_raw_ref, min_finite_fraction);
end

function diag = empty_raw_excursion_belt_diag(t_grid)
% EMPTY_RAW_EXCURSION_BELT_DIAG Return the per-belt raw diagnostic schema.

    diag = struct( ...
        'valid', false, ...
        'reference_available', false, ...
        'reference_quality', 'not_evaluated', ...
        'reference_source', 'common_session_reference_interval', ...
        'reference_n_samples', 0, ...
        'reference_finite_fraction', NaN, ...
        'session_excursion_reference', NaN, ...
        'evaluable_endpoint_mask', false(size(t_grid)), ...
        'pass_endpoint_mask', false(size(t_grid)), ...
        'excursion_ratio', nan(size(t_grid)));
end

function diag = copy_raw_reference_to_diag(diag, raw_ref, min_finite_fraction)
% COPY_RAW_REFERENCE_TO_DIAG Copy fixed excursion-reference provenance.

    raw_ref = normalize_raw_reference(raw_ref);
    diag.reference_available = ...
        raw_reference_is_usable(raw_ref, min_finite_fraction);
    diag.reference_quality = raw_ref.quality;
    diag.reference_n_samples = raw_ref.n_samples;
    diag.reference_finite_fraction = raw_ref.finite_fraction;
    diag.session_excursion_reference = raw_ref.excursion;
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
% NORMALIZE_RAW_REFERENCE Fill the fixed raw-excursion reference schema safely.

    raw_ref = struct( ...
        'available', false, ...
        'quality', 'raw_reference_unavailable', ...
        'n_samples', 0, ...
        'finite_fraction', NaN, ...
        'excursion', NaN);
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

function tf = raw_reference_is_usable(raw_ref, min_finite_fraction)
% RAW_REFERENCE_IS_USABLE Validate fixed raw excursion and finite coverage.

    raw_ref = normalize_raw_reference(raw_ref);
    tf = isequal(raw_ref.available, true) && ...
        isscalar(raw_ref.excursion) && isfinite(raw_ref.excursion) && ...
        raw_ref.excursion > 0 && ...
        isscalar(raw_ref.finite_fraction) && ...
        isfinite(raw_ref.finite_fraction) && ...
        raw_ref.finite_fraction >= min_finite_fraction;
end

function tf = raw_signal_available(data, channel_idx)
% RAW_SIGNAL_AVAILABLE Check that a resolved belt column has finite samples.

    tf = isnumeric(data) && ~isempty(data) && ...
        isscalar(channel_idx) && isfinite(channel_idx) && ...
        channel_idx == round(channel_idx) && channel_idx >= 1 && ...
        channel_idx <= size(data, 2) && any(isfinite(data(:, channel_idx)));
end

function mask = amplitude_localization_mask( ...
    lungs, diaph, lungs_evidence, diaph_evidence, threshold, t_grid, win_sec)
% AMPLITUDE_LOCALIZATION_MASK Retain low-breath cells from selected windows.
% Per-belt qualifying breath cells are gated by windows in which amplitude was
% evaluable and passed. Their union is used only to refine event boundaries.

    lungs_window = analysis_window_endpoints_to_state_mask( ...
        lungs_evidence.amplitude_evaluable_endpoint_mask & ...
        lungs_evidence.amplitude_pass_endpoint_mask, t_grid, win_sec);
    diaph_window = analysis_window_endpoints_to_state_mask( ...
        diaph_evidence.amplitude_evaluable_endpoint_mask & ...
        diaph_evidence.amplitude_pass_endpoint_mask, t_grid, win_sec);
    lungs_mask = breath_amplitude_mask(lungs, threshold, t_grid) & lungs_window;
    diaph_mask = breath_amplitude_mask(diaph, threshold, t_grid) & diaph_window;
    mask = lungs_mask | diaph_mask;
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

function [events, candidate_events] = localize_apnea_candidates( ...
    candidates, amplitude_local, amplitude_candidate, raw_window_local, ...
    raw_candidate, t_grid, N, fs, window_sec)
% LOCALIZE_APNEA_CANDIDATES Refine candidates using selected evidence support.
% Raw-excursion fallback window support takes precedence, followed by localized
% qualifying breath cells and finally the candidate bounds. All window-derived
% boundaries carry window_sec uncertainty. Every localized interval passed the
% existing final decision and is retained as an accepted compact candidate.

    events = empty_events();
    candidate_events = empty_candidate_events();
    if isempty(candidates)
        return;
    end
    events = repmat(candidates(1), numel(candidates), 1);
    if numel(t_grid) > 1
        grid_step = median(diff(t_grid), 'omitnan');
    else
        grid_step = 1;
    end
    for i = 1:numel(candidates)
        candidate = candidates(i);
        in_candidate = t_grid >= candidate.start_t & t_grid < candidate.end_t;
        has_amp = any(amplitude_candidate & in_candidate);
        has_raw = any(raw_candidate & in_candidate);
        uncertainty = window_sec;
        local_mask = false(size(t_grid));
        if has_raw && any(raw_window_local & in_candidate)
            local_mask = raw_window_local & in_candidate;
        elseif has_amp && any(amplitude_local & in_candidate)
            local_mask = amplitude_local & in_candidate;
        end

        [t0, t1, found] = longest_grid_run(local_mask, t_grid, grid_step);
        if ~found
            t0 = candidate.start_t;
            t1 = candidate.end_t;
        end
        events(i) = event_from_times(candidate, t0, t1, N, fs);
        candidate_events(i, 1) = events_to_candidate_events( ...
            events(i), 'combined', true, '', uncertainty);
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

function diag = raw_excursion_belt_diagnostics( ...
    x, raw_ref, fs, t_grid, raw_cfg)
% RAW_EXCURSION_BELT_DIAGNOSTICS Evaluate complete trailing raw windows.
% A window is evaluable when finite coverage passes QC and its P95-P5 excursion
% is finite. pass_endpoint_mask compares its ratio with the raw threshold.

    x = x(:);
    N = numel(x);
    diag = copy_raw_reference_to_diag( ...
        empty_raw_excursion_belt_diag(t_grid), raw_ref, ...
        raw_cfg.min_finite_fraction);
    if raw_cfg.win_sec <= 0 || N < 3 || numel(t_grid) < 2 || ...
            ~raw_reference_is_usable(raw_ref, raw_cfg.min_finite_fraction)
        return;
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
        if finite_fraction(segment) < raw_cfg.min_finite_fraction
            continue;
        end
        excursion = robust_resp_excursion(segment);
        if ~isfinite(excursion)
            continue;
        end
        diag.evaluable_endpoint_mask(i) = true;
        diag.excursion_ratio(i) = excursion / raw_ref.excursion;
        diag.pass_endpoint_mask(i) = ...
            diag.excursion_ratio(i) <= raw_cfg.excursion_ratio_thr;
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

function value = respiratory_raw_min_finite_fraction(config)
% RESPIRATORY_RAW_MIN_FINITE_FRACTION Read shared raw respiratory-signal QC.
% The reference configuration supplies one coverage threshold for fixed raw
% references and current raw apnea windows.

    value = 0.80;
    if isstruct(config) && isfield(config, 'reference') && ...
            isstruct(config.reference)
        value = get_config_value( ...
            config.reference, 'resp', 'raw_min_finite_fraction', value);
    end
    if ~isscalar(value) || ~isfinite(value) || value < 0 || value > 1
        error(['config.reference.resp.raw_min_finite_fraction must be ' ...
            'between 0 and 1.']);
    end
end

function [i1, i2] = time_window_to_indices(t1, t2, fs, N)
% TIME_WINDOW_TO_INDICES Convert second-based bounds to clamped sample indices.

    i1 = max(1, floor(t1 * fs) + 1);
    i2 = min(N, floor(t2 * fs) + 1);
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
