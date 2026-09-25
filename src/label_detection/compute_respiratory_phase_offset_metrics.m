function metrics = compute_respiratory_phase_offset_metrics(data, resp_cycles, config)
% COMPUTE_RESPIRATORY_PHASE_OFFSET_METRICS Measure thoracoabdominal phase offset.
% Both recorded/configured-polarity belts are evaluated at one shared wavelet
% frequency. Reviewed peak timing guides the respiratory fundamental where a
% valid inter-breath interval exists; joint belt magnitude selects within that
% neighborhood and is the documented fallback when timing is unavailable.
% Contiguous finite two-belt blocks are transformed independently. wtI cone-of-
% influence NaNs plus an explicit one-lowest-eligible-frequency-cycle margin
% prevent five-cycle circular summaries from crossing gaps or transform edges.
% No polarity optimization, time shift, raw absolute-value transform, breath
% redetection, or session-reference phase normalization is applied.

    N = size(data, 1);
    t_grid = (0:config.grid_step_sec:(N - 1) / config.fs)';
    metrics = empty_phase_offset_metrics(t_grid, config);
    metrics.master_n_samples = N;

    if ~isfield(config, 'channels')
        config = resolve_signal_channels(config);
    end
    idx_lungs = config.channels.lungs_idx;
    idx_diaph = config.channels.diaph_idx;
    if isempty(idx_lungs) || isempty(idx_diaph) || ...
            idx_lungs > size(data, 2) || idx_diaph > size(data, 2)
        metrics.availability_reason = 'missing_respiratory_belt_channel';
        return;
    end
    if is_lung_belt_ignored(config)
        metrics.availability_reason = 'lung_belt_marked_missing';
        return;
    end

    lungs_raw = data(:, idx_lungs);
    diaph_raw = data(:, idx_diaph);
    pair_valid = isfinite(lungs_raw) & isfinite(diaph_raw);
    if nnz(pair_valid) < 2
        metrics.availability_reason = 'flat_or_invalid_respiratory_signal';
        return;
    end
    [block_starts, block_ends] = logical_runs(pair_valid);
    metrics.input_valid_block_count = numel(block_starts);
    metrics.minimum_block_duration_sec = ...
        (metrics.summary_cycles + 2 * metrics.edge_exclusion_cycles) / ...
        metrics.frequency_max_hz;

    old_visibility = get(groot, 'defaultFigureVisible');
    existing_figures = findall(groot, 'Type', 'figure');
    target_visibility = phase_figure_visibility(config);
    cleanup = onCleanup(@() restore_phase_figure_visibility( ...
        old_visibility, existing_figures, target_visibility));
    set(groot, 'defaultFigureVisible', target_visibility);

    magnitude_floor_lungs = [];
    magnitude_floor_diaph = [];
    analyzed_block_count = 0;
    for input_block = 1:numel(block_starts)
        start_idx = block_starts(input_block);
        end_idx = block_ends(input_block);
        block_duration_sec = (end_idx - start_idx + 1) / config.fs;
        if block_duration_sec < metrics.minimum_block_duration_sec
            metrics.short_block_count = metrics.short_block_count + 1;
            continue;
        end

        lungs_block = metrics.lungs_polarity_multiplier * ...
            lungs_raw(start_idx:end_idx);
        diaph_block = metrics.diaph_polarity_multiplier * ...
            diaph_raw(start_idx:end_idx);
        [lungs_block, lungs_ok] = prepare_phase_block(lungs_block);
        [diaph_block, diaph_ok] = prepare_phase_block(diaph_block);
        if ~lungs_ok || ~diaph_ok
            metrics.flat_block_count = metrics.flat_block_count + 1;
            continue;
        end

        try
            [lungs_analysis, diaph_analysis, fs_analysis] = ...
                resample_respiration_for_analysis(lungs_block, diaph_block, ...
                    config.fs, metrics.analysis_fs);
            metrics.analysis_fs = fs_analysis;
            n_analysis = numel(lungs_analysis);
            if n_analysis < 2
                metrics.short_block_count = metrics.short_block_count + 1;
                continue;
            end
            local_t = (0:n_analysis - 1)' / fs_analysis;
            block_start_t = (start_idx - 1) / config.fs;
            absolute_t = block_start_t + local_t;
            [expected_frequency, lungs_timing, diaph_timing] = ...
                reviewed_frequency_trace(resp_cycles, absolute_t, ...
                    pair_valid, config.fs, metrics.frequency_min_hz, ...
                    metrics.frequency_max_hz);
            metrics.breath_timing_available_lungs = ...
                metrics.breath_timing_available_lungs || any(isfinite(lungs_timing));
            metrics.breath_timing_available_diaph = ...
                metrics.breath_timing_available_diaph || any(isfinite(diaph_timing));

            fmax = min(metrics.frequency_max_hz, 0.95 * fs_analysis / 2);
            if metrics.frequency_min_hz >= fmax
                metrics.availability_reason = 'invalid_respiratory_frequency_range';
                return;
            end
            [wt_lungs, frequency] = wtI(lungs_analysis, fs_analysis, ...
                'fmin', metrics.frequency_min_hz, 'fmax', fmax, ...
                'f0', metrics.f0, 'Plot', 'off', 'Display', 'off', ...
                'CutEdges', 'on', 'Padding', 'none');
            [wt_diaph, frequency_diaph] = wtI(diaph_analysis, fs_analysis, ...
                'fmin', metrics.frequency_min_hz, 'fmax', fmax, ...
                'f0', metrics.f0, 'Plot', 'off', 'Display', 'off', ...
                'CutEdges', 'on', 'Padding', 'none');
            [wt_lungs, wt_diaph, frequency] = align_phase_wavelets( ...
                wt_lungs, wt_diaph, frequency, frequency_diaph);
            if isempty(frequency) || isempty(wt_lungs) || isempty(wt_diaph)
                metrics.failed_block_count = metrics.failed_block_count + 1;
                continue;
            end

            eligible_floor = lowest_eligible_frequency(expected_frequency, ...
                metrics.frequency_min_hz, metrics.frequency_tolerance_fraction);
            edge_sec = metrics.edge_exclusion_cycles / eligible_floor;
            explicit_edge_valid = local_t >= edge_sec & ...
                local_t <= local_t(end) - edge_sec;
            [phase_rad, selected_frequency, coefficient_valid, ...
                transform_support, floors, selection_mode] = ...
                shared_frequency_phase(wt_lungs, wt_diaph, frequency, ...
                    expected_frequency, explicit_edge_valid, ...
                    metrics.frequency_tolerance_fraction, ...
                    metrics.min_magnitude_fraction);

            global_idx = find(t_grid >= block_start_t & ...
                t_grid <= (end_idx - 1) / config.fs);
            if isempty(global_idx)
                continue;
            end
            local_grid_t = t_grid(global_idx) - block_start_t;
            [mean_deg, resultant, selected_grid, expected_grid, ...
                mode_grid, valid_grid] = summarize_phase_on_grid( ...
                    phase_rad, selected_frequency, expected_frequency, ...
                    selection_mode, coefficient_valid, transform_support, ...
                    fs_analysis, local_grid_t, metrics.summary_cycles, ...
                    metrics.min_valid_fraction);

            analyzed_block_count = analyzed_block_count + 1;
            metrics.valid_block_id(global_idx) = analyzed_block_count;
            metrics.valid_block_bounds_sec(analyzed_block_count, :) = ...
                [block_start_t end_idx / config.fs];
            metrics.signed_mean_phase_deg(global_idx) = mean_deg;
            metrics.resultant_length(global_idx) = resultant;
            metrics.selected_resp_frequency_hz(global_idx) = selected_grid;
            metrics.expected_resp_frequency_hz(global_idx) = expected_grid;
            metrics.frequency_selection_mode(global_idx) = mode_grid;
            metrics.valid_phase_mask(global_idx) = valid_grid;
            metrics.analysis_n_samples = metrics.analysis_n_samples + n_analysis;
            metrics.analysis_duration_sec = metrics.analysis_duration_sec + ...
                n_analysis / fs_analysis;
            magnitude_floor_lungs(end + 1, 1) = floors.lungs; %#ok<AGROW>
            magnitude_floor_diaph(end + 1, 1) = floors.diaph; %#ok<AGROW>
        catch ME
            metrics.failed_block_count = metrics.failed_block_count + 1;
            metrics.error_message = append_error_message( ...
                metrics.error_message, ME.message);
        end
    end

    metrics.valid_block_count = analyzed_block_count;
    metrics.magnitude_floors = struct( ...
        'lungs', finite_median(magnitude_floor_lungs), ...
        'diaph', finite_median(magnitude_floor_diaph));
    metrics.absolute_mean_phase_deg = abs(metrics.signed_mean_phase_deg);
    ratio_valid = isfinite(metrics.selected_resp_frequency_hz) & ...
        isfinite(metrics.expected_resp_frequency_hz) & ...
        metrics.expected_resp_frequency_hz > 0;
    metrics.selected_to_expected_frequency_ratio(ratio_valid) = ...
        metrics.selected_resp_frequency_hz(ratio_valid) ./ ...
        metrics.expected_resp_frequency_hz(ratio_valid);
    qc_range = metrics.frequency_ratio_qc_range;
    metrics.frequency_consistent_with_breath_timing(ratio_valid) = double( ...
        metrics.selected_to_expected_frequency_ratio(ratio_valid) >= qc_range(1) & ...
        metrics.selected_to_expected_frequency_ratio(ratio_valid) <= qc_range(2));
    metrics.reliable_phase_mask = metrics.valid_phase_mask & ...
        metrics.resultant_length >= metrics.min_resultant_length;
    metrics.candidate_mask = metrics.reliable_phase_mask & ...
        metrics.absolute_mean_phase_deg >= metrics.angle_threshold_deg;
    metrics.cohort_qc = phase_recording_qc(metrics);
    metrics.available = any(metrics.reliable_phase_mask);
    if metrics.available
        metrics.availability_reason = 'available';
    elseif any(metrics.valid_phase_mask)
        metrics.availability_reason = 'no_reliable_circular_phase_summary';
    elseif metrics.failed_block_count > 0 && analyzed_block_count == 0
        metrics.availability_reason = 'wavelet_computation_failed';
    else
        metrics.availability_reason = 'no_valid_shared_frequency_phase_evidence';
    end
end

function metrics = empty_phase_offset_metrics(t_grid, config)
% EMPTY_PHASE_OFFSET_METRICS Initialize compact phase-offset evidence.

    lungs_multiplier = phase_setting(config, 'lungs_polarity_multiplier', 1);
    diaph_multiplier = phase_setting(config, 'diaph_polarity_multiplier', 1);
    if ~isscalar(lungs_multiplier) || ~isfinite(lungs_multiplier) || ...
            ~ismember(lungs_multiplier, [-1 1]) || ...
            ~isscalar(diaph_multiplier) || ~isfinite(diaph_multiplier) || ...
            ~ismember(diaph_multiplier, [-1 1])
        error('MAGMA:RespiratoryPhaseOffset:InvalidSetting', ...
            'Phase-offset belt polarity multipliers must each be +1 or -1.');
    end
    if lungs_multiplier == 1 && diaph_multiplier == 1
        polarity_source = 'preprocessing_standardized_belt_polarity';
    else
        polarity_source = ...
            'preprocessing_standardized_then_user_configured_fixed_hardware_correction';
    end
    polarity_convention = ...
        ['preprocessing_standardized_plus_configured_fixed_multipliers_' ...
         'thoracic_minus_abdominal_no_phase_optimization'];
    frequency_selection = [ ...
        'reviewed_breath_timing_guided_joint_magnitude_or_' ...
        'joint_wavelet_magnitude_fallback_at_one_shared_frequency'];
    edge_rule = [ ...
        'independent_finite_blocks_with_wtI_CutEdges_and_explicit_' ...
        'lowest_locally_eligible_frequency_cycle_margin'];

    metrics = struct( ...
        'method', 'wavelet_phase_offset', ...
        'available', false, ...
        'availability_reason', 'not_evaluated', ...
        'error_message', '', ...
        'time_sec', t_grid, ...
        'signed_mean_phase_deg', nan(size(t_grid)), ...
        'absolute_mean_phase_deg', nan(size(t_grid)), ...
        'resultant_length', nan(size(t_grid)), ...
        'expected_resp_frequency_hz', nan(size(t_grid)), ...
        'selected_resp_frequency_hz', nan(size(t_grid)), ...
        'selected_to_expected_frequency_ratio', nan(size(t_grid)), ...
        'frequency_selection_mode', ...
            {repmat({'unavailable'}, size(t_grid))}, ...
        'frequency_consistent_with_breath_timing', nan(size(t_grid)), ...
        'valid_block_id', nan(size(t_grid)), ...
        'valid_phase_mask', false(size(t_grid)), ...
        'reliable_phase_mask', false(size(t_grid)), ...
        'candidate_mask', false(size(t_grid)), ...
        'event_mask', false(size(t_grid)), ...
        'events', empty_events(), ...
        'analysis_fs', get_config_value(config, 'async', 'analysis_fs', ...
            min(config.fs, 20)), ...
        'analysis_n_samples', 0, ...
        'analysis_duration_sec', 0, ...
        'master_fs', config.fs, ...
        'master_n_samples', 0, ...
        'f0', get_config_value(config, 'async', 'f0', 1), ...
        'frequency_min_hz', phase_setting(config, 'frequency_min_hz', 0.052), ...
        'frequency_max_hz', phase_setting(config, 'frequency_max_hz', 0.60), ...
        'frequency_tolerance_fraction', phase_setting(config, ...
            'frequency_tolerance_fraction', 0.30), ...
        'frequency_ratio_qc_range', phase_setting(config, ...
            'frequency_ratio_qc_range', [0.5 1.5]), ...
        'angle_threshold_deg', phase_setting(config, ...
            'angle_threshold_deg', 30), ...
        'summary_cycles', phase_setting(config, 'summary_cycles', 5), ...
        'min_resultant_length', phase_setting(config, ...
            'min_resultant_length', 0.80), ...
        'min_valid_fraction', phase_setting(config, ...
            'min_valid_fraction', 0.80), ...
        'min_magnitude_fraction', phase_setting(config, ...
            'min_magnitude_fraction', 0.05), ...
        'edge_exclusion_cycles', phase_setting(config, ...
            'edge_exclusion_cycles', 1), ...
        'lungs_polarity_multiplier', lungs_multiplier, ...
        'diaph_polarity_multiplier', diaph_multiplier, ...
        'polarity_source', polarity_source, ...
        'magnitude_floors', struct('lungs', NaN, 'diaph', NaN), ...
        'min_dur_sec', get_config_value(config, 'async', 'min_dur_sec', 30), ...
        'input_valid_block_count', 0, ...
        'valid_block_count', 0, ...
        'short_block_count', 0, ...
        'flat_block_count', 0, ...
        'failed_block_count', 0, ...
        'minimum_block_duration_sec', NaN, ...
        'valid_block_bounds_sec', zeros(0, 2), ...
        'breath_timing_available_lungs', false, ...
        'breath_timing_available_diaph', false, ...
        'cohort_qc', empty_phase_recording_qc(), ...
        'polarity_convention', polarity_convention, ...
        'frequency_selection', frequency_selection, ...
        'reference_normalization', 'none', ...
        'literature_motivation', ...
            ['Motto_2005_10.1109/TBME.2005.844026;' ...
             'Chen_Hsiao_2016_10.1186/s12938-016-0233-7'], ...
        'implementation_scope', ...
            'MAGMA_wavelet_phase_offset_not_exact_tidal_volume_replication', ...
        'provenance', struct( ...
            'polarity_convention', polarity_convention, ...
            'lungs_polarity_multiplier', lungs_multiplier, ...
            'diaph_polarity_multiplier', diaph_multiplier, ...
            'polarity_source', polarity_source, ...
            'frequency_selection', frequency_selection, ...
            'breath_timing_source', ...
                'reviewed_canonical_peak_times_piecewise_over_valid_IBIs', ...
            'frequency_selection_modes', ...
                {{'breath_timing_guided', 'joint_wavelet_magnitude_fallback'}}, ...
            'gap_handling', ...
                'contiguous_finite_two_belt_blocks_transformed_independently', ...
            'transform_edge_exclusion', edge_rule, ...
            'frequency_ratio_qc_role', ...
                'descriptive_only_not_an_asynchrony_event_criterion', ...
            'reference_normalization', 'none', ...
            'literature_motivation', ...
                ['Motto_2005_10.1109/TBME.2005.844026;' ...
                 'Chen_Hsiao_2016_10.1186/s12938-016-0233-7'], ...
            'implementation_scope', ...
                'MAGMA_wavelet_phase_offset_not_exact_tidal_volume_replication'));
    validate_phase_settings(metrics);
end

function value = phase_setting(config, name, default_value)
% PHASE_SETTING Read one nested config.async.phase_offset value.

    value = default_value;
    if isfield(config, 'async') && isfield(config.async, 'phase_offset') && ...
            isfield(config.async.phase_offset, name)
        value = config.async.phase_offset.(name);
    end
end

function validate_phase_settings(metrics)
% VALIDATE_PHASE_SETTINGS Reject invalid operational comparison settings.

    positive = {'analysis_fs', 'frequency_min_hz', 'frequency_max_hz', ...
        'summary_cycles', 'min_dur_sec', 'edge_exclusion_cycles'};
    for i = 1:numel(positive)
        value = metrics.(positive{i});
        if ~isscalar(value) || ~isfinite(value) || value <= 0
            error('MAGMA:RespiratoryPhaseOffset:InvalidSetting', ...
                '%s must be a finite positive scalar.', positive{i});
        end
    end
    ratio_range = metrics.frequency_ratio_qc_range;
    multipliers = [metrics.lungs_polarity_multiplier ...
        metrics.diaph_polarity_multiplier];
    if metrics.frequency_min_hz >= metrics.frequency_max_hz || ...
            ~isscalar(metrics.frequency_tolerance_fraction) || ...
            ~isfinite(metrics.frequency_tolerance_fraction) || ...
            metrics.frequency_tolerance_fraction < 0 || ...
            metrics.frequency_tolerance_fraction >= 1 || ...
            ~isnumeric(ratio_range) || numel(ratio_range) ~= 2 || ...
            any(~isfinite(ratio_range)) || ratio_range(1) <= 0 || ...
            ratio_range(1) >= ratio_range(2) || ...
            any(~ismember(multipliers, [-1 1])) || ...
            ~isscalar(metrics.angle_threshold_deg) || ...
            ~isfinite(metrics.angle_threshold_deg) || ...
            metrics.angle_threshold_deg < 0 || metrics.angle_threshold_deg > 180 || ...
            ~isscalar(metrics.min_resultant_length) || ...
            ~isfinite(metrics.min_resultant_length) || ...
            metrics.min_resultant_length < 0 || metrics.min_resultant_length > 1 || ...
            ~isscalar(metrics.min_valid_fraction) || ...
            ~isfinite(metrics.min_valid_fraction) || ...
            metrics.min_valid_fraction <= 0 || metrics.min_valid_fraction > 1 || ...
            ~isscalar(metrics.min_magnitude_fraction) || ...
            ~isfinite(metrics.min_magnitude_fraction) || ...
            metrics.min_magnitude_fraction < 0
        error('MAGMA:RespiratoryPhaseOffset:InvalidSetting', ...
            ['Invalid phase-offset frequency, polarity, angle, reliability, ' ...
             'or validity setting.']);
    end
end

function [starts, ends] = logical_runs(mask)
% LOGICAL_RUNS Return inclusive bounds of contiguous true samples.

    d = diff([false; logical(mask(:)); false]);
    starts = find(d == 1);
    ends = find(d == -1) - 1;
end

function [x, ok] = prepare_phase_block(x)
% PREPARE_PHASE_BLOCK Robustly center/scale one already-finite valid block.

    x = x(:);
    ok = numel(x) >= 2 && all(isfinite(x));
    if ~ok
        return;
    end
    x = x - median(x, 'omitnan');
    scale = 1.4826 * median(abs(x), 'omitnan');
    if ~isfinite(scale) || scale <= eps
        scale = std(x, 'omitnan');
    end
    ok = isfinite(scale) && scale > eps;
    if ok
        x = x ./ scale;
    end
end

function [expected, lungs_frequency, diaph_frequency] = ...
    reviewed_frequency_trace(resp_cycles, query_t, pair_valid, fs, fmin, fmax)
% REVIEWED_FREQUENCY_TRACE Combine piecewise reviewed-breath IBI frequencies.
% No interpolation is performed: 1/IBI applies only between its two reviewed
% peaks, and an IBI crossing any invalid two-belt sample is discarded.

    lungs_frequency = nan(size(query_t));
    diaph_frequency = nan(size(query_t));
    if isstruct(resp_cycles) && isfield(resp_cycles, 'lungs')
        lungs_frequency = belt_frequency_trace(resp_cycles.lungs, query_t, ...
            pair_valid, fs, fmin, fmax);
    end
    if isstruct(resp_cycles) && isfield(resp_cycles, 'diaph')
        diaph_frequency = belt_frequency_trace(resp_cycles.diaph, query_t, ...
            pair_valid, fs, fmin, fmax);
    end
    expected = nan(size(query_t));
    both = isfinite(lungs_frequency) & isfinite(diaph_frequency);
    expected(both) = 0.5 * ...
        (lungs_frequency(both) + diaph_frequency(both));
    lungs_only = isfinite(lungs_frequency) & ~isfinite(diaph_frequency);
    expected(lungs_only) = lungs_frequency(lungs_only);
    diaph_only = ~isfinite(lungs_frequency) & isfinite(diaph_frequency);
    expected(diaph_only) = diaph_frequency(diaph_only);
end

function frequency_trace = belt_frequency_trace( ...
    belt, query_t, pair_valid, fs, fmin, fmax)
% BELT_FREQUENCY_TRACE Assign 1/IBI only inside valid reviewed peak pairs.

    frequency_trace = nan(size(query_t));
    if ~isstruct(belt) || (isfield(belt, 'ok') && ~belt.ok) || ...
            ~isfield(belt, 'peak_t')
        return;
    end
    peak_t = belt.peak_t(:);
    peak_t = peak_t(isfinite(peak_t));
    peak_t = unique(sort(peak_t));
    for i = 1:numel(peak_t) - 1
        ibi = peak_t(i + 1) - peak_t(i);
        frequency = 1 / ibi;
        if ~isfinite(frequency) || ibi <= 0 || ...
                frequency < fmin || frequency > fmax
            continue;
        end
        first = round(peak_t(i) * fs) + 1;
        last = round(peak_t(i + 1) * fs) + 1;
        if first < 1 || last > numel(pair_valid) || last <= first || ...
                ~all(pair_valid(first:last))
            continue;
        end
        in_interval = query_t >= peak_t(i) & query_t <= peak_t(i + 1);
        frequency_trace(in_interval) = frequency;
    end
end

function floor_frequency = lowest_eligible_frequency(expected, fmin, tolerance)
% LOWEST_ELIGIBLE_FREQUENCY Set the explicit block-edge support scale.

    expected = expected(isfinite(expected) & expected > 0);
    if isempty(expected)
        floor_frequency = fmin;
    else
        floor_frequency = max(fmin, (1 - tolerance) * min(expected));
    end
end

function [wt1, wt2, frequency] = align_phase_wavelets( ...
    wt1, wt2, frequency1, frequency2)
% ALIGN_PHASE_WAVELETS Crop transforms to common frequency/time dimensions.

    nf = min([size(wt1, 1), size(wt2, 1), ...
        numel(frequency1), numel(frequency2)]);
    nt = min(size(wt1, 2), size(wt2, 2));
    if nf < 1 || nt < 1
        wt1 = [];
        wt2 = [];
        frequency = [];
        return;
    end
    wt1 = wt1(1:nf, 1:nt);
    wt2 = wt2(1:nf, 1:nt);
    frequency = frequency1(1:nf);
end

function [phase_rad, selected_frequency, valid, transform_support, floors, mode] = ...
    shared_frequency_phase(wt_lungs, wt_diaph, frequency, expected, ...
        explicit_edge_valid, tolerance, magnitude_fraction)
% SHARED_FREQUENCY_PHASE Select one same-belt frequency at every time point.
% Reviewed timing limits the candidate ridge to (1 +/- tolerance)*expected.
% If timing or a finite candidate bin is unavailable, the joint-magnitude
% maximum over the configured band is used and explicitly marked as fallback.

    nt = min([size(wt_lungs, 2), size(wt_diaph, 2), ...
        numel(expected), numel(explicit_edge_valid)]);
    wt_lungs = wt_lungs(:, 1:nt);
    wt_diaph = wt_diaph(:, 1:nt);
    expected = expected(1:nt);
    explicit_edge_valid = logical(explicit_edge_valid(1:nt));
    joint_magnitude = sqrt(abs(wt_lungs) .* abs(wt_diaph));
    row = nan(nt, 1);
    mode = repmat({'joint_wavelet_magnitude_fallback'}, nt, 1);
    for j = 1:nt
        guided_rows = [];
        if isfinite(expected(j)) && expected(j) > 0
            guided_rows = find(frequency >= (1 - tolerance) * expected(j) & ...
                frequency <= (1 + tolerance) * expected(j));
        end
        selected_row = maximum_finite_row(joint_magnitude(:, j), guided_rows);
        if ~isempty(selected_row)
            row(j) = selected_row;
            mode{j} = 'breath_timing_guided';
        else
            selected_row = maximum_finite_row( ...
                joint_magnitude(:, j), (1:numel(frequency))');
            if ~isempty(selected_row)
                row(j) = selected_row;
            end
        end
    end

    phase_rad = nan(nt, 1);
    selected_frequency = nan(nt, 1);
    selected_lungs = nan(nt, 1);
    selected_diaph = nan(nt, 1);
    has_row = isfinite(row);
    columns = find(has_row);
    if ~isempty(columns)
        linear = sub2ind(size(wt_lungs), row(has_row), columns);
        selected_lungs(has_row) = wt_lungs(linear);
        selected_diaph(has_row) = wt_diaph(linear);
        selected_frequency(has_row) = frequency(row(has_row));
        phase_rad(has_row) = angle( ...
            selected_lungs(has_row) .* conj(selected_diaph(has_row)));
    end

    lung_peak = max(abs(wt_lungs), [], 1, 'omitnan');
    diaph_peak = max(abs(wt_diaph), [], 1, 'omitnan');
    lung_scale = finite_median(lung_peak);
    diaph_scale = finite_median(diaph_peak);
    floors = struct( ...
        'lungs', max(eps, magnitude_fraction * lung_scale), ...
        'diaph', max(eps, magnitude_fraction * diaph_scale));
    transform_support = explicit_edge_valid & has_row & ...
        isfinite(selected_lungs) & isfinite(selected_diaph) & ...
        isfinite(selected_frequency) & selected_frequency > 0;
    valid = transform_support & ...
        abs(selected_lungs) >= floors.lungs & ...
        abs(selected_diaph) >= floors.diaph;
    phase_rad(~valid) = NaN;
    selected_frequency(~valid) = NaN;
end

function row = maximum_finite_row(values, candidate_rows)
% MAXIMUM_FINITE_ROW Return the candidate row with largest finite magnitude.

    row = [];
    if isempty(candidate_rows)
        return;
    end
    candidate_rows = candidate_rows(:);
    candidate_values = values(candidate_rows);
    finite = isfinite(candidate_values);
    if ~any(finite)
        return;
    end
    finite_rows = candidate_rows(finite);
    finite_values = candidate_values(finite);
    [~, index] = max(finite_values);
    row = finite_rows(index);
end

function [mean_deg, resultant, selected_grid, expected_grid, mode_grid, valid_grid] = ...
    summarize_phase_on_grid(phase_rad, selected_frequency, expected_frequency, ...
        selection_mode, coefficient_valid, transform_support, fs, t_grid, ...
        summary_cycles, min_valid_fraction)
% SUMMARIZE_PHASE_ON_GRID Compute centered circular means within one block.
% A summary may contain low-magnitude coefficients up to min_valid_fraction,
% but every sample must remain inside the transform-support/edge-valid region.

    mean_deg = nan(size(t_grid));
    resultant = nan(size(t_grid));
    selected_grid = nan(size(t_grid));
    expected_grid = nan(size(t_grid));
    mode_grid = repmat({'unavailable'}, size(t_grid));
    valid_grid = false(size(t_grid));
    n = numel(phase_rad);
    for g = 1:numel(t_grid)
        center = round(t_grid(g) * fs) + 1;
        if center < 1 || center > n || ~coefficient_valid(center)
            continue;
        end
        f_center = selected_frequency(center);
        half_window = ceil(0.5 * summary_cycles * fs / f_center);
        first = center - half_window;
        last = center + half_window;
        if first < 1 || last > n || ~all(transform_support(first:last))
            continue;
        end
        window_valid = coefficient_valid(first:last);
        if nnz(window_valid) / numel(window_valid) < min_valid_fraction
            continue;
        end
        values = phase_rad(first:last);
        values = values(window_valid);
        [mean_phase, r] = circular_phase_summary(values);
        if ~isfinite(mean_phase) || ~isfinite(r)
            continue;
        end
        valid_indices = first - 1 + find(window_valid);
        mean_deg(g) = rad2deg(mean_phase);
        resultant(g) = r;
        selected_grid(g) = finite_median(selected_frequency(valid_indices));
        expected_grid(g) = finite_median(expected_frequency(valid_indices));
        modes = selection_mode(valid_indices);
        if all(strcmp(modes, 'breath_timing_guided'))
            mode_grid{g} = 'breath_timing_guided';
        else
            mode_grid{g} = 'joint_wavelet_magnitude_fallback';
        end
        valid_grid(g) = isfinite(selected_grid(g));
    end
end

function qc = phase_recording_qc(metrics)
% PHASE_RECORDING_QC Build descriptive polarity/frequency cohort-QC scalars.
% Near-zero and near-180 bins reuse the 30-degree operational angle threshold;
% these summaries never change polarity, reliability, candidates, or events.

    qc = empty_phase_recording_qc();
    reliable = metrics.reliable_phase_mask & ...
        isfinite(metrics.signed_mean_phase_deg) & ...
        isfinite(metrics.resultant_length);
    qc.n_reliable_grid_points = nnz(reliable);
    if any(reliable)
        signed = metrics.signed_mean_phase_deg(reliable);
        absolute = abs(signed);
        qc.median_abs_phase_deg = median(absolute, 'omitnan');
        qc.median_signed_phase_deg = median(signed, 'omitnan');
        qc.median_resultant_length = median( ...
            metrics.resultant_length(reliable), 'omitnan');
        qc.fraction_reliable_near_0deg = ...
            mean(absolute <= metrics.angle_threshold_deg);
        qc.fraction_reliable_near_180deg = ...
            mean(absolute >= 180 - metrics.angle_threshold_deg);
    end
    frequency_qc = metrics.frequency_consistent_with_breath_timing;
    frequency_qc = frequency_qc(isfinite(frequency_qc));
    if ~isempty(frequency_qc)
        qc.fraction_frequency_consistent_with_breath_timing = ...
            mean(frequency_qc ~= 0);
    end
end

function qc = empty_phase_recording_qc()
% EMPTY_PHASE_RECORDING_QC Return stable descriptive recording-level fields.

    qc = struct( ...
        'n_reliable_grid_points', 0, ...
        'median_abs_phase_deg', NaN, ...
        'median_signed_phase_deg', NaN, ...
        'median_resultant_length', NaN, ...
        'fraction_reliable_near_0deg', NaN, ...
        'fraction_reliable_near_180deg', NaN, ...
        'fraction_frequency_consistent_with_breath_timing', NaN);
end

function value = finite_median(values)
% FINITE_MEDIAN Return the median finite value, or NaN when none exist.

    values = values(isfinite(values));
    if isempty(values)
        value = NaN;
    else
        value = median(values, 'omitnan');
    end
end

function message = append_error_message(message, addition)
% APPEND_ERROR_MESSAGE Retain compact per-recording block failure context.

    if isempty(message)
        message = addition;
    elseif ~contains(message, addition)
        message = [message ' | ' addition];
    end
end

function visibility = phase_figure_visibility(config)
% PHASE_FIGURE_VISIBILITY Resolve wavelet-library figure visibility.

    visibility = 'on';
    if isfield(config, 'make_figs_visible') && ~isempty(config.make_figs_visible)
        visibility = char(string(config.make_figs_visible));
    end
end

function restore_phase_figure_visibility(old, existing, target)
% RESTORE_PHASE_FIGURE_VISIBILITY Restore root state and close hidden figures.

    set(groot, 'defaultFigureVisible', old);
    if strcmpi(target, 'off')
        current = findall(groot, 'Type', 'figure');
        created = setdiff(current, existing);
        if ~isempty(created)
            close(created(ishandle(created)));
        end
    end
end
