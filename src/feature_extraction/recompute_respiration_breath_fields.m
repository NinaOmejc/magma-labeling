function b = recompute_respiration_breath_fields(b, x, peak_idx, config)
% Recompute peak, trough, amplitude, IBI, and RR fields after peak edits.

    x = x(:);
    fs = config.new_fs;

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
    b.ibi = [];
    b.rr_bpm = [];
    b.rr_mean_bpm = NaN;
    b.rr_std_bpm = NaN;
    b.ok = false;

    if numel(peak_idx) < 3
        return;
    end

    n = numel(peak_idx);
    trough_idx = zeros(n - 1, 1);
    trough_val = zeros(n - 1, 1);
    amp = zeros(n - 1, 1);

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
        amp(i) = b.peak_val(i) - tr;
    end

    b.trough_idx = trough_idx;
    b.trough_t = (trough_idx - 1) / fs;
    b.trough_val = trough_val;
    b.amp = [amp(:); NaN];

    b.ibi = diff(peak_idx) / fs;
    b.rr_bpm = 60 ./ b.ibi;
    b.rr_mean_bpm = 60 / mean(b.ibi, 'omitnan');
    b.rr_std_bpm = std(b.rr_bpm, 'omitnan');
    b.ok = true;
end
