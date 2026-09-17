function b = recompute_respiration_breath_fields(b, x, peak_idx, config)
% RECOMPUTE_RESPIRATION_BREATH_FIELDS Rebuild aligned breath fields after peak edits.
% b is the belt struct to update, x is the sample-level belt signal, and
% peak_idx contains proposed one-based sample indices. Invalid/duplicate
% indices are removed. The function writes peak/trough indices and times,
% three peak-to-trough amplitude definitions, the configured selected amp,
% IBI in seconds, RR in breaths/min, summary RR, and ok. For peak i,
% amp_exp uses the following trough, amp_insp the preceding trough, and
% amp_sym the mean of both. Undefined boundary amplitudes remain NaN.

    x = x(:);
    fs = config.fs;
    amp_method = resolve_respiration_amplitude_method(config);

    peak_idx = peak_idx(:);
    peak_idx = peak_idx(isfinite(peak_idx));
    peak_idx = unique(round(peak_idx), 'stable');
    peak_idx = peak_idx(peak_idx >= 1 & peak_idx <= numel(x));
    peak_idx = sort(peak_idx);

    b.x0 = x;
    b.peak_idx = peak_idx;
    b.peak_t = (peak_idx - 1) / fs;
    b.peak_val = x(peak_idx);

    b.trough_idx = [];
    b.trough_t = [];
    b.trough_val = [];
    b.amp = nan(numel(peak_idx), 1);
    b.amp_exp = nan(numel(peak_idx), 1);
    b.amp_insp = nan(numel(peak_idx), 1);
    b.amp_sym = nan(numel(peak_idx), 1);
    b.ibi = [];
    b.rr_bpm = [];
    b.rr_mean_bpm = NaN;
    b.rr_std_bpm = NaN;
    b.ok = false;

    if numel(peak_idx) < 2
        return;
    end

    n = numel(peak_idx);
    trough_idx = zeros(n - 1, 1);
    trough_val = zeros(n - 1, 1);

    for i = 1:n-1
        idx_range = peak_idx(i):peak_idx(i+1);
        seg = x(idx_range);

        switch lower(config.resp.trough_method)
            case 'min'
                [tr, j] = min(seg);

            case 'prctile'
                tr_p = prctile(seg, config.resp.trough_prct);
                [~, j] = min(abs(seg - tr_p));
                tr = seg(j);

            otherwise
                error('Unknown config.resp.trough_method: %s', config.resp.trough_method);
        end

        trough_idx(i) = idx_range(j);
        trough_val(i) = tr;
    end

    b.trough_idx = trough_idx;
    b.trough_t = (trough_idx - 1) / fs;
    b.trough_val = trough_val;
    b.amp_exp(1:n-1) = b.peak_val(1:n-1) - trough_val;
    b.amp_insp(2:n) = b.peak_val(2:n) - trough_val;
    if n > 2
        adjacent_trough_mean = (trough_val(1:n-2) + trough_val(2:n-1)) / 2;
        b.amp_sym(2:n-1) = b.peak_val(2:n-1) - adjacent_trough_mean;
    end
    b.amp = b.(amplitude_field(amp_method));

    b.ibi = diff(peak_idx) / fs;
    b.rr_bpm = 60 ./ b.ibi;
    b.rr_mean_bpm = 60 / mean(b.ibi, 'omitnan');
    b.rr_std_bpm = std(b.rr_bpm, 'omitnan');
    b.ok = n >= 3;
end

function field = amplitude_field(method)
% AMPLITUDE_FIELD Map a validated configuration value to its breath field.

    switch method
        case 'expiratory'
            field = 'amp_exp';
        case 'inspiratory'
            field = 'amp_insp';
        case 'symmetric'
            field = 'amp_sym';
    end
end
