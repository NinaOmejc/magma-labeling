function rea = compute_respiratory_asynchrony_metrics(data, breaths_lungs, breaths_diaph, config)
% compute_respiratory_asynchrony_metrics
% Wavelet phase-coherence diagnostics for Label 5.

    N = size(data, 1);
    t_grid = (0:config.grid_step_sec:(N-1)/config.fs)';

    rea = empty_rea_metrics(t_grid, config);

    idx_lungs = find(strcmp(config.data_columns, 'Resp-Lungs'), 1);
    idx_diaph = find(strcmp(config.data_columns, 'Resp-Diaphragm'), 1);
    if isempty(idx_lungs) || isempty(idx_diaph)
        rea.skip_code = 1;
        return;
    end

    lungs_broken = isfield(config,'problems') && isfield(config.problems,'subjects_with_broken_lung_belt') && ...
        any(config.subject == config.problems.subjects_with_broken_lung_belt);
    if lungs_broken
        rea.skip_code = 2;
        return;
    end

    if ~isempty(breaths_lungs) && ~is_valid_breath_signal(breaths_lungs, false)
        rea.skip_code = 3;
        return;
    end
    if ~isempty(breaths_diaph) && ~is_valid_breath_signal(breaths_diaph, false)
        rea.skip_code = 4;
        return;
    end

    [lungs_sig, lungs_ok] = prepare_resp_signal_local(data(:, idx_lungs));
    [diaph_sig, diaph_ok] = prepare_resp_signal_local(data(:, idx_diaph));
    if ~lungs_ok || ~diaph_ok
        rea.skip_code = 5;
        return;
    end

    try
        [lungs_pc, diaph_pc, fs_pc] = resample_pair_local(lungs_sig, diaph_sig, config.fs, rea.target_fs);
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
        avg_TPC = mean(TPC, 2, 'omitnan');
        % figure, plot(freq, avg_TPC)

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

    rea.baseline_mask = get_baseline_mask_local(t_grid, N, config);
    [rea.thresholds, rea.baselines] = phase_coherence_thresholds_local(rea, rea.baseline_mask);

    dev_high = isfinite(rea.phase_coherence_high) & isfinite(rea.thresholds.high) & ...
        rea.phase_coherence_high < rea.thresholds.high;
    dev_mid = isfinite(rea.phase_coherence_mid) & isfinite(rea.thresholds.mid) & ...
        rea.phase_coherence_mid < rea.thresholds.mid;
    dev_low = isfinite(rea.phase_coherence_low) & isfinite(rea.thresholds.low) & ...
        rea.phase_coherence_low < rea.thresholds.low;

    rea.deviation_bin_count = double(dev_high) + double(dev_mid) + double(dev_low);
    rea.low_coherence_mask = rea.deviation_bin_count >= rea.min_deviating_bins;
    rea.valid_analysis = true;
    rea.skip_code = 0;
end

function rea = empty_rea_metrics(t_grid, config)
    rea = struct();
    rea.time_sec = t_grid;
    rea.valid_analysis = false;
    rea.skip_code = 0;
    rea.error_message = '';

    rea.target_fs = get_config_value(config, 'ReA', 'target_fs', min(config.fs, 20));
    rea.fmin_hz = get_config_value(config, 'ReA', 'fmin', 0.052);
    rea.fmax_hz = get_config_value(config, 'ReA', 'fmax', 2.0);
    rea.f0 = get_config_value(config, 'ReA', 'f0', 1);
    rea.low_mid_cut_hz = get_config_value(config, 'ReA', 'low_mid_cut_hz', 0.145);
    rea.mid_high_cut_hz = get_config_value(config, 'ReA', 'mid_high_cut_hz', 0.6);
    rea.tlphcoh_cycles = get_config_value(config, 'ReA', 'tlphcoh_cycles', 10);
    rea.min_dur_sec = get_config_value(config, 'ReA', 'min_dur_sec', 30);
    rea.baseline_mad_k = get_config_value(config, 'ReA', 'baseline_mad_k', 3);
    rea.min_abs_drop = get_config_value(config, 'ReA', 'min_abs_drop', 0.15);
    rea.min_deviating_bins = get_config_value(config, 'ReA', 'min_deviating_bins', 1);
    rea.plot_step_sec = get_config_value(config, 'ReA', 'plot_step_sec', 15);

    rea.phase_coherence_high = nan(size(t_grid));
    rea.phase_coherence_mid = nan(size(t_grid));
    rea.phase_coherence_low = nan(size(t_grid));
    rea.baseline_mask = false(size(t_grid));
    rea.deviation_bin_count = nan(size(t_grid));
    rea.low_coherence_mask = false(size(t_grid));
    rea.baselines = struct('high', nan, 'mid', nan, 'low', nan);
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
    x = x - median(x, 'omitnan');

    sx = std(x, 'omitnan');
    ok = isfinite(sx) && sx > eps;
    if ok
        x = x ./ sx;
    end
end

function [x1, x2, fs_out] = resample_pair_local(x1, x2, fs_in, target_fs)
    fs_out = min(target_fs, fs_in);
    if ~isfinite(fs_out) || fs_out <= 0
        fs_out = fs_in;
    end

    if abs(fs_out - fs_in) > 10 * eps(fs_in)
        [p, q] = rat(fs_out / fs_in, 1e-12);
        x1 = resample(x1, p, q);
        x2 = resample(x2, p, q);
        fs_out = fs_in * p / q;
    end

    n = min(numel(x1), numel(x2));
    x1 = x1(1:n);
    x2 = x2(1:n);
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

function [thresholds, baselines] = phase_coherence_thresholds_local(rea, baseline_mask)
    names = {'high', 'mid', 'low'};
    thresholds = struct();
    baselines = struct();

    for i = 1:numel(names)
        name = names{i};
        values = rea.(['phase_coherence_' name])(baseline_mask);
        values = values(isfinite(values));

        if isempty(values)
            baselines.(name) = nan;
            thresholds.(name) = nan;
            continue;
        end

        center = median(values, 'omitnan');
        spread = 1.4826 * median(abs(values - center), 'omitnan');
        if ~isfinite(spread)
            spread = 0;
        end

        baselines.(name) = center;
        thresholds.(name) = max(0, center - max(rea.min_abs_drop, rea.baseline_mad_k * spread));
    end
end

function baseline_mask = get_baseline_mask_local(t_grid, N, config)
    [~, ~, baseline_start_t, baseline_end_t] = get_static_baseline_interval(N, config);
    baseline_mask = t_grid >= baseline_start_t & t_grid <= baseline_end_t;
end
