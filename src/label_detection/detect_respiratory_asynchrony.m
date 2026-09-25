function [events, diagnostics] = detect_respiratory_asynchrony( ...
    data, session_reference, resp_cycles, config)
% DETECT_RESPIRATORY_ASYNCHRONY Select one explicit asynchrony method.
% wavelet_coherence_drop is the preserved session-reference-relative legacy
% detector. wavelet_phase_offset is a complementary recorded-polarity phase-
% displacement method. Only primary_method supplies canonical async events;
% unavailable primary evidence never falls back to the alternative method.

    primary_method = async_primary_method(config);
    compare_methods = get_config_value( ...
        config, 'async', 'compare_methods', false);
    N = size(data, 1);

    legacy_full = compute_respiratory_asynchrony_metrics( ...
        data, resp_cycles, session_reference, config);
    legacy_compact = compact_rea_metrics(legacy_full);
    [legacy_events, legacy_event_mask] = legacy_asynchrony_events( ...
        legacy_full, config.fs, N);
    legacy_method = legacy_method_diagnostics( ...
        legacy_compact, legacy_full, legacy_events, legacy_event_mask);

    phase_requested = compare_methods || ...
        strcmp(primary_method, 'wavelet_phase_offset');
    if phase_requested
        phase_method = compute_respiratory_phase_offset_metrics( ...
            data, resp_cycles, config);
        if phase_method.available
            [phase_events, phase_event_mask] = sustained_condition_to_events( ...
                phase_method.candidate_mask, phase_method.time_sec, ...
                config.fs, N, phase_method.min_dur_sec, ...
                'respiratory_asynchrony');
            phase_method.events = phase_events;
            phase_method.event_mask = phase_event_mask;
        end
    else
        phase_method = unrequested_phase_method(legacy_full.time_sec);
    end

    switch primary_method
        case 'wavelet_coherence_drop'
            events = legacy_events;
            primary_available = legacy_method.available;
            primary_reason = legacy_method.availability_reason;
            primary_evaluable = legacy_method.evaluable_mask;
        case 'wavelet_phase_offset'
            events = phase_method.events;
            primary_available = phase_method.available;
            primary_reason = phase_method.availability_reason;
            primary_evaluable = phase_method.reliable_phase_mask;
    end

    diagnostics = legacy_compact;
    diagnostics.schema_version = 'respiratory_asynchrony_diagnostics_v2';
    diagnostics.primary_method = primary_method;
    diagnostics.compare_methods = logical(compare_methods);
    diagnostics.primary_available = logical(primary_available);
    diagnostics.primary_availability_reason = primary_reason;
    diagnostics.primary_valid_evidence_mask = logical(primary_evaluable(:));
    diagnostics.primary_events = events;
    diagnostics.methods = struct( ...
        'wavelet_coherence_drop', legacy_method, ...
        'wavelet_phase_offset', phase_method);
    diagnostics.comparison = compare_async_methods( ...
        legacy_method, phase_method, legacy_full.time_sec, compare_methods);

    if ~primary_available
        log_message(config, 1, 'Skipping async detection (%s): %s', ...
            primary_method, primary_reason);
    end

    do_plot = get_config_value(config, 'async', 'do_plot', false);
    if do_plot
        plot_respiratory_asynchrony(data, config, primary_method, ...
            diagnostics.primary_valid_evidence_mask, events, ...
            legacy_full, legacy_method, phase_method);
    end
end

function method = async_primary_method(config)
% ASYNC_PRIMARY_METHOD Resolve explicit method selection with legacy default.

    method = 'wavelet_coherence_drop';
    if isfield(config, 'async') && isfield(config.async, 'primary_method')
        method = lower(char(string(config.async.primary_method)));
    end
    allowed = {'wavelet_coherence_drop', 'wavelet_phase_offset'};
    if ~ismember(method, allowed)
        error('MAGMA:RespiratoryAsynchrony:InvalidMethod', ...
            'config.async.primary_method must be %s or %s.', ...
            allowed{1}, allowed{2});
    end
end

function [events, event_mask] = legacy_asynchrony_events(full, fs, N)
% LEGACY_ASYNCHRONY_EVENTS Preserve the existing event conversion exactly.

    events = empty_events();
    event_mask = false(size(full.time_sec));
    if ~full.valid_analysis
        return;
    end
    [events, event_mask] = sustained_condition_to_events( ...
        full.low_coherence_mask, full.time_sec, fs, N, ...
        full.min_dur_sec, 'respiratory_asynchrony');
end

function method = legacy_method_diagnostics(compact, full, events, event_mask)
% LEGACY_METHOD_DIAGNOSTICS Extend an unchanged compact legacy payload.

    method = compact;
    method.method = 'wavelet_coherence_drop';
    method.available = logical(full.valid_analysis);
    method.availability_reason = rea_skip_reason( ...
        full.skip_code, full.error_message);
    if method.available
        method.availability_reason = 'available';
    end
    method.time_sec = full.time_sec;
    method.evaluable_mask = logical(full.valid_evidence_mask(:));
    method.event_mask = logical(event_mask(:));
    method.events = events;
    method.min_dur_sec = full.min_dur_sec;
    method.settings = struct( ...
        'analysis_fs', full.analysis_fs, ...
        'frequency_min_hz', full.fmin_hz, ...
        'frequency_max_hz', full.fmax_hz, ...
        'wavelet_resolution_f0', full.f0, ...
        'low_mid_cut_hz', full.low_mid_cut_hz, ...
        'mid_high_cut_hz', full.mid_high_cut_hz, ...
        'tlphcoh_cycles', full.tlphcoh_cycles, ...
        'minimum_duration_sec', full.min_dur_sec, ...
        'reference_mad_k', full.reference_mad_k, ...
        'minimum_absolute_drop', full.min_abs_drop, ...
        'minimum_deviating_bins', full.min_deviating_bins);
    method.provenance = struct( ...
        'reference_normalization', ...
            'session_reference_relative_phase_coherence_drop', ...
        'polarity_convention', 'preprocessing_standardized_belt_polarity', ...
        'implementation', 'preserved_legacy_wavelet_phase_coherence');
end

function phase = unrequested_phase_method(t_grid)
% UNREQUESTED_PHASE_METHOD Return a stable alternative-method placeholder.

    phase = struct( ...
        'method', 'wavelet_phase_offset', ...
        'available', false, ...
        'availability_reason', 'not_requested', ...
        'error_message', '', ...
        'time_sec', t_grid(:), ...
        'signed_mean_phase_deg', nan(size(t_grid(:))), ...
        'absolute_mean_phase_deg', nan(size(t_grid(:))), ...
        'resultant_length', nan(size(t_grid(:))), ...
        'expected_resp_frequency_hz', nan(size(t_grid(:))), ...
        'selected_resp_frequency_hz', nan(size(t_grid(:))), ...
        'selected_to_expected_frequency_ratio', nan(size(t_grid(:))), ...
        'frequency_selection_mode', ...
            {repmat({'unavailable'}, size(t_grid(:)))}, ...
        'frequency_consistent_with_breath_timing', nan(size(t_grid(:))), ...
        'valid_block_id', nan(size(t_grid(:))), ...
        'valid_phase_mask', false(size(t_grid(:))), ...
        'reliable_phase_mask', false(size(t_grid(:))), ...
        'candidate_mask', false(size(t_grid(:))), ...
        'event_mask', false(size(t_grid(:))), ...
        'events', empty_events());
end

function comparison = compare_async_methods(legacy, phase, t_grid, enabled)
% COMPARE_ASYNC_METHODS Summarize agreement only on jointly assessable time.

    dt = 1;
    if numel(t_grid) > 1
        dt = median(diff(t_grid), 'omitnan');
    end
    legacy_assessable = logical(legacy.evaluable_mask(:));
    phase_assessable = logical(phase.reliable_phase_mask(:));
    legacy_positive = logical(legacy.event_mask(:));
    phase_positive = logical(phase.event_mask(:));
    aligned = numel(legacy_assessable) == numel(phase_assessable) && ...
        numel(legacy_positive) == numel(phase_positive) && ...
        numel(legacy_assessable) == numel(t_grid);
    if ~aligned
        error('MAGMA:RespiratoryAsynchrony:ComparisonAlignment', ...
            'Asynchrony method evidence must align to the same analysis grid.');
    end

    joint = legacy_assessable & phase_assessable;
    overlap = joint & legacy_positive & phase_positive;
    legacy_only = joint & legacy_positive & ~phase_positive;
    phase_only = joint & ~legacy_positive & phase_positive;
    agreement = joint & (legacy_positive == phase_positive);
    comparison = struct( ...
        'enabled', logical(enabled), ...
        'kind', 'method_agreement_not_accuracy', ...
        'available', logical(enabled) && legacy.available && ...
            phase.available && any(joint), ...
        'wavelet_coherence_drop_usable_sec', ...
            nnz(legacy_assessable) * dt, ...
        'wavelet_phase_offset_usable_sec', nnz(phase_assessable) * dt, ...
        'jointly_assessable_sec', nnz(joint) * dt, ...
        'overlap_duration_sec', nnz(overlap) * dt, ...
        'coherence_only_duration_sec', nnz(legacy_only) * dt, ...
        'phase_offset_only_duration_sec', nnz(phase_only) * dt, ...
        'agreement_duration_sec', nnz(agreement) * dt, ...
        'agreement_fraction', NaN);
    if any(joint)
        comparison.agreement_fraction = nnz(agreement) / nnz(joint);
    end
end

function compact = compact_rea_metrics(full)
% COMPACT_REA_METRICS Preserve the legacy saved evidence fields exactly.

    compact = struct( ...
        'valid_analysis', full.valid_analysis, ...
        'skip_code', full.skip_code, ...
        'error_message', full.error_message, ...
        'phase_coherence_high', full.phase_coherence_high, ...
        'phase_coherence_mid', full.phase_coherence_mid, ...
        'phase_coherence_low', full.phase_coherence_low, ...
        'reference_available', full.reference_available, ...
        'reference_quality', full.reference_quality, ...
        'deviation_bin_count', full.deviation_bin_count, ...
        'low_coherence_mask', full.low_coherence_mask, ...
        'valid_evidence_mask', full.valid_evidence_mask, ...
        'references', full.references, ...
        'reference_valid_counts', full.reference_valid_counts, ...
        'thresholds', full.thresholds);
end

function msg = rea_skip_reason(skip_code, error_message)
% REA_SKIP_REASON Translate preserved legacy status codes.

    switch skip_code
        case 0
            msg = 'available';
        case 1
            msg = 'missing respiratory belt channel(s).';
        case 2
            msg = 'lung belt is marked missing for this recording.';
        case 3
            msg = 'lungs belt breathing features are invalid.';
        case 4
            msg = 'diaphragm belt breathing features are invalid.';
        case 5
            msg = 'at least one respiratory belt signal is unusable (all invalid/flat).';
        case 6
            msg = 'asynchrony frequency range is invalid for the signal sampling rate.';
        case 7
            msg = 'wavelet outputs were empty after alignment.';
        case 8
            if isempty(error_message)
                msg = 'wavelet coherence computation failed.';
            else
                msg = ['wavelet coherence computation failed (' error_message ').'];
            end
        case 9
            msg = 'no finite session-reference-relative coherence evidence was available.';
        otherwise
            msg = 'input data do not support asynchrony computation.';
    end
end

function plot_respiratory_asynchrony( ...
    data, config, primary_method, primary_evaluable, primary_events, ...
    legacy_full, legacy_method, phase_method)
% PLOT_RESPIRATORY_ASYNCHRONY Show legacy coherence and phase-offset evidence.

    if ~isfield(config, 'channels')
        config = resolve_signal_channels(config);
    end
    t_grid = legacy_full.time_sec;
    primary_mask = events_to_grid_mask(primary_events, t_grid);
    t_raw = (0:size(data, 1) - 1) / config.fs;
    panels = respiratory_asynchrony_plot_panels(config);
    fig = figure('Units', 'pixels', 'Position', ...
        near_fullscreen_figure_position(), 'Visible', config.make_figs_visible);
    tl = tiledlayout(numel(panels), 1, ...
        'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, sprintf(['RESPIRATORY ASYNCHRONY | primary: %s\n' ...
        'Subject: %g | Measurement: %g'], primary_method, ...
        config.subject, config.measure), 'Interpreter', 'none');

    ax = gobjects(1, numel(panels));
    phase_reliability_ax = gobjects(0);
    for i = 1:numel(panels)
        ax(i) = nexttile(tl);
        switch panels{i}
            case 'belts'
                plot_combined_raw_panel(ax(i), t_raw, data, ...
                    config.channels.lungs_idx, config.channels.diaph_idx, ...
                    t_grid, primary_mask);
            case 'phase_offset'
                plot_phase_offset_panel(ax(i), phase_method);
            case 'phase_consistency'
                plot_phase_reliability_panel(ax(i), phase_method);
                phase_reliability_ax = ax(i);
            case 'legacy_coherence'
                plot_legacy_coherence_panel( ...
                    ax(i), t_grid, legacy_full, legacy_method);
        end
    end
    if ~any(primary_evaluable)
        text(phase_reliability_ax, 0.01, 0.05, 'Primary method unavailable', ...
            'Units', 'normalized', 'Color', [0.75 0 0]);
    end
    linkaxes(ax, 'x');
    if ~isempty(t_grid)
        xlim(ax(1), [0 max(t_raw(end), t_grid(end))]);
    end
    align_axes_x_widths(ax);
    set(fig, 'Visible', config.make_figs_visible);
    save_figure(config, 'respiratory_asynchrony');
end

function plot_legacy_coherence_panel(ax, t_grid, legacy_full, legacy_method)
% PLOT_LEGACY_COHERENCE_PANEL Show the representative mid-band comparison.

    mid_title = sprintf('Legacy respiratory-band coherence (%.3g-%.3g Hz)', ...
        legacy_full.low_mid_cut_hz, legacy_full.mid_high_cut_hz);
    plot_coherence_panel(ax, t_grid, legacy_full.phase_coherence_mid, ...
        legacy_full.thresholds.mid, legacy_full.references.mid, ...
        legacy_full.reference_mask, legacy_method.event_mask, ...
        mid_title, legacy_full.plot_step_sec);
    text(ax, 0.01, 0.04, ...
        ['Representative trace; legacy events may also be triggered by ' ...
         'low/high-frequency coherence bands'], ...
        'Units', 'normalized', 'FontSize', 8, 'Color', [0.35 0.35 0.35]);
end

function mask = events_to_grid_mask(events, t_grid)
% EVENTS_TO_GRID_MASK Rasterize canonical event time bounds on the grid.

    mask = false(size(t_grid));
    for i = 1:numel(events)
        mask = mask | (t_grid >= events(i).start_t & ...
            t_grid < events(i).end_t);
    end
end

function plot_combined_raw_panel( ...
    ax, t_raw, data, lungs_idx, diaph_idx, t_grid, mask)
% PLOT_COMBINED_RAW_PANEL Overlay independently normalized belts for display.

    hold(ax, 'on');
    legend_handles = gobjects(0);
    if valid_plot_channel(lungs_idx, size(data, 2))
        lungs = robust_normalize_for_plot(data(:, lungs_idx));
        legend_handles(end + 1) = plot(ax, t_raw, lungs, 'k', ...
            'DisplayName', 'lungs'); %#ok<AGROW>
    end
    if valid_plot_channel(diaph_idx, size(data, 2))
        diaph = robust_normalize_for_plot(data(:, diaph_idx));
        legend_handles(end + 1) = plot(ax, t_raw, diaph, ...
            'Color', [0.10 0.35 0.90], ...
            'DisplayName', 'diaphragm'); %#ok<AGROW>
    end
    if isempty(legend_handles)
        text(ax, 0.5, 0.5, 'Respiratory belt channels not found', ...
            'Units', 'normalized', 'HorizontalAlignment', 'center');
    end
    shade_mask_on_axis(ax, t_grid, mask);
    event_key = patch(ax, nan(1, 4), nan(1, 4), [1.00 0.65 0.65], ...
        'EdgeColor', 'none', 'FaceAlpha', 0.45, ...
        'DisplayName', 'final async event');
    legend_handles(end + 1) = event_key;
    hold(ax, 'off');
    grid(ax, 'on');
    xlabel(ax, 'Time (s)');
    ylabel(ax, 'Normalized effort');
    title(ax, 'Respiratory effort belts + final asynchrony events');
    legend(ax, legend_handles, 'Location', 'eastoutside', 'Box', 'off');
end

function normalized = robust_normalize_for_plot(signal)
% ROBUST_NORMALIZE_FOR_PLOT Median-center and MAD-scale one display trace.

    signal = double(signal(:));
    normalized = nan(size(signal));
    finite_mask = isfinite(signal);
    if ~any(finite_mask)
        return;
    end
    finite_signal = signal(finite_mask);
    center = median(finite_signal);
    centered = finite_signal - center;
    scale = 1.4826 * median(abs(centered));
    scale_floor = eps(max(1, max(abs(finite_signal))));
    if ~isfinite(scale) || scale <= scale_floor
        scale = std(finite_signal, 0);
    end
    if ~isfinite(scale) || scale <= scale_floor
        scale = 1;
    end
    normalized(finite_mask) = centered / scale;
end

function tf = valid_plot_channel(index, n_columns)
% VALID_PLOT_CHANNEL Check one optional raw-data channel index.

    tf = ~isempty(index) && isscalar(index) && isfinite(index) && ...
        index == round(index) && index >= 1 && index <= n_columns;
end

function plot_coherence_panel( ...
    ax, t_grid, coherence, threshold, reference_value, reference_mask, ...
    event_mask, title_text, plot_step_sec)
% PLOT_COHERENCE_PANEL Plot preserved legacy coherence evidence.

    held = held_median_trace(t_grid, coherence, plot_step_sec);
    ylim(ax, [0 1]);
    hold(ax, 'on');
    shade_reference_on_axis(ax, t_grid, reference_mask);
    shade_mask_on_axis(ax, t_grid, event_mask);
    plot(ax, t_grid, coherence, 'Color', [0.70 0.70 0.70], ...
        'DisplayName', 'raw coherence');
    stairs(ax, t_grid, held, 'b', 'LineWidth', 1.4, ...
        'DisplayName', sprintf('%g s held median', plot_step_sec));
    if isfinite(reference_value)
        yline(ax, reference_value, 'k--', ...
            'DisplayName', 'session reference median');
    end
    if isfinite(threshold)
        yline(ax, threshold, 'r--', 'DisplayName', 'deviation threshold');
    end
    hold(ax, 'off');
    grid(ax, 'on');
    xlabel(ax, 'Time (s)');
    ylabel(ax, 'WPhCoh');
    title(ax, title_text);
    legend(ax, 'Location', 'eastoutside', 'Box', 'off');
end

function plot_phase_offset_panel(ax, phase)
% PLOT_PHASE_OFFSET_PANEL Plot signed/absolute phase and phase-method events.

    hold(ax, 'on');
    shade_mask_on_axis(ax, phase.time_sec, phase.event_mask);
    plot(ax, phase.time_sec, phase.signed_mean_phase_deg, 'Color', [0.2 0.4 0.8], ...
        'LineWidth', 1.0, 'DisplayName', 'signed circular mean');
    plot(ax, phase.time_sec, phase.absolute_mean_phase_deg, 'k', ...
        'LineWidth', 1.0, 'DisplayName', 'absolute phase offset');
    if isfield(phase, 'angle_threshold_deg')
        yline(ax, phase.angle_threshold_deg, 'r--', ...
            'DisplayName', 'absolute-angle threshold');
    end
    ylim(ax, [-180 180]);
    grid(ax, 'on');
    xlabel(ax, 'Time (s)');
    ylabel(ax, 'Phase (deg)');
    title(ax, 'Wavelet phase offset at shared respiratory frequency');
    legend(ax, 'Location', 'eastoutside');
    hold(ax, 'off');
end

function plot_phase_reliability_panel(ax, phase)
% PLOT_PHASE_RELIABILITY_PANEL Plot circular consistency and selected frequency.

    yyaxis(ax, 'left');
    plot(ax, phase.time_sec, phase.resultant_length, 'Color', [0.1 0.6 0.2], ...
        'DisplayName', 'phase consistency (resultant length)');
    ylabel(ax, 'Resultant length');
    ylim(ax, [0 1]);
    if isfield(phase, 'min_resultant_length')
        yline(ax, phase.min_resultant_length, 'r--', ...
            'DisplayName', 'reliability threshold');
    end
    yyaxis(ax, 'right');
    ax.YAxis(2).Color = [0.6 0.2 0.6];
    plot(ax, phase.time_sec, phase.selected_resp_frequency_hz, ...
        'Color', [0.6 0.2 0.6], 'DisplayName', 'selected shared frequency');
    if isfield(phase, 'expected_resp_frequency_hz')
        hold(ax, 'on');
        plot(ax, phase.time_sec, phase.expected_resp_frequency_hz, '--', ...
            'Color', [0.2 0.4 0.8], ...
            'DisplayName', 'reviewed-breath expected frequency');
        hold(ax, 'off');
    end
    ylabel(ax, 'Shared frequency (Hz)');
    grid(ax, 'on');
    xlabel(ax, 'Time (s)');
    title(ax, 'Phase consistency and shared respiratory frequency');
    legend(ax, 'Location', 'eastoutside', 'Box', 'off');
end

function held = held_median_trace(t_grid, values, step_sec)
% HELD_MEDIAN_TRACE Replace finite values with blockwise display medians.

    held = nan(size(values));
    if isempty(t_grid) || isempty(values) || step_sec <= 0
        return;
    end
    block_start = floor(t_grid(1) / step_sec) * step_sec;
    block_edges = block_start:step_sec:(t_grid(end) + step_sec);
    for k = 1:numel(block_edges) - 1
        idx = t_grid >= block_edges(k) & t_grid < block_edges(k + 1);
        block_values = values(idx);
        block_values = block_values(isfinite(block_values));
        if ~isempty(block_values)
            held(idx) = median(block_values, 'omitnan');
        end
    end
end

function shade_reference_on_axis(ax, t_grid, reference_mask)
% SHADE_REFERENCE_ON_AXIS Shade contiguous session-reference runs.

    if ~any(reference_mask)
        return;
    end
    limits = ylim(ax);
    d = diff([false; logical(reference_mask(:)); false]);
    starts = find(d == 1);
    ends = find(d == -1) - 1;
    for i = 1:numel(starts)
        x0 = t_grid(starts(i));
        x1 = t_grid(ends(i));
        patch(ax, [x0 x1 x1 x0], ...
            [limits(1) limits(1) limits(2) limits(2)], ...
            [0.85 0.88 0.92], 'EdgeColor', 'none', 'FaceAlpha', 0.25, ...
            'HandleVisibility', 'off');
    end
end
