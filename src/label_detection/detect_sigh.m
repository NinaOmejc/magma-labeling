function [events, diagnostics] = detect_sigh( ...
    data, resp_features, ~, config)
% DETECT_SIGH Automatically identify isolated high-amplitude breaths.
% data supplies sample signals; resp_features supplies breath markers, the
% selected canonical amplitude, and saved session/global-normalized evidence;
% config selects the fixed session reference (default), centered rolling-median,
% global-outlier, or legacy criterion plus plotting.
% events are paired, discrete breath-peak identities. diagnostics stores compact per-belt
% breath amplitude/baseline/ratio evidence and decision thresholds.
% Manual editing is handled only by the unified label-review GUI.

    events = empty_events();

    N = size(data,1);
    fs = config.fs;

    lungs = resp_features.lungs;
    diaph = resp_features.diaph;
    amplitude_method = resolve_respiration_amplitude_method(config);

    method = 'session_reference_2x';
    session_ratio_threshold = 2.0;
    rolling_window_breaths = 15;
    rolling_min_valid_breaths = 3;
    rolling_ratio_threshold = 2.0;
    compare_methods = false;
    ratio_prctile = 98;

    % Existing global-outlier criteria.
    min_abs_ratio = 1.8;
    iqr_k = 3.5;
    min_gap_sec = 20;

    do_plot = false;
    % Existing legacy criteria.
    legacy_prev_win_sec = 60;
    legacy_amp_ratio_thr = 1.5;
    legacy_min_prev_breaths = 3;

    if isfield(config, 'sigh')
        if isfield(config.sigh,'method'), method = config.sigh.method; end
        if isfield(config.sigh,'session_ratio_threshold'), session_ratio_threshold = config.sigh.session_ratio_threshold; end
        if isfield(config.sigh,'rolling_window_breaths'), rolling_window_breaths = config.sigh.rolling_window_breaths; end
        if isfield(config.sigh,'rolling_min_valid_breaths'), rolling_min_valid_breaths = config.sigh.rolling_min_valid_breaths; end
        if isfield(config.sigh,'rolling_ratio_threshold'), rolling_ratio_threshold = config.sigh.rolling_ratio_threshold; end
        if isfield(config.sigh,'compare_methods'), compare_methods = logical(config.sigh.compare_methods); end
        if isfield(config.sigh,'ratio_prctile'), ratio_prctile = config.sigh.ratio_prctile; end
        if isfield(config.sigh,'do_plot'), do_plot = config.sigh.do_plot; end
        if isfield(config.sigh,'min_abs_ratio'), min_abs_ratio = config.sigh.min_abs_ratio; end
        if isfield(config.sigh,'iqr_k'), iqr_k = config.sigh.iqr_k; end
        if isfield(config.sigh,'min_gap_sec'), min_gap_sec = config.sigh.min_gap_sec; end

        if isfield(config.sigh,'legacy_prev_win_sec'), legacy_prev_win_sec = config.sigh.legacy_prev_win_sec; end
        if isfield(config.sigh,'legacy_amp_ratio_thr'), legacy_amp_ratio_thr = config.sigh.legacy_amp_ratio_thr; end
        if isfield(config.sigh,'legacy_min_prev_breaths'), legacy_min_prev_breaths = config.sigh.legacy_min_prev_breaths; end
    end
    method = lower(char(string(method)));
    if strcmp(method, 'session_reference_2x') || compare_methods
        if ~isnumeric(session_ratio_threshold) || ~isreal(session_ratio_threshold) || ...
                ~isscalar(session_ratio_threshold) || ~isfinite(session_ratio_threshold) || session_ratio_threshold <= 0
            error('MAGMA:Sigh:InvalidSessionThreshold', ...
                'config.sigh.session_ratio_threshold must be positive.');
        end
    end
    if strcmp(method, 'rolling_median_2x') || compare_methods
        validate_rolling_sigh_config(rolling_window_breaths, ...
            rolling_min_valid_breaths, rolling_ratio_threshold);
    end

    validate_sigh_alignment_if_usable(lungs);
    validate_sigh_alignment_if_usable(diaph);

    global_lungs_valid = global_sigh_inputs_available(lungs);
    global_diaph_valid = global_sigh_inputs_available(diaph);
    diagnostics = struct( ...
        'available', false, ...
        'sigh_method', method, ...
        'amplitude_method', amplitude_method, ...
        'lungs', empty_sigh_belt_diagnostics(lungs, method, amplitude_method), ...
        'diaph', empty_sigh_belt_diagnostics(diaph, method, amplitude_method), ...
        'comparison', empty_sigh_comparison());
    sigh_lungs = false(size(lungs.peak_t(:)));
    sigh_diaph = false(size(diaph.peak_t(:)));
    switch method
        case 'session_reference_2x'
            diagnostics.lungs = session_reference_sigh_diagnostics( ...
                lungs, session_ratio_threshold, amplitude_method);
            diagnostics.diaph = session_reference_sigh_diagnostics( ...
                diaph, session_ratio_threshold, amplitude_method);
            sigh_lungs = diagnostics.lungs.sigh_flags;
            sigh_diaph = diagnostics.diaph.sigh_flags;

        case 'rolling_median_2x'
            [sigh_lungs, baseline, ratio, threshold, amplitude, available, ...
                evaluable, boundary_mask, status] = ...
                sigh_flags_rolling_median_2x(lungs, ...
                    rolling_window_breaths, rolling_min_valid_breaths, ...
                    rolling_ratio_threshold);
            diagnostics.lungs = set_sigh_belt_diagnostics( ...
                diagnostics.lungs, available, sigh_lungs, amplitude, ...
                baseline, ratio, threshold, evaluable, boundary_mask, status);
            [sigh_diaph, baseline, ratio, threshold, amplitude, available, ...
                evaluable, boundary_mask, status] = ...
                sigh_flags_rolling_median_2x(diaph, ...
                    rolling_window_breaths, rolling_min_valid_breaths, ...
                    rolling_ratio_threshold);
            diagnostics.diaph = set_sigh_belt_diagnostics( ...
                diagnostics.diaph, available, sigh_diaph, amplitude, ...
                baseline, ratio, threshold, evaluable, boundary_mask, status);

        case 'legacy_60s'
            if canonical_sigh_inputs_available(lungs)
                [sigh_lungs, baseline, ratio, evaluable] = ...
                    sigh_flags_legacy_60s(lungs, legacy_prev_win_sec, ...
                        legacy_amp_ratio_thr, legacy_min_prev_breaths);
                amplitude = canonical_sigh_amplitude(lungs);
                [available, status] = sigh_method_availability( ...
                    evaluable, 'insufficient_prior_breath_history');
                diagnostics.lungs = set_sigh_belt_diagnostics( ...
                    diagnostics.lungs, available, sigh_lungs, amplitude, ...
                    baseline, ratio, legacy_amp_ratio_thr, evaluable, ...
                    false(size(evaluable)), status);
            end
            if canonical_sigh_inputs_available(diaph)
                [sigh_diaph, baseline, ratio, evaluable] = ...
                    sigh_flags_legacy_60s(diaph, legacy_prev_win_sec, ...
                        legacy_amp_ratio_thr, legacy_min_prev_breaths);
                amplitude = canonical_sigh_amplitude(diaph);
                [available, status] = sigh_method_availability( ...
                    evaluable, 'insufficient_prior_breath_history');
                diagnostics.diaph = set_sigh_belt_diagnostics( ...
                    diagnostics.diaph, available, sigh_diaph, amplitude, ...
                    baseline, ratio, legacy_amp_ratio_thr, evaluable, ...
                    false(size(evaluable)), status);
            end

        case 'global_ratio_outlier'
            if global_lungs_valid
                [sigh_lungs, baseline, ratio, threshold, evaluable] = ...
                    sigh_flags_global_ratio_outlier( ...
                    lungs, ratio_prctile, ...
                    min_abs_ratio, iqr_k, min_gap_sec);
                amplitude = canonical_sigh_amplitude(lungs);
                [available, status] = sigh_method_availability( ...
                    evaluable, 'insufficient_global_amplitudes');
                diagnostics.lungs = set_sigh_belt_diagnostics( ...
                    diagnostics.lungs, available, sigh_lungs, amplitude, ...
                    baseline, ratio, threshold, evaluable, ...
                    false(size(evaluable)), status);
            end
            if global_diaph_valid
                [sigh_diaph, baseline, ratio, threshold, evaluable] = ...
                    sigh_flags_global_ratio_outlier( ...
                    diaph, ratio_prctile, ...
                    min_abs_ratio, iqr_k, min_gap_sec);
                amplitude = canonical_sigh_amplitude(diaph);
                [available, status] = sigh_method_availability( ...
                    evaluable, 'insufficient_global_amplitudes');
                diagnostics.diaph = set_sigh_belt_diagnostics( ...
                    diagnostics.diaph, available, sigh_diaph, amplitude, ...
                    baseline, ratio, threshold, evaluable, ...
                    false(size(evaluable)), status);
            end

        otherwise
            error('MAGMA:Sigh:InvalidMethod', ...
                ['config.sigh.method must be ''session_reference_2x'', ''rolling_median_2x'', ' ...
                 '''global_ratio_outlier'', or ''legacy_60s'' (received ''%s'').'], ...
                method);
    end
    [sigh_lungs,diagnostics.lungs] = gate_artifact_sigh(lungs,sigh_lungs,diagnostics.lungs,method,rolling_window_breaths,legacy_prev_win_sec,fs);
    [sigh_diaph,diagnostics.diaph] = gate_artifact_sigh(diaph,sigh_diaph,diagnostics.diaph,method,rolling_window_breaths,legacy_prev_win_sec,fs);
    diagnostics.available = diagnostics.lungs.available || ...
        diagnostics.diaph.available;

    comparison_details = empty_sigh_comparison_details();
    if compare_methods
        [diagnostics.comparison.lungs, comparison_details.lungs] = ...
            compare_sigh_methods(lungs, ...
                rolling_window_breaths, rolling_min_valid_breaths, ...
                rolling_ratio_threshold, session_ratio_threshold, amplitude_method, fs);
        [diagnostics.comparison.diaph, comparison_details.diaph] = ...
            compare_sigh_methods(diaph, ...
                rolling_window_breaths, rolling_min_valid_breaths, ...
                rolling_ratio_threshold, session_ratio_threshold, amplitude_method, fs);
        diagnostics.comparison.enabled = true;
        diagnostics.comparison.total = aggregate_sigh_comparison( ...
            diagnostics.comparison.lungs, diagnostics.comparison.diaph);
        print_sigh_comparison(diagnostics.comparison, config);
    end

    if ~diagnostics.available
        log_message(config, 1, ...
            ['Skipping sigh detection: selected method %s has no valid ' ...
             'respiratory belt with usable breath amplitudes.'], method);
        return;
    end
    events = sigh_flags_to_events(lungs, diaph, sigh_lungs, sigh_diaph, N, fs);

    if do_plot
        if ~isfield(config, 'channels')
            config = resolve_signal_channels(config);
        end
        idx_lungs = config.channels.lungs_idx;
        idx_diaph = config.channels.diaph_idx;

        t_raw = (0:N-1)/fs;

        figure('Units','pixels','Position', near_fullscreen_figure_position(), 'Visible', config.make_figs_visible);
        sgtitle(['SIGH | Method: ' method ' | Subject: ' ...
            num2str(config.subject) ' | Measurement: ' num2str(config.measure)], 'Interpreter', 'none')

        ax1 = subplot(4,1,1); hold on
        h_lungs_trace = gobjects(0);
        if ~isempty(idx_lungs), h_lungs_trace = plot(t_raw, data(:,idx_lungs), 'k', 'DisplayName', 'Resp-Lungs'); end
        h_lungs_events = shade_events_on_axis(gca, events, 'final sigh event');
        h_lungs_sigh = gobjects(0);
        if any(sigh_lungs)
            if ~isempty(idx_lungs)
                y_lungs_mark = interp1(t_raw, data(:,idx_lungs), ...
                    lungs.peak_t(sigh_lungs), 'linear', 'extrap');
            else
                y_lungs_mark = nan(sum(sigh_lungs),1);
            end
            h_lungs_sigh = plot(lungs.peak_t(sigh_lungs), y_lungs_mark, ...
                'ro', 'MarkerFaceColor', 'r', 'DisplayName', 'Sigh breaths');
        end
        title('Raw lungs effort + final sigh events')
        [raw_handles, raw_labels] = raw_sigh_legend_entries( ...
            h_lungs_trace, h_lungs_events, h_lungs_sigh, 'Resp-Lungs');
        add_axis_legend(gca, raw_handles, raw_labels);
        xlabel('Time (s)'); ylabel('Resp-Lungs'); grid on; hold off

        ax2 = subplot(4,1,2);
        plot_sigh_ratio_evidence( ...
            ax2, lungs, diagnostics.lungs, sigh_lungs, 'lungs', ...
            comparison_details.lungs);

        ax3 = subplot(4,1,3); hold on
        h_diaph_trace = gobjects(0);
        if ~isempty(idx_diaph), h_diaph_trace = plot(t_raw, data(:,idx_diaph), 'k', 'DisplayName', 'Resp-Diaphragm'); end
        h_diaph_events = shade_events_on_axis(gca, events, 'final sigh event');
        h_diaph_sigh = gobjects(0);
        if any(sigh_diaph)
            if ~isempty(idx_diaph)
                y_diaph_mark = interp1(t_raw, data(:,idx_diaph), ...
                    diaph.peak_t(sigh_diaph), 'linear', 'extrap');
            else
                y_diaph_mark = nan(sum(sigh_diaph),1);
            end
            h_diaph_sigh = plot(diaph.peak_t(sigh_diaph), y_diaph_mark, ...
                'ro', 'MarkerFaceColor', 'r', 'DisplayName', 'Sigh breaths');
        end
        title('Raw diaphragm effort + final sigh events')
        [raw_handles, raw_labels] = raw_sigh_legend_entries( ...
            h_diaph_trace, h_diaph_events, h_diaph_sigh, 'Resp-Diaphragm');
        add_axis_legend(gca, raw_handles, raw_labels);
        xlabel('Time (s)'); ylabel('Resp-Diaphragm'); grid on; hold off

        ax4 = subplot(4,1,4);
        plot_sigh_ratio_evidence( ...
            ax4, diaph, diagnostics.diaph, sigh_diaph, 'diaphragm', ...
            comparison_details.diaph);

        linkaxes([ax1 ax3], 'x');
        recording_end_t = (N - 1) / fs;
        if recording_end_t > 0
            xlim(ax1, [0 recording_end_t]);
        end
        align_axes_x_widths([ax1 ax2 ax3 ax4]);

        save_figure(config, 'sigh');
    end
end

function [handles, labels] = raw_sigh_legend_entries( ...
    trace_handle, event_handles, sigh_handle, trace_label)
% RAW_SIGH_LEGEND_ENTRIES Build a stable raw-panel legend in display order.

    handles = gobjects(0);
    labels = cell(0, 1);
    [handles, labels] = append_valid_legend_handle( ...
        handles, labels, trace_handle, trace_label);
    [handles, labels] = append_valid_legend_handle( ...
        handles, labels, event_handles, 'final sigh event');
    [handles, labels] = append_valid_legend_handle( ...
        handles, labels, sigh_handle, 'Sigh breaths');
end

function plot_sigh_ratio_evidence( ...
    ax, belt, belt_diagnostics, selected_mask, belt_name, comparison)
% PLOT_SIGH_RATIO_EVIDENCE Show primary breath ratios and optional comparison.

    hold(ax, 'on');
    title(ax, sprintf('Sigh amplitude-ratio evidence (%s, %s)', ...
        belt_name, belt_diagnostics.method), 'Interpreter', 'none');
    xlabel(ax, 'Breath index');
    if strcmp(belt_diagnostics.method, 'session_reference_2x')
        ylabel(ax, 'Amplitude / session reference');
    else
        ylabel(ax, 'Sigh amplitude / method baseline');
    end
    grid(ax, 'on');

    ratio = belt_diagnostics.sigh_ratio(:);
    selected_mask = logical(selected_mask(:));
    n_breaths = numel(belt.peak_t);
    assert_sigh_vector_length(ratio, n_breaths, 'diagnostic ratio vector');
    assert_sigh_vector_length(selected_mask, n_breaths, 'selected-breath mask');
    breath_index = (1:n_breaths)';
    valid = isfinite(ratio) & ratio > 0;

    set_breath_index_xlim(ax, n_breaths);
    if ~belt_diagnostics.available || ~any(valid)
        ylim(ax, [0 1]);
        text(ax, 0.5, 0.5, 'No usable breath-ratio evidence', ...
            'Units', 'normalized', 'HorizontalAlignment', 'center');
        hold(ax, 'off');
        return;
    end

    h_ratios = plot(ax, breath_index(valid), ratio(valid), 'o', ...
        'LineStyle', 'none', 'Color', [0.35 0.35 0.35], ...
        'MarkerSize', 4, 'DisplayName', 'primary breath ratios');
    h_threshold = gobjects(0);
    if isscalar(belt_diagnostics.sigh_threshold) && ...
            isfinite(belt_diagnostics.sigh_threshold)
        h_threshold = yline(ax, belt_diagnostics.sigh_threshold, 'k--', ...
            'LineWidth', 1.2, 'DisplayName', 'primary threshold');
    end
    sigh_mask = valid & selected_mask;
    handles = gobjects(0);
    labels = cell(0, 1);
    [handles, labels] = append_valid_legend_handle( ...
        handles, labels, h_ratios, 'primary breath ratios');
    [handles, labels] = append_valid_legend_handle( ...
        handles, labels, h_threshold, 'primary threshold');
    if any(sigh_mask)
        h_sighs = plot(ax, breath_index(sigh_mask), ratio(sigh_mask), 'ro', ...
            'LineStyle', 'none', 'MarkerFaceColor', 'r', 'MarkerSize', 6, ...
            'DisplayName', 'primary sigh breaths');
        [handles, labels] = append_valid_legend_handle( ...
            handles, labels, h_sighs, 'primary sigh breaths');
    end

    [other_ratio, other_flags, other_threshold, other_name] = ...
        comparison_overlay(comparison, belt_diagnostics.method, n_breaths);
    other_valid = isfinite(other_ratio) & other_ratio > 0;
    if any(other_valid)
        h_other = plot(ax, breath_index(other_valid), other_ratio(other_valid), 's', ...
            'LineStyle', 'none', 'Color', [0.10 0.35 0.90], ...
            'MarkerSize', 4, 'DisplayName', [other_name ' ratios']);
        [handles, labels] = append_valid_legend_handle( ...
            handles, labels, h_other, [other_name ' ratios']);
        if isfinite(other_threshold)
            h_other_threshold = yline(ax, other_threshold, ':', ...
                'Color', [0.10 0.35 0.90], 'LineWidth', 1.2, ...
                'DisplayName', [other_name ' threshold']);
            [handles, labels] = append_valid_legend_handle( ...
                handles, labels, h_other_threshold, [other_name ' threshold']);
        end
        other_sighs = other_valid & other_flags;
        if any(other_sighs)
            h_other_sighs = plot(ax, breath_index(other_sighs), ...
                other_ratio(other_sighs), 'x', 'LineStyle', 'none', ...
                'Color', [0.10 0.35 0.90], 'MarkerSize', 7, 'LineWidth', 1.2, ...
                'DisplayName', [other_name ' sigh breaths']);
            [handles, labels] = append_valid_legend_handle( ...
                handles, labels, h_other_sighs, [other_name ' sigh breaths']);
        end
    end
    add_axis_legend(ax, handles, labels);
    hold(ax, 'off');
end

function [handles, labels] = append_valid_legend_handle( ...
    handles, labels, candidate_handles, label)
% APPEND_VALID_LEGEND_HANDLE Append the first valid optional graphics handle.

    valid_index = find(isgraphics(candidate_handles), 1, 'first');
    if isempty(valid_index)
        return;
    end
    handles(end + 1, 1) = candidate_handles(valid_index);
    labels{end + 1, 1} = label;
end

function set_breath_index_xlim(ax, n_breaths)
% SET_BREATH_INDEX_XLIM Span breath indices without linking raw panels.

    if n_breaths < 1
        return;
    end
    limits = [1 n_breaths];
    if limits(1) == limits(2)
        limits = limits + [-0.5 0.5];
    end
    xlim(ax, limits);
end

function diagnostics = empty_sigh_belt_diagnostics(belt, method, amplitude_method)
% EMPTY_SIGH_BELT_DIAGNOSTICS Initialize breath-level sigh evidence for one belt.
% Evidence vectors are aligned with belt.peak_t.

    n_breaths = numel(belt.peak_t);
    reference_quality = 'belt_unavailable';
    if isfield(belt, 'reference_quality')
        reference_quality = belt.reference_quality;
    end
    reference_value = NaN;
    if isfield(belt, 'session_reference_value') && isnumeric(belt.session_reference_value) && ...
            isreal(belt.session_reference_value) && isscalar(belt.session_reference_value)
        reference_value = belt.session_reference_value;
    end
    [unavailable, unavailable_status] = sigh_belt_unavailable(belt);
    if ~unavailable
        unavailable_status = 'belt_unavailable';
    end
    diagnostics = struct( ...
        'available', false, ...
        'reference_quality', reference_quality, ...
        'session_reference_value', reference_value, ...
        'method', method, ...
        'amplitude_method', amplitude_method, ...
        'amplitude_source', 'resp_features.<belt>.amp', ...
        'boundary_convention', sigh_boundary_convention(method), ...
        'status', unavailable_status, ...
        'sigh_flags', false(n_breaths, 1), ...
        'sigh_amplitude', nan(n_breaths, 1), ...
        'sigh_baseline', nan(n_breaths, 1), ...
        'sigh_ratio', nan(n_breaths, 1), ...
        'evaluable_mask', false(n_breaths, 1), ...
        'boundary_extrapolation_mask', false(n_breaths, 1), ...
        'sigh_threshold', NaN, ...
        'decision_threshold', NaN);
end

function diagnostics = session_reference_sigh_diagnostics(belt, threshold, amplitude_method)
% SESSION_REFERENCE_SIGH_DIAGNOSTICS Use saved ratios; never estimate a reference.
    diagnostics = empty_sigh_belt_diagnostics(belt, 'session_reference_2x', amplitude_method);
    diagnostics.sigh_threshold = threshold;
    diagnostics.decision_threshold = threshold;
    [unavailable, ~] = sigh_belt_unavailable(belt);
    if unavailable, return; end
    [peak_t, amplitude] = canonical_sigh_vectors(belt);
    diagnostics.sigh_amplitude = amplitude;
    diagnostics.status = 'no_session_reference';
    if ~isfield(belt, 'session_amplitude_available') || ...
            ~isscalar(belt.session_amplitude_available) || ...
            ~isequal(belt.session_amplitude_available, true)
        return;
    end
    reference = diagnostics.session_reference_value;
    if ~isfinite(reference) || reference <= 0
        diagnostics.status = 'invalid_session_reference';
        return;
    end
    if ~isfield(belt, 'amp_ratio_session')
        diagnostics.status = 'missing_session_amplitude_ratio';
        return;
    end
    ratio = belt.amp_ratio_session(:);
    assert_sigh_vector_length(ratio, numel(peak_t), 'session amplitude-ratio vector');
    evaluable = isfinite(peak_t) & isfinite(amplitude) & amplitude > 0 & ...
        isfinite(ratio) & ratio > 0;
    ratio(~evaluable) = NaN;
    flags = evaluable & ratio >= threshold;
    [available, status] = sigh_method_availability(evaluable, 'insufficient_valid_amplitudes');
    diagnostics = set_sigh_belt_diagnostics(diagnostics, available, flags, amplitude, ...
        repmat(reference, numel(peak_t), 1), ratio, threshold, evaluable, ...
        false(size(evaluable)), status);
end

function convention = sigh_boundary_convention(method)
% SIGH_BOUNDARY_CONVENTION Describe how method evidence treats boundaries.

    if strcmp(method, 'rolling_median_2x')
        convention = 'complete_centered_windows_constant_edge_extension';
    else
        convention = 'not_applicable';
    end
end

function validate_rolling_sigh_config(window_breaths, min_valid, threshold)
% VALIDATE_ROLLING_SIGH_CONFIG Validate the defining local-baseline settings.

    if ~isscalar(window_breaths) || ~isfinite(window_breaths) || ...
            window_breaths < 1 || window_breaths ~= round(window_breaths) || ...
            mod(window_breaths, 2) ~= 1
        error('MAGMA:Sigh:InvalidRollingWindow', ...
            'config.sigh.rolling_window_breaths must be a positive odd integer.');
    end
    if ~isscalar(min_valid) || ~isfinite(min_valid) || min_valid < 1 || ...
            min_valid ~= round(min_valid) || min_valid > window_breaths
        error('MAGMA:Sigh:InvalidRollingMinimum', ...
            ['config.sigh.rolling_min_valid_breaths must be an integer ' ...
             'between 1 and rolling_window_breaths.']);
    end
    if ~isscalar(threshold) || ~isfinite(threshold) || threshold <= 0
        error('MAGMA:Sigh:InvalidRollingThreshold', ...
            'config.sigh.rolling_ratio_threshold must be positive.');
    end
end

function tf = global_sigh_inputs_available(belt)
% GLOBAL_SIGH_INPUTS_AVAILABLE Preserve the existing global-method gate.

    [unavailable, ~] = sigh_belt_unavailable(belt);
    if unavailable
        tf = false;
        return;
    end
    tf = isstruct(belt) && isfield(belt, 'global_amplitude_available') && ...
        isscalar(belt.global_amplitude_available) && ...
        logical(belt.global_amplitude_available);
end

function diagnostics = set_sigh_belt_diagnostics( ...
    diagnostics, available, flags, amplitude, baseline, ratio, threshold, ...
    evaluable, boundary_mask, status)
% SET_SIGH_BELT_DIAGNOSTICS Store method-neutral breath-level sigh evidence.

    n_breaths = numel(diagnostics.sigh_flags);
    assert_sigh_vector_length(flags, n_breaths, 'flags');
    assert_sigh_vector_length(amplitude, n_breaths, 'amplitude');
    assert_sigh_vector_length(baseline, n_breaths, 'baseline');
    assert_sigh_vector_length(ratio, n_breaths, 'ratio');
    assert_sigh_vector_length(evaluable, n_breaths, 'evaluable mask');
    assert_sigh_vector_length(boundary_mask, n_breaths, ...
        'boundary-extrapolation mask');
    diagnostics.available = logical(available);
    diagnostics.status = status;
    diagnostics.sigh_flags = logical(flags(:));
    diagnostics.sigh_amplitude = amplitude(:);
    diagnostics.sigh_baseline = baseline(:);
    diagnostics.sigh_ratio = ratio(:);
    diagnostics.evaluable_mask = logical(evaluable(:));
    diagnostics.boundary_extrapolation_mask = logical(boundary_mask(:));
    diagnostics.sigh_threshold = threshold;
    diagnostics.decision_threshold = threshold;
end

function [available, status] = sigh_method_availability(evaluable, unavailable_status)
% SIGH_METHOD_AVAILABILITY Distinguish unevaluable evidence from negatives.

    available = any(logical(evaluable(:)));
    if available
        status = 'available';
    else
        status = unavailable_status;
    end
end

function tf = canonical_sigh_inputs_available(belt)
% CANONICAL_SIGH_INPUTS_AVAILABLE Check availability without changing amplitude.

    [unavailable, ~] = sigh_belt_unavailable(belt);
    if unavailable
        tf = false;
        return;
    end
    tf = isstruct(belt) && isfield(belt, 'peak_t') && isfield(belt, 'amp');
    if ~tf
        return;
    end
    [~, amplitude] = canonical_sigh_vectors(belt);
    tf = ~isempty(amplitude) && any(isfinite(amplitude) & amplitude > 0);
end

function validate_sigh_alignment_if_usable(belt)
% VALIDATE_SIGH_ALIGNMENT_IF_USABLE Keep strict checks for usable belts only.

    [unavailable, ~] = sigh_belt_unavailable(belt);
    if ~unavailable
        canonical_sigh_vectors(belt);
    end
end

function [unavailable, status] = sigh_belt_unavailable(belt)
% SIGH_BELT_UNAVAILABLE Resolve explicit belt availability before vectors.

    unavailable = false;
    status = '';
    if isstruct(belt) && isfield(belt, 'ignored') && ...
            isscalar(belt.ignored) && logical(belt.ignored)
        unavailable = true;
        status = 'belt_ignored';
    elseif isstruct(belt) && isfield(belt, 'available') && ...
            isscalar(belt.available) && ~logical(belt.available)
        unavailable = true;
        status = 'belt_unavailable';
    end
end

function amplitude = canonical_sigh_amplitude(belt)
% CANONICAL_SIGH_AMPLITUDE Return the selected upstream amplitude definition.

    [~, amplitude] = canonical_sigh_vectors(belt);
end

function [peak_t, amplitude] = canonical_sigh_vectors(belt)
% CANONICAL_SIGH_VECTORS Require one canonical amplitude per breath peak.

    if ~isstruct(belt) || ~isfield(belt, 'peak_t') || ~isfield(belt, 'amp')
        error('MAGMA:Sigh:MissingCanonicalAmplitude', ...
            'Sigh detection requires aligned resp_features.<belt>.peak_t and .amp vectors.');
    end
    peak_t = belt.peak_t(:);
    amplitude = belt.amp(:);
    if numel(peak_t) ~= numel(amplitude)
        error('MAGMA:Sigh:BreathAlignmentMismatch', ...
            ['resp_features.<belt>.peak_t and the canonical .amp field must ' ...
             'align one-to-one for sigh detection.']);
    end
end

function assert_sigh_vector_length(values, expected_length, description)
% ASSERT_SIGH_VECTOR_LENGTH Reject silent truncation of breath evidence.

    if numel(values) ~= expected_length
        error('MAGMA:Sigh:BreathAlignmentMismatch', ...
            'Sigh %s must contain one value per breath peak.', description);
    end
end

function [baseline, ratio] = validated_global_sigh_evidence(belt)
% VALIDATED_GLOBAL_SIGH_EVIDENCE Validate stored normalization against .amp.

    [~, amplitude] = canonical_sigh_vectors(belt);
    n_breaths = numel(amplitude);
    if ~isfield(belt, 'global_reference_value') || ...
            ~isscalar(belt.global_reference_value)
        error('MAGMA:Sigh:MissingGlobalReference', ...
            'Global sigh detection requires a scalar global_reference_value.');
    end
    if ~isfield(belt, 'amp_ratio_global')
        error('MAGMA:Sigh:MissingGlobalRatio', ...
            'Global sigh detection requires amp_ratio_global aligned with canonical .amp.');
    end
    ratio = belt.amp_ratio_global(:);
    assert_sigh_vector_length(ratio, n_breaths, 'global amplitude-ratio vector');
    baseline = repmat(belt.global_reference_value, n_breaths, 1);

    expected = nan(size(amplitude));
    valid_amplitude = isfinite(amplitude) & amplitude > 0 & ...
        isfinite(baseline) & baseline > 0;
    expected(valid_amplitude) = ...
        amplitude(valid_amplitude) ./ baseline(valid_amplitude);
    comparable = isfinite(expected) & isfinite(ratio);
    tolerance = 0;
    if any(comparable)
        tolerance = 100 * eps(max(1, max(abs(expected(comparable)))));
    end
    same_nan = isnan(expected) & isnan(ratio);
    same_inf = isinf(expected) & isinf(ratio) & ...
        (sign(expected) == sign(ratio));
    nonfinite_mismatch = ~comparable & ~same_nan & ~same_inf;
    if any(nonfinite_mismatch) || ...
            any(abs(expected(comparable) - ratio(comparable)) > tolerance)
        error('MAGMA:Sigh:StaleGlobalRatio', ...
            ['resp_features.<belt>.amp_ratio_global does not match the ' ...
             'selected canonical .amp and global_reference_value.']);
    end
end

function [sigh_flags, baseline, ratio, ratio_threshold, amplitude, available, ...
        evaluable, boundary_mask, status] = ...
    sigh_flags_rolling_median_2x( ...
        feature_belt, window_breaths, min_valid, ratio_threshold)
% SIGH_FLAGS_ROLLING_MEDIAN_2X Compare canonical amplitude with a local median.
% Baselines use only complete centered windows. The first and last complete
% baselines are extended unchanged to the boundary breath positions.

    [unavailable, status] = sigh_belt_unavailable(feature_belt);
    if unavailable
        if isstruct(feature_belt) && isfield(feature_belt, 'peak_t')
            L = numel(feature_belt.peak_t);
        else
            L = 0;
        end
        sigh_flags = false(L, 1);
        amplitude = nan(L, 1);
        baseline = nan(L, 1);
        ratio = nan(L, 1);
        evaluable = false(L, 1);
        boundary_mask = false(L, 1);
        available = false;
        return;
    end

    [peak_t, amplitude] = canonical_sigh_vectors(feature_belt);
    L = numel(peak_t);
    sigh_flags = false(L, 1);
    baseline = nan(L, 1);
    ratio = nan(L, 1);
    evaluable = false(L, 1);
    boundary_mask = false(L, 1);
    available = false;

    if L == 0
        status = 'no_breaths';
        return;
    end
    if L < window_breaths
        status = 'insufficient_breath_positions';
        return;
    end

    half_window = floor(window_breaths / 2);
    valid_amplitude = isfinite(amplitude) & amplitude > 0;
    first_center = half_window + 1;
    last_center = L - half_window;
    for i = first_center:last_center
        window_values = amplitude((i - half_window):(i + half_window));
        window_values = window_values(isfinite(window_values) & window_values > 0);
        if numel(window_values) < min_valid
            continue;
        end
        local_median = median(window_values, 'omitnan');
        if ~isfinite(local_median) || local_median <= 0
            continue;
        end
        baseline(i) = local_median;
    end

    baseline(1:half_window) = baseline(first_center);
    baseline((last_center + 1):L) = baseline(last_center);
    boundary_mask(1:half_window) = true;
    boundary_mask((last_center + 1):L) = true;

    evaluable = valid_amplitude & isfinite(baseline) & baseline > 0;
    ratio(evaluable) = amplitude(evaluable) ./ baseline(evaluable);
    sigh_flags(evaluable) = ratio(evaluable) >= ratio_threshold;
    available = any(evaluable);
    if available
        status = 'available';
    else
        status = 'insufficient_valid_amplitudes';
    end
end

function comparison = empty_sigh_comparison()
% EMPTY_SIGH_COMPARISON Initialize optional method-comparison summaries.

    comparison = struct( ...
        'enabled', false, ...
        'lungs', empty_sigh_comparison_summary(), ...
        'diaph', empty_sigh_comparison_summary(), ...
        'total', empty_sigh_comparison_summary());
end

function details = empty_sigh_comparison_details()
% EMPTY_SIGH_COMPARISON_DETAILS Initialize unsaved plotting evidence.

    details = struct( ...
        'lungs', empty_sigh_comparison_detail(), ...
        'diaph', empty_sigh_comparison_detail());
end

function summary = empty_sigh_comparison_summary()
% EMPTY_SIGH_COMPARISON_SUMMARY Define stable comparison count fields.

    summary = struct( ...
        'available', false, ...
        'valid_breath_count', 0, ...
        'rolling_median_2x_count', 0, ...
        'rolling_median_2x_percent', NaN, ...
        'rolling_median_2x_threshold', NaN, ...
        'session_reference_2x_count', 0, ...
        'session_reference_2x_percent', NaN, ...
        'session_reference_2x_threshold', NaN, ...
        'both_count', 0, ...
        'rolling_median_2x_only_count', 0, ...
        'session_reference_2x_only_count', 0, ...
        'agreement_count', 0, ...
        'agreement_percent', NaN);
end

function detail = empty_sigh_comparison_detail()
% EMPTY_SIGH_COMPARISON_DETAIL Hold temporary aligned plot vectors.

    detail = struct( ...
        'available', false, ...
        'rolling_ratio', [], ...
        'rolling_flags', false(0, 1), ...
        'rolling_threshold', NaN, ...
        'session_ratio', [], ...
        'session_flags', false(0, 1), ...
        'session_threshold', NaN);
end

function [summary, detail] = compare_sigh_methods( ...
    feature_belt, window_breaths, min_valid, ...
    rolling_threshold, session_threshold, amplitude_method, fs)
% COMPARE_SIGH_METHODS Compare fixed and rolling ratios on jointly clean breaths.

    summary = empty_sigh_comparison_summary();
    detail = empty_sigh_comparison_detail();
    [rolling_flags, rolling_baseline, rolling_ratio, rolling_threshold, ~, ...
        rolling_available, rolling_evaluable] = ...
        sigh_flags_rolling_median_2x(feature_belt, ...
            window_breaths, min_valid, rolling_threshold);
    rolling = struct('available', rolling_available, 'evaluable_mask', rolling_evaluable, ...
        'sigh_ratio', rolling_ratio, 'sigh_baseline', rolling_baseline);
    [rolling_flags, rolling] = gate_artifact_sigh(feature_belt, rolling_flags, ...
        rolling, 'rolling_median_2x', window_breaths, 0, fs);
    session = session_reference_sigh_diagnostics(feature_belt, session_threshold, amplitude_method);
    [session_flags, session] = gate_artifact_sigh(feature_belt, session.sigh_flags, ...
        session, 'session_reference_2x', window_breaths, 0, fs);
    rolling_ratio = rolling.sigh_ratio;
    rolling_evaluable = rolling.evaluable_mask;
    session_ratio = session.sigh_ratio;
    session_evaluable = session.evaluable_mask;

    n = numel(feature_belt.peak_t);
    assert_sigh_vector_length(rolling_flags, n, 'rolling flags');
    assert_sigh_vector_length(rolling_ratio, n, 'rolling ratios');
    assert_sigh_vector_length(rolling_evaluable, n, 'rolling evaluable mask');
    assert_sigh_vector_length(session_flags, n, 'session flags');
    assert_sigh_vector_length(session_ratio, n, 'session ratios');
    assert_sigh_vector_length(session_evaluable, n, 'session evaluable mask');
    rolling_flags = logical(rolling_flags(:));
    rolling_ratio = rolling_ratio(:);
    session_flags = logical(session_flags(:));
    session_ratio = session_ratio(:);
    valid = logical(rolling_evaluable(:)) & logical(session_evaluable(:));

    detail.available = any(valid);
    detail.rolling_ratio = rolling_ratio;
    detail.rolling_flags = rolling_flags;
    detail.rolling_threshold = rolling_threshold;
    detail.session_ratio = session_ratio;
    detail.session_flags = session_flags;
    detail.session_threshold = session_threshold;

    summary.available = detail.available;
    summary.valid_breath_count = sum(valid);
    summary.rolling_median_2x_count = sum(valid & rolling_flags);
    summary.session_reference_2x_count = sum(valid & session_flags);
    summary.both_count = sum(valid & rolling_flags & session_flags);
    summary.rolling_median_2x_only_count = ...
        sum(valid & rolling_flags & ~session_flags);
    summary.session_reference_2x_only_count = ...
        sum(valid & ~rolling_flags & session_flags);
    summary.agreement_count = sum(valid & (rolling_flags == session_flags));
    summary.rolling_median_2x_threshold = rolling_threshold;
    summary.session_reference_2x_threshold = session_threshold;
    summary = add_sigh_comparison_percentages(summary);
end

function summary = aggregate_sigh_comparison(lungs, diaph)
% AGGREGATE_SIGH_COMPARISON Sum per-belt comparison observations.

    summary = empty_sigh_comparison_summary();
    fields = {'valid_breath_count', 'rolling_median_2x_count', ...
        'session_reference_2x_count', 'both_count', ...
        'rolling_median_2x_only_count', ...
        'session_reference_2x_only_count', 'agreement_count'};
    for i = 1:numel(fields)
        summary.(fields{i}) = lungs.(fields{i}) + diaph.(fields{i});
    end
    summary.available = lungs.available || diaph.available;
    thresholds = [lungs.rolling_median_2x_threshold, ...
        diaph.rolling_median_2x_threshold];
    thresholds = thresholds(isfinite(thresholds));
    if ~isempty(thresholds)
        summary.rolling_median_2x_threshold = thresholds(1);
    end
    summary.session_reference_2x_threshold = lungs.session_reference_2x_threshold;
    summary = add_sigh_comparison_percentages(summary);
end

function summary = add_sigh_comparison_percentages(summary)
% ADD_SIGH_COMPARISON_PERCENTAGES Normalize comparison counts by valid breaths.

    n = summary.valid_breath_count;
    if n <= 0
        return;
    end
    summary.rolling_median_2x_percent = ...
        100 * summary.rolling_median_2x_count / n;
    summary.session_reference_2x_percent = ...
        100 * summary.session_reference_2x_count / n;
    summary.agreement_percent = 100 * summary.agreement_count / n;
end

function print_sigh_comparison(comparison, config)
% PRINT_SIGH_COMPARISON Report per-belt and combined detector agreement.

    names = {'lungs', 'diaph'};
    for i = 1:numel(names)
        name = names{i};
        summary = comparison.(name);
        if ~summary.available
            continue;
        end
        log_message(config, 1, 'Sigh detection comparison (%s)', name);
        log_message(config, 1, ...
            ['rolling_median_2x: %d / %d breaths (%.2f%%), ' ...
             'threshold = %.2f'], summary.rolling_median_2x_count, ...
            summary.valid_breath_count, summary.rolling_median_2x_percent, ...
            summary.rolling_median_2x_threshold);
        log_message(config, 1, ...
            ['session_reference_2x: %d / %d breaths (%.2f%%), ' ...
             'threshold = %.2f'], summary.session_reference_2x_count, ...
            summary.valid_breath_count, summary.session_reference_2x_percent, ...
            summary.session_reference_2x_threshold);
        log_message(config, 1, ...
            ['overlap: %d | rolling only: %d | session only: %d | ' ...
             'agreement: %.2f%%'], summary.both_count, ...
            summary.rolling_median_2x_only_count, ...
            summary.session_reference_2x_only_count, ...
            summary.agreement_percent);
    end
    total = comparison.total;
    if total.available
        log_message(config, 1, ...
            ['Sigh comparison total: %d valid belt-breath observations | ' ...
             'rolling %d (%.2f%%) | session %d (%.2f%%) | overlap %d | ' ...
             'rolling only %d | session only %d | agreement %.2f%%'], ...
            total.valid_breath_count, total.rolling_median_2x_count, ...
            total.rolling_median_2x_percent, ...
            total.session_reference_2x_count, ...
            total.session_reference_2x_percent, total.both_count, ...
            total.rolling_median_2x_only_count, ...
            total.session_reference_2x_only_count, total.agreement_percent);
    end
end

function [ratio, flags, threshold, name] = ...
    comparison_overlay(comparison, primary_method, n_breaths)
% COMPARISON_OVERLAY Select the non-primary comparison trace for plotting.

    ratio = nan(n_breaths, 1);
    flags = false(n_breaths, 1);
    threshold = NaN;
    name = '';
    if ~isstruct(comparison) || ~isfield(comparison, 'available') || ...
            ~comparison.available
        return;
    end
    switch primary_method
        case 'rolling_median_2x'
            source_ratio = comparison.session_ratio;
            source_flags = comparison.session_flags;
            threshold = comparison.session_threshold;
            name = 'session_reference_2x';
        case 'session_reference_2x'
            source_ratio = comparison.rolling_ratio;
            source_flags = comparison.rolling_flags;
            threshold = comparison.rolling_threshold;
            name = 'rolling_median_2x';
        otherwise
            return;
    end
    assert_sigh_vector_length(source_ratio, n_breaths, ...
        'comparison ratio vector');
    assert_sigh_vector_length(source_flags, n_breaths, ...
        'comparison flag vector');
    ratio = source_ratio(:);
    flags = logical(source_flags(:));
end

function [sigh_flags, local_ref, ratio, ratio_thr, evaluable] = sigh_flags_global_ratio_outlier( ...
    b, ratio_prctile, min_abs_ratio, iqr_k, min_gap_sec)
% SIGH_FLAGS_GLOBAL_RATIO_OUTLIER Flag globally normalized amplitude outliers.
% b supplies aligned peak_t, amp, amp_ratio_global, and global reference.
% ratio_thr is the maximum of the requested percentile, median+iqr_k*IQR,
% and min_abs_ratio. sigh_flags is breath-level and retains only the strongest
% candidate within min_gap_sec; local_ref repeats the global belt amplitude.

    [peak_t, amp] = canonical_sigh_vectors(b);
    L = numel(peak_t);
    sigh_flags = false(L,1);
    ratio_thr = NaN;
    evaluable = false(L,1);
    [local_ref, ratio] = validated_global_sigh_evidence(b);

    if L < 10
        return;
    end

    valid = isfinite(ratio) & ratio > 0 & isfinite(amp) & amp > 0 & isfinite(local_ref) & local_ref > 0;

    if sum(valid) < 10
        return;
    end
    evaluable = valid;

    rv = ratio(valid);
    
    thr_pct = prctile(rv, ratio_prctile);
    thr_iqr = median(rv, 'omitnan') + iqr_k * iqr(rv);
    
    % Final threshold: percentile alone is not enough.
    % This prevents healthy controls from always getting the top 2% labeled.
    ratio_thr = max([thr_pct, thr_iqr, min_abs_ratio]);
    
    candidate_flags = false(L,1);
    candidate_flags(valid) = ratio(valid) >= ratio_thr;
    
    % Optional cleanup: keep only the strongest sigh within min_gap_sec.
    sigh_flags = enforce_min_gap_by_strength(candidate_flags, peak_t, ratio, min_gap_sec);
end


function [sigh_flags, baseline, ratio, evaluable] = sigh_flags_legacy_60s( ...
    b, prev_win_sec, amp_ratio_thr, min_prev_breaths)
% SIGH_FLAGS_LEGACY_60S Compare each breath with the preceding amplitude median.
% b supplies peak_t (s) and amp; a breath is flagged when it is at least
% amp_ratio_thr times the median of min_prev_breaths in the prior window.

    [peak_t, amp] = canonical_sigh_vectors(b);
    L = numel(peak_t);
    sigh_flags = false(L,1);
    baseline = nan(L,1);
    ratio = nan(L,1);
    evaluable = false(L,1);

    for i = 1:L
        t = peak_t(i);
        lb = t - prev_win_sec;
        if lb < 0, continue; end
        prev_idx = find(peak_t < t & peak_t >= lb);
        if numel(prev_idx) < min_prev_breaths, continue; end
        med_prev = median(amp(prev_idx), 'omitnan');
        if ~isfinite(med_prev) || med_prev <= 0 || ~isfinite(amp(i)), continue; end
        baseline(i) = med_prev;
        ratio(i) = amp(i) / med_prev;
        evaluable(i) = true;
        if amp(i) >= amp_ratio_thr * med_prev
            sigh_flags(i) = true;
        end
    end
end

% rest unchanged

function events = sigh_flags_to_events(lungs, diaph, flags_lungs, flags_diaph, N, fs)
% SIGH_FLAGS_TO_EVENTS Reuse review breath pairing, then select detected peaks.
% Pair the full valid breath trains, not just sighs: adjacent different breaths
% must not become a pair simply because they are the nearest two sighs.
% Flags have already passed the selected method and artifact rules above.

    belts = {lungs, diaph};
    flags = {flags_lungs, flags_diaph};
    names = {'lungs', 'diaph'};
    pairing = struct();
    selected = cell(1, 2);
    for i = 1:2
        peaks = belts{i}.peak_t(:);
        if numel(peaks) ~= numel(flags{i})
            error('MAGMA:Sigh:BreathAlignmentMismatch', ...
                'Sigh event flags must align one-to-one with breath peak times.');
        end
        pairing.(names{i}) = struct('peak_t', peaks, ...
            'amp', belts{i}.amp, 'available', belts{i}.available);
        selected{i} = round(peaks(logical(flags{i}(:))) * fs) + 1;
    end
    [candidates, ~, panel_peaks] = build_sigh_breath_candidates(pairing, N, fs);
    detected = [ismember(round(panel_peaks(:, 1) * fs) + 1, selected{1}), ...
        ismember(round(panel_peaks(:, 2) * fs) + 1, selected{2})];
    keep = any(detected, 2);
    events = candidates(keep);
    detected = detected(keep, :);
    panel_peaks = panel_peaks(keep, :);
    for i = 1:numel(events)
        panel = 1;
        if all(detected(i, :))
            events(i).belt = 'both';
        elseif detected(i, 1)
            events(i).belt = 'lungs';
        else
            panel = 2;
            events(i).belt = 'diaph';
        end
        % Use an actually selected peak; paired detections use the lung peak.
        peak = round(panel_peaks(i, panel) * fs) + 1;
        events(i).start_idx = peak;
        events(i).end_idx = peak;
        events(i).start_t = (peak - 1) / fs;
        events(i).end_t = peak / fs;
        events(i).duration = 1 / fs;
    end
    events = normalize_review_events(events, fs);
end

function flags_out = enforce_min_gap_by_strength(flags_in, peak_t, strength, min_gap_sec)
% ENFORCE_MIN_GAP_BY_STRENGTH Greedily retain strongest separated breath candidates.
% flags_in, peak_t (s), and strength are aligned breath vectors. Any weaker
% candidate within min_gap_sec of an already retained candidate is removed.

    flags_in = logical(flags_in(:));
    peak_t = peak_t(:);
    strength = strength(:);
    if numel(peak_t) ~= numel(flags_in) || ...
            numel(strength) ~= numel(flags_in)
        error('MAGMA:Sigh:BreathAlignmentMismatch', ...
            ['Sigh candidate flags, peak times, and decision strengths ' ...
             'must align one-to-one.']);
    end

    flags_out = false(size(flags_in));

    idx = find(flags_in);
    if isempty(idx)
        return;
    end

    % Sort candidates from strongest to weakest.
    [~, order] = sort(strength(idx), 'descend', 'MissingPlacement', 'last');
    idx_sorted = idx(order);

    for k = 1:numel(idx_sorted)
        i = idx_sorted(k);

        if ~isfinite(peak_t(i)) || ~isfinite(strength(i))
            continue;
        end

        already_kept = find(flags_out);
        if isempty(already_kept)
            flags_out(i) = true;
            continue;
        end

        too_close = any(abs(peak_t(already_kept) - peak_t(i)) < min_gap_sec);

        if ~too_close
            flags_out(i) = true;
        end
    end
end

function add_axis_legend(ax, handles, labels)
% ADD_AXIS_LEGEND Keep valid plotted data and non-XData graphics aligned.

    keep = false(size(handles));
    for i = 1:numel(handles)
        h = handles(i);
        if ~isgraphics(h)
            continue;
        end
        if isprop(h, 'XData')
            xdata = get(h, 'XData');
            if isempty(xdata)
                continue;
            end
        end
        keep(i) = true;
    end

    handles = handles(keep);
    labels = labels(keep);
    if isempty(handles)
        legend(ax, 'off');
        return;
    end
    legend(ax, handles, labels, 'Location', 'eastoutside');
end

function [flags,diagnostics] = gate_artifact_sigh(belt,flags,diagnostics,method,window_breaths,legacy_sec,fs)
    if ~isfield(belt,'artifact_intervals_idx') || isempty(belt.artifact_intervals_idx), return; end
    t = belt.peak_t(:); clean = true(size(t));
    for i = 1:numel(t)
        first = t(i); last = t(i);
        if strcmp(method,'rolling_median_2x')
            half = floor(window_breaths/2);
            center = max(half+1,min(numel(t)-half,i));
            first = t(max(1,center-half)); last = t(min(numel(t),center+half));
        elseif strcmp(method,'legacy_60s'), first = first-legacy_sec; end
        clean(i) = respiratory_artifact_window_valid(belt.artifact_intervals_idx,last,last-first,fs);
    end
    flags = flags & clean;
    for field = {'evaluable_mask','sigh_flags'}
        if isfield(diagnostics,field{1}), diagnostics.(field{1}) = diagnostics.(field{1}) & clean; end
    end
    for field = {'sigh_baseline','sigh_ratio'}
        if isfield(diagnostics,field{1}), diagnostics.(field{1})(~clean) = NaN; end
    end
    if isfield(diagnostics,'evaluable_mask'), diagnostics.available = any(diagnostics.evaluable_mask); end
end
