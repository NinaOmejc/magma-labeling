function rea = compute_respiratory_asynchrony_metrics(data, resp_feat, session_reference, config)
% compute_respiratory_asynchrony_metrics
% Wavelet phase-coherence diagnostics for Label 10. Master inputs and output
% timing stay at config.fs; only the internal wavelet signals use analysis_fs.
% Coherence reference statistics use the common session-reference interval.

    N = size(data, 1);
    t_grid = (0:config.grid_step_sec:(N-1)/config.fs)';

    rea = empty_rea_metrics(t_grid, session_reference, config);
    rea.master_n_samples = N;

    if ~isfield(config, 'channels')
        config = resolve_signal_channels(config);
    end
    idx_lungs = config.channels.lungs_idx;
    idx_diaph = config.channels.diaph_idx;
    if isempty(idx_lungs) || isempty(idx_diaph)
        rea.skip_code = 1;
        return;
    end

    lungs_broken = is_lung_belt_ignored(config);
    if lungs_broken
        rea.skip_code = 2;
        return;
    end

    if ~isempty(resp_feat) && ~is_valid_breath_signal(resp_feat.lungs, false)
        rea.skip_code = 3;
        return;
    end
    if ~isempty(resp_feat) && ~is_valid_breath_signal(resp_feat.diaph, false)
        rea.skip_code = 4;
        return;
    end

    [lungs_sig, lungs_ok] = prepare_resp_signal_local(data(:, idx_lungs));
    [diaph_sig, diaph_ok] = prepare_resp_signal_local(data(:, idx_diaph));
    if ~lungs_ok || ~diaph_ok
        rea.skip_code = 5;
        return;
    end

    rea.reference_mask = get_reference_mask_local(t_grid, session_reference);
    if ~isstruct(session_reference) || ~isfield(session_reference, 'available') || ...
            ~session_reference.available || ~any(rea.reference_mask)
        rea.reference_quality = 'reference_interval_unavailable';
        rea.skip_code = 9;
        return;
    end

    old_default_visibility = get(groot, 'defaultFigureVisible');
    figures_before = findall(groot, 'Type', 'figure');
    target_visibility = target_figure_visibility(config);
    cleanup_visibility = onCleanup(@() restore_figure_visibility(old_default_visibility, figures_before, target_visibility));
    set(groot, 'defaultFigureVisible', target_visibility);

    try
        [lungs_pc, diaph_pc, fs_pc] = resample_respiration_for_analysis( ...
            lungs_sig, diaph_sig, config.fs, rea.analysis_fs);
        rea.analysis_fs = fs_pc;
        rea.analysis_n_samples = numel(lungs_pc);
        rea.analysis_duration_sec = max(0, rea.analysis_n_samples - 1) / fs_pc;
        fmax = min(rea.fmax_hz, 0.95 * fs_pc / 2);
        if rea.fmin_hz >= fmax
            rea.skip_code = 6;
            return;
        end

        [WT_lungs, freq] = wtI(lungs_pc, fs_pc, ...
            'fmin', rea.fmin_hz, 'fmax', fmax, 'f0', rea.f0, ...
            'Plot', 'off', 'Display', 'off', 'CutEdges', 'on', 'Padding', 'none');
        [WT_diaph, freq_diaph] = wtI(diaph_pc, fs_pc, ...
            'fmin', rea.fmin_hz, 'fmax', fmax, 'f0', rea.f0, ...
            'Plot', 'off', 'Display', 'off', 'CutEdges', 'on', 'Padding', 'none');

        [WT_lungs, WT_diaph, freq] = align_wavelet_outputs_local(WT_lungs, WT_diaph, freq, freq_diaph);
        if isempty(freq) || isempty(WT_lungs) || isempty(WT_diaph)
            rea.skip_code = 7;
            return;
        end

        TPC = tlphcoh(WT_lungs, WT_diaph, freq, fs_pc, rea.tlphcoh_cycles);
    catch ME
        rea.skip_code = 8;
        rea.error_message = ME.message;
        warning('MAGMA:RespiratoryAsynchrony:Skipped', ...
            'Respiratory asynchrony metrics skipped: %s', ME.message);
        return;
    end

    t_pc = (0:size(TPC, 2)-1)' / fs_pc;
    coh_high = mean_phase_coherence_in_band_local(TPC, freq > rea.mid_high_cut_hz);
    coh_mid = mean_phase_coherence_in_band_local(TPC, freq >= rea.low_mid_cut_hz & freq <= rea.mid_high_cut_hz);
    coh_low = mean_phase_coherence_in_band_local(TPC, freq < rea.low_mid_cut_hz);

    rea.phase_coherence_high = interp1(t_pc, coh_high, t_grid, 'linear', nan);
    rea.phase_coherence_mid = interp1(t_pc, coh_mid, t_grid, 'linear', nan);
    rea.phase_coherence_low = interp1(t_pc, coh_low, t_grid, 'linear', nan);

    [rea.thresholds, rea.references, rea.reference_valid_counts] = ...
        phase_coherence_thresholds_local(rea, rea.reference_mask);
    rea.reference_available = any(structfun(@(x) x > 0, rea.reference_valid_counts));
    if ~rea.reference_available
        if ~isstruct(session_reference) || ~isfield(session_reference, 'available') || ...
                ~session_reference.available
            rea.reference_quality = 'reference_interval_unavailable';
        else
            rea.reference_quality = 'insufficient_valid_coherence';
        end
        rea.skip_code = 9;
        return;
    elseif session_reference.complete
        rea.reference_quality = 'good';
    else
        rea.reference_quality = 'warning_truncated_interval';
    end

    valid_high = isfinite(rea.phase_coherence_high) & isfinite(rea.thresholds.high);
    valid_mid = isfinite(rea.phase_coherence_mid) & isfinite(rea.thresholds.mid);
    valid_low = isfinite(rea.phase_coherence_low) & isfinite(rea.thresholds.low);
    rea.valid_evidence_mask = valid_high | valid_mid | valid_low;
    if ~any(rea.valid_evidence_mask)
        rea.skip_code = 9;
        return;
    end

    dev_high = valid_high & ...
        rea.phase_coherence_high < rea.thresholds.high;
    dev_mid = valid_mid & ...
        rea.phase_coherence_mid < rea.thresholds.mid;
    dev_low = valid_low & ...
        rea.phase_coherence_low < rea.thresholds.low;

    rea.deviation_bin_count = double(dev_high) + double(dev_mid) + double(dev_low);
    rea.low_coherence_mask = rea.deviation_bin_count >= rea.min_deviating_bins;
    rea.valid_analysis = true;
    rea.skip_code = 0;
end

function visibility = target_figure_visibility(config)
    visibility = 'on';
    if isfield(config, 'make_figs_visible') && ~isempty(config.make_figs_visible)
        visibility = char(string(config.make_figs_visible));
    end
end

function restore_figure_visibility(old_visibility, existing_figures, target_visibility)
    set(groot, 'defaultFigureVisible', old_visibility);
    if strcmpi(target_visibility, 'off')
        current_figures = findall(groot, 'Type', 'figure');
        new_figures = setdiff(current_figures, existing_figures);
        if ~isempty(new_figures)
            close(new_figures(ishandle(new_figures)));
        end
    end
end

function rea = empty_rea_metrics(t_grid, session_reference, config)
    rea = struct();
    rea.time_sec = t_grid;
    rea.valid_analysis = false;
    rea.skip_code = 0;
    rea.error_message = '';

    rea.analysis_fs = get_config_value(config, 'ReA', 'analysis_fs', min(config.fs, 20));
    rea.analysis_n_samples = 0;
    rea.analysis_duration_sec = 0;
    rea.master_fs = config.fs;
    rea.fmin_hz = get_config_value(config, 'ReA', 'fmin', 0.052);
    rea.fmax_hz = get_config_value(config, 'ReA', 'fmax', 2.0);
    rea.f0 = get_config_value(config, 'ReA', 'f0', 1);
    rea.low_mid_cut_hz = get_config_value(config, 'ReA', 'low_mid_cut_hz', 0.145);
    rea.mid_high_cut_hz = get_config_value(config, 'ReA', 'mid_high_cut_hz', 0.6);
    rea.tlphcoh_cycles = get_config_value(config, 'ReA', 'tlphcoh_cycles', 10);
    rea.min_dur_sec = get_config_value(config, 'ReA', 'min_dur_sec', 30);
    rea.reference_mad_k = get_config_value(config, 'ReA', 'reference_mad_k', 3);
    rea.min_abs_drop = get_config_value(config, 'ReA', 'min_abs_drop', 0.15);
    rea.min_deviating_bins = get_config_value(config, 'ReA', 'min_deviating_bins', 1);
    rea.plot_step_sec = get_config_value(config, 'ReA', 'plot_step_sec', 15);

    rea.phase_coherence_high = nan(size(t_grid));
    rea.phase_coherence_mid = nan(size(t_grid));
    rea.phase_coherence_low = nan(size(t_grid));
    rea.reference_mask = false(size(t_grid));
    rea.reference_available = false;
    rea.reference_quality = 'not_evaluated';
    if ~isstruct(session_reference) || ~isfield(session_reference, 'available') || ...
            ~session_reference.available
        rea.reference_quality = 'reference_interval_unavailable';
    end
    rea.deviation_bin_count = nan(size(t_grid));
    rea.low_coherence_mask = false(size(t_grid));
    rea.valid_evidence_mask = false(size(t_grid));
    rea.references = struct('high', nan, 'mid', nan, 'low', nan);
    rea.reference_valid_counts = struct('high', 0, 'mid', 0, 'low', 0);
    rea.thresholds = struct('high', nan, 'mid', nan, 'low', nan);
end

function [x, ok] = prepare_resp_signal_local(x)
    x = x(:);
    finite = isfinite(x);
    ok = nnz(finite) >= 2;
    if ~ok
        return;
    end

    sample_idx = (1:numel(x))';
    x(~finite) = interp1(sample_idx(finite), x(finite), sample_idx(~finite), 'linear', 'extrap');
    x_median = median(x, 'omitnan');
    x = x - x_median;

    sx = 1.4826 * median(abs(x), 'omitnan');
    if ~isfinite(sx) || sx <= eps
        sx = std(x, 'omitnan');
    end
    ok = isfinite(sx) && sx > eps;
    if ok
        x = x ./ sx;
    end
end

function [WT1, WT2, freq] = align_wavelet_outputs_local(WT1, WT2, freq1, freq2)
    nf = min([size(WT1, 1), size(WT2, 1), numel(freq1), numel(freq2)]);
    nt = min(size(WT1, 2), size(WT2, 2));
    if nf <= 0 || nt <= 0
        WT1 = [];
        WT2 = [];
        freq = [];
        return;
    end

    WT1 = WT1(1:nf, 1:nt);
    WT2 = WT2(1:nf, 1:nt);
    freq = freq1(1:nf);
end

function trace = mean_phase_coherence_in_band_local(TPC, band_mask)
    trace = nan(size(TPC, 2), 1);
    if ~any(band_mask)
        return;
    end

    trace = mean(TPC(band_mask, :), 1, 'omitnan')';
end

function [thresholds, references, valid_counts] = ...
    phase_coherence_thresholds_local(rea, reference_mask)
    names = {'high', 'mid', 'low'};
    thresholds = struct();
    references = struct();
    valid_counts = struct();

    for i = 1:numel(names)
        name = names{i};
        values = rea.(['phase_coherence_' name])(reference_mask);
        values = values(isfinite(values));
        valid_counts.(name) = numel(values);

        if isempty(values)
            references.(name) = nan;
            thresholds.(name) = nan;
            continue;
        end

        center = median(values, 'omitnan');
        spread = 1.4826 * median(abs(values - center), 'omitnan');
        if ~isfinite(spread)
            spread = 0;
        end

        references.(name) = center;
        thresholds.(name) = max(0, center - max(rea.min_abs_drop, rea.reference_mad_k * spread));
    end
end

function reference_mask = get_reference_mask_local(t_grid, session_reference)
    reference_mask = false(size(t_grid));
    if ~isstruct(session_reference) || ~isfield(session_reference, 'available') || ...
            ~session_reference.available
        return;
    end
    reference_mask = t_grid >= session_reference.reference_start_t & ...
        t_grid < session_reference.reference_end_t;
end
