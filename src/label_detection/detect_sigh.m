function [events, diagnostics, review_info] = detect_sigh( ...
    data, resp_features, resp_cycles, config)
% DETECT_SIGH Identify isolated high-amplitude breaths and optionally review them.
% data/resp_cycles supply sample signals and breath markers; resp_features
% supplies the selected canonical amplitude plus global-normalized evidence;
% config selects the centered rolling-median, global-outlier, or legacy
% criterion plus plotting and review.
% events are midpoint-bounded breath events. diagnostics stores compact per-belt
% breath amplitude/baseline/ratio evidence and decision thresholds.
% review_info records review scope/status,
% sample review_mask, automatic/reviewed events, and per-belt breath flags.

    events = empty_events();

    N = size(data,1);
    fs = config.fs;

    lungs = resp_features.lungs;
    diaph = resp_features.diaph;
    amplitude_method = resolve_respiration_amplitude_method(config);

    method = 'rolling_median_2x';
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
    manual_window_sec = 1000;

    % Existing legacy criteria.
    legacy_prev_win_sec = 60;
    legacy_amp_ratio_thr = 1.5;
    legacy_min_prev_breaths = 3;

    if isfield(config, 'sigh')
        if isfield(config.sigh,'method'), method = config.sigh.method; end
        if isfield(config.sigh,'rolling_window_breaths'), rolling_window_breaths = config.sigh.rolling_window_breaths; end
        if isfield(config.sigh,'rolling_min_valid_breaths'), rolling_min_valid_breaths = config.sigh.rolling_min_valid_breaths; end
        if isfield(config.sigh,'rolling_ratio_threshold'), rolling_ratio_threshold = config.sigh.rolling_ratio_threshold; end
        if isfield(config.sigh,'compare_methods'), compare_methods = logical(config.sigh.compare_methods); end
        if isfield(config.sigh,'ratio_prctile'), ratio_prctile = config.sigh.ratio_prctile; end
        if isfield(config.sigh,'do_plot'), do_plot = config.sigh.do_plot; end
        if isfield(config.sigh,'manual_window_sec'), manual_window_sec = config.sigh.manual_window_sec; end
        if isfield(config.sigh,'min_abs_ratio'), min_abs_ratio = config.sigh.min_abs_ratio; end
        if isfield(config.sigh,'iqr_k'), iqr_k = config.sigh.iqr_k; end
        if isfield(config.sigh,'min_gap_sec'), min_gap_sec = config.sigh.min_gap_sec; end

        if isfield(config.sigh,'legacy_prev_win_sec'), legacy_prev_win_sec = config.sigh.legacy_prev_win_sec; end
        if isfield(config.sigh,'legacy_amp_ratio_thr'), legacy_amp_ratio_thr = config.sigh.legacy_amp_ratio_thr; end
        if isfield(config.sigh,'legacy_min_prev_breaths'), legacy_min_prev_breaths = config.sigh.legacy_min_prev_breaths; end
    end
    do_manual_review = manual_review_enabled(config);
    method = lower(char(string(method)));
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
    review_info = struct( ...
        'reviewed', false, ...
        'review_scope', 'unreviewed', ...
        'review_mask', false(N,1), ...
        'status', 'unreviewed', ...
        'automatic_events', empty_events(), ...
        'reviewed_events', empty_events(), ...
        'automatic_flags_lungs', false(size(lungs.peak_t(:))), ...
        'automatic_flags_diaph', false(size(diaph.peak_t(:))), ...
        'reviewed_flags_lungs', false(size(lungs.peak_t(:))), ...
        'reviewed_flags_diaph', false(size(diaph.peak_t(:))));

    sigh_lungs = false(size(lungs.peak_t(:)));
    sigh_diaph = false(size(diaph.peak_t(:)));
    switch method
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
                ['config.sigh.method must be ''rolling_median_2x'', ' ...
                 '''global_ratio_outlier'', or ''legacy_60s'' (received ''%s'').'], ...
                method);
    end
    diagnostics.available = diagnostics.lungs.available || ...
        diagnostics.diaph.available;

    comparison_details = empty_sigh_comparison_details();
    if compare_methods
        [diagnostics.comparison.lungs, comparison_details.lungs] = ...
            compare_sigh_methods(lungs, ...
                rolling_window_breaths, rolling_min_valid_breaths, ...
                rolling_ratio_threshold, ratio_prctile, min_abs_ratio, ...
                iqr_k, min_gap_sec);
        [diagnostics.comparison.diaph, comparison_details.diaph] = ...
            compare_sigh_methods(diaph, ...
                rolling_window_breaths, rolling_min_valid_breaths, ...
                rolling_ratio_threshold, ratio_prctile, min_abs_ratio, ...
                iqr_k, min_gap_sec);
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
    automatic_sigh_lungs = sigh_lungs;
    automatic_sigh_diaph = sigh_diaph;
    automatic_events_L = sigh_flags_to_events(lungs.peak_t, automatic_sigh_lungs, N, fs, 'lungs');
    automatic_events_D = sigh_flags_to_events(diaph.peak_t, automatic_sigh_diaph, N, fs, 'diaph');
    automatic_events = merge_events({automatic_events_L, automatic_events_D});
    review_info.automatic_events = automatic_events;
    review_info.automatic_flags_lungs = automatic_sigh_lungs;
    review_info.automatic_flags_diaph = automatic_sigh_diaph;

    if do_manual_review && diagnostics.lungs.available && diagnostics.diaph.available
        [sigh_lungs, sigh_diaph, sigh_review_mask] = manual_edit_sigh_flags( ...
            data, resp_cycles.lungs, resp_cycles.diaph, sigh_lungs, sigh_diaph, ...
            config, manual_window_sec);
        review_info.reviewed = true;
        review_info.review_scope = 'explicitly_viewed_regions_sigh_breaths_both_belts';
        review_info.review_mask = sigh_review_mask;
    elseif do_manual_review
        warning('MAGMA:Sigh:ManualSkipped', ...
            'Manual sigh editing requires two valid respiratory belts and was skipped for this input configuration.');
    end

    events_L = sigh_flags_to_events(lungs.peak_t, sigh_lungs, N, fs, 'lungs');
    events_D = sigh_flags_to_events(diaph.peak_t, sigh_diaph, N, fs, 'diaph');
    events = merge_events({events_L, events_D});
    review_info.reviewed_events = events;
    review_info.reviewed_flags_lungs = sigh_lungs;
    review_info.reviewed_flags_diaph = sigh_diaph;
    if review_info.reviewed
        if event_sets_equal(automatic_events, events)
            review_info.status = 'reviewed_accepted';
        elseif ~isempty(automatic_events) && isempty(events)
            review_info.status = 'reviewed_rejected';
        else
            review_info.status = 'reviewed_edited';
        end
    end

    if do_plot
        if ~isfield(config, 'channels')
            config = resolve_signal_channels(config);
        end
        idx_lungs = config.channels.lungs_idx;
        idx_diaph = config.channels.diaph_idx;

        t_raw = (0:N-1)/fs;

        figure('Units','pixels','Position', near_fullscreen_figure_position(), 'Visible', config.make_figs_visible);
        sgtitle(['SIGH | Method: ' method ' | Subject: ' ...
            num2str(config.subject) ' | Measurement: ' num2str(config.measure)])

        ax1 = subplot(4,1,1); hold on
        h_lungs_trace = gobjects(0);
        if ~isempty(idx_lungs), h_lungs_trace = plot(t_raw, data(:,idx_lungs), 'k', 'DisplayName', 'Resp-Lungs'); end
        h_lungs_events = shade_events_on_axis(gca, events, 'final sigh event');
        if ~isempty(idx_lungs)
            y_lungs_mark = interp1(t_raw, data(:,idx_lungs), lungs.peak_t(sigh_lungs), 'linear', 'extrap');
        else
            y_lungs_mark = nan(sum(sigh_lungs),1);
        end
        h_lungs_sigh = plot(lungs.peak_t(sigh_lungs), y_lungs_mark, 'ro', 'MarkerFaceColor','r', ...
            'DisplayName', 'Sigh breaths');
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
        if ~isempty(idx_diaph)
            y_diaph_mark = interp1(t_raw, data(:,idx_diaph), diaph.peak_t(sigh_diaph), 'linear', 'extrap');
        else
            y_diaph_mark = nan(sum(sigh_diaph),1);
        end
        h_diaph_sigh = plot(diaph.peak_t(sigh_diaph), y_diaph_mark, 'ro', 'MarkerFaceColor','r', ...
            'DisplayName', 'Sigh breaths');
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

    handles = trace_handle;
    labels = {trace_label};
    if isempty(trace_handle)
        labels = cell(0, 1);
    end
    if ~isempty(event_handles)
        handles(end + 1, 1) = event_handles(1);
        labels{end + 1} = 'final sigh event';
    end
    handles(end + 1, 1) = sigh_handle;
    labels{end + 1} = 'Sigh breaths';
end

function plot_sigh_ratio_evidence( ...
    ax, belt, belt_diagnostics, selected_mask, belt_name, comparison)
% PLOT_SIGH_RATIO_EVIDENCE Show primary breath ratios and optional comparison.

    hold(ax, 'on');
    title(ax, sprintf('Sigh amplitude-ratio evidence (%s, %s)', ...
        belt_name, belt_diagnostics.method), 'Interpreter', 'none');
    xlabel(ax, 'Breath index');
    ylabel(ax, 'Sigh amplitude / method baseline');
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
    handles = h_ratios;
    labels = {'primary breath ratios'};
    if ~isempty(h_threshold) && isgraphics(h_threshold)
        handles(end + 1, 1) = h_threshold;
        labels{end + 1} = 'primary threshold';
    end
    if any(sigh_mask)
        h_sighs = plot(ax, breath_index(sigh_mask), ratio(sigh_mask), 'ro', ...
            'LineStyle', 'none', 'MarkerFaceColor', 'r', 'MarkerSize', 6, ...
            'DisplayName', 'primary sigh breaths');
        handles(end + 1, 1) = h_sighs;
        labels{end + 1} = 'primary sigh breaths';
    end

    [other_ratio, other_flags, other_threshold, other_name] = ...
        comparison_overlay(comparison, belt_diagnostics.method, n_breaths);
    other_valid = isfinite(other_ratio) & other_ratio > 0;
    if any(other_valid)
        h_other = plot(ax, breath_index(other_valid), other_ratio(other_valid), 's', ...
            'LineStyle', 'none', 'Color', [0.10 0.35 0.90], ...
            'MarkerSize', 4, 'DisplayName', [other_name ' ratios']);
        handles(end + 1, 1) = h_other;
        labels{end + 1} = [other_name ' ratios'];
        if isfinite(other_threshold)
            h_other_threshold = yline(ax, other_threshold, ':', ...
                'Color', [0.10 0.35 0.90], 'LineWidth', 1.2, ...
                'DisplayName', [other_name ' threshold']);
            handles(end + 1, 1) = h_other_threshold;
            labels{end + 1} = [other_name ' threshold'];
        end
        other_sighs = other_valid & other_flags;
        if any(other_sighs)
            h_other_sighs = plot(ax, breath_index(other_sighs), ...
                other_ratio(other_sighs), 'x', 'LineStyle', 'none', ...
                'Color', [0.10 0.35 0.90], 'MarkerSize', 7, 'LineWidth', 1.2, ...
                'DisplayName', [other_name ' sigh breaths']);
            handles(end + 1, 1) = h_other_sighs;
            labels{end + 1} = [other_name ' sigh breaths'];
        end
    end
    add_axis_legend(ax, handles, labels);
    hold(ax, 'off');
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
    [unavailable, unavailable_status] = sigh_belt_unavailable(belt);
    if ~unavailable
        unavailable_status = 'belt_unavailable';
    end
    diagnostics = struct( ...
        'available', false, ...
        'reference_quality', reference_quality, ...
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
        'global_ratio_outlier_count', 0, ...
        'global_ratio_outlier_percent', NaN, ...
        'global_ratio_outlier_threshold', NaN, ...
        'both_count', 0, ...
        'rolling_median_2x_only_count', 0, ...
        'global_ratio_outlier_only_count', 0, ...
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
        'global_ratio', [], ...
        'global_flags', false(0, 1), ...
        'global_threshold', NaN);
end

function [summary, detail] = compare_sigh_methods( ...
    feature_belt, window_breaths, min_valid, ...
    rolling_threshold, ratio_prctile, min_abs_ratio, iqr_k, min_gap_sec)
% COMPARE_SIGH_METHODS Compare rolling and unchanged global detector outputs.

    summary = empty_sigh_comparison_summary();
    detail = empty_sigh_comparison_detail();
    [rolling_flags, ~, rolling_ratio, rolling_threshold, ~, ...
        rolling_available, rolling_evaluable] = ...
        sigh_flags_rolling_median_2x(feature_belt, ...
            window_breaths, min_valid, rolling_threshold);
    if global_sigh_inputs_available(feature_belt)
        [global_flags, ~, global_ratio, global_threshold, global_evaluable] = ...
            sigh_flags_global_ratio_outlier(feature_belt, ratio_prctile, ...
                min_abs_ratio, iqr_k, min_gap_sec);
    else
        global_flags = false(size(rolling_flags));
        global_ratio = nan(size(rolling_ratio));
        global_threshold = NaN;
        global_evaluable = false(size(rolling_evaluable));
    end

    n = numel(feature_belt.peak_t);
    assert_sigh_vector_length(rolling_flags, n, 'rolling flags');
    assert_sigh_vector_length(rolling_ratio, n, 'rolling ratios');
    assert_sigh_vector_length(rolling_evaluable, n, 'rolling evaluable mask');
    assert_sigh_vector_length(global_flags, n, 'global flags');
    assert_sigh_vector_length(global_ratio, n, 'global ratios');
    assert_sigh_vector_length(global_evaluable, n, 'global evaluable mask');
    rolling_flags = logical(rolling_flags(:));
    rolling_ratio = rolling_ratio(:);
    global_flags = logical(global_flags(:));
    global_ratio = global_ratio(:);
    valid = logical(rolling_evaluable(:)) & logical(global_evaluable(:));

    detail.available = rolling_available && isfinite(global_threshold) && any(valid);
    detail.rolling_ratio = rolling_ratio;
    detail.rolling_flags = rolling_flags;
    detail.rolling_threshold = rolling_threshold;
    detail.global_ratio = global_ratio;
    detail.global_flags = global_flags;
    detail.global_threshold = global_threshold;

    summary.available = detail.available;
    summary.valid_breath_count = sum(valid);
    summary.rolling_median_2x_count = sum(valid & rolling_flags);
    summary.global_ratio_outlier_count = sum(valid & global_flags);
    summary.both_count = sum(valid & rolling_flags & global_flags);
    summary.rolling_median_2x_only_count = ...
        sum(valid & rolling_flags & ~global_flags);
    summary.global_ratio_outlier_only_count = ...
        sum(valid & ~rolling_flags & global_flags);
    summary.agreement_count = sum(valid & (rolling_flags == global_flags));
    summary.rolling_median_2x_threshold = rolling_threshold;
    summary.global_ratio_outlier_threshold = global_threshold;
    summary = add_sigh_comparison_percentages(summary);
end

function summary = aggregate_sigh_comparison(lungs, diaph)
% AGGREGATE_SIGH_COMPARISON Sum per-belt comparison observations.

    summary = empty_sigh_comparison_summary();
    fields = {'valid_breath_count', 'rolling_median_2x_count', ...
        'global_ratio_outlier_count', 'both_count', ...
        'rolling_median_2x_only_count', ...
        'global_ratio_outlier_only_count', 'agreement_count'};
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
    summary.global_ratio_outlier_percent = ...
        100 * summary.global_ratio_outlier_count / n;
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
            ['global_ratio_outlier: %d / %d breaths (%.2f%%), ' ...
             'threshold = %.2f'], summary.global_ratio_outlier_count, ...
            summary.valid_breath_count, summary.global_ratio_outlier_percent, ...
            summary.global_ratio_outlier_threshold);
        log_message(config, 1, ...
            ['overlap: %d | rolling only: %d | global only: %d | ' ...
             'agreement: %.2f%%'], summary.both_count, ...
            summary.rolling_median_2x_only_count, ...
            summary.global_ratio_outlier_only_count, ...
            summary.agreement_percent);
    end
    total = comparison.total;
    if total.available
        log_message(config, 1, ...
            ['Sigh comparison total: %d valid belt-breath observations | ' ...
             'rolling %d (%.2f%%) | global %d (%.2f%%) | overlap %d | ' ...
             'rolling only %d | global only %d | agreement %.2f%%'], ...
            total.valid_breath_count, total.rolling_median_2x_count, ...
            total.rolling_median_2x_percent, ...
            total.global_ratio_outlier_count, ...
            total.global_ratio_outlier_percent, total.both_count, ...
            total.rolling_median_2x_only_count, ...
            total.global_ratio_outlier_only_count, total.agreement_percent);
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
            source_ratio = comparison.global_ratio;
            source_flags = comparison.global_flags;
            threshold = comparison.global_threshold;
            name = 'global_ratio_outlier';
        case 'global_ratio_outlier'
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

function tf = event_sets_equal(a, b)
% EVENT_SETS_EQUAL Compare event type and sample bounds independent of ordering.

    if numel(a) ~= numel(b)
        tf = false;
        return;
    end
    if isempty(a)
        tf = true;
        return;
    end
    a = sortrows(struct2table(a), {'type', 'start_idx', 'end_idx'});
    b = sortrows(struct2table(b), {'type', 'start_idx', 'end_idx'});
    tf = isequal(a.type, b.type) && isequal(a.start_idx, b.start_idx) && ...
        isequal(a.end_idx, b.end_idx);
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

function events = sigh_flags_to_events(peak_t, flags, N, fs, belt)
% SIGH_FLAGS_TO_EVENTS Convert selected breaths to midpoint-bounded events.
% peak_t is seconds and flags is an aligned breath-level mask. N/fs clamp
% canonical sample/time bounds; belt is appended to the sigh event type.

    events = empty_events();
    peak_t = peak_t(:);
    flags  = logical(flags(:));
    if numel(peak_t) ~= numel(flags)
        error('MAGMA:Sigh:BreathAlignmentMismatch', ...
            'Sigh event flags must align one-to-one with breath peak times.');
    end
    L = numel(peak_t);

    n_events = sum(flags);
    if n_events == 0
        return;
    end
    template = struct( ...
        'type', '', ...
        'start_idx', 0, ...
        'end_idx', 0, ...
        'start_t', 0, ...
        'end_t', 0, ...
        'duration', 0);
    events = repmat(template, n_events, 1);
    out = 0;

    for i = 1:L
        if ~flags(i), continue; end

        t0 = peak_t(i);
        if i == 1 && L >= 2
            dt = peak_t(i+1) - peak_t(i);
            start_t = max(0, t0 - 0.5*dt);
        elseif i > 1
            start_t = 0.5*(peak_t(i-1) + peak_t(i));
        else
            start_t = max(0, t0 - 0.5); % fallback
        end

        if i == L && L >= 2
            dt = peak_t(i) - peak_t(i-1);
            end_t = min(N/fs, t0 + 0.5*dt);
        elseif i < L
            end_t = 0.5*(peak_t(i) + peak_t(i+1));
        else
            end_t = min(N/fs, t0 + 0.5); % fallback
        end

        s = max(1, min(N, round(start_t*fs) + 1));
        e = max(s, min(N, round(end_t*fs)));

        start_t = (s-1)/fs;
        end_t   = e/fs;

        out = out + 1;
        events(out) = struct( ...
            'type', ['sigh_' belt], ...
            'start_idx', s, ...
            'end_idx', e, ...
            'start_t', start_t, ...
            'end_t', end_t, ...
            'duration', (e - s + 1) / fs );

    end

    events = events(1:out);
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
