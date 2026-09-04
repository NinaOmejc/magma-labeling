function [state_mask, cov_trace, robust_cov_trace, endpoint_mask] = ...
    compute_irregularity_metrics(breaths, t_grid, win_sec, cov_thr)
% COMPUTE_IRREGULARITY_METRICS Compute trailing-window IBI variability.
%
% CoV is the sole detection metric. Robust CoV is retained as a
% descriptive trace and does not affect endpoint or state classification.

    state_mask = false(size(t_grid));
    cov_trace = nan(size(t_grid));
    robust_cov_trace = nan(size(t_grid));
    endpoint_mask = false(size(t_grid));

    if isempty(breaths) || ~isstruct(breaths) || ~isfield(breaths, 'peak_t') || ...
            ~isfield(breaths, 'ibi') || ~isfield(breaths, 'ok') || ~breaths.ok
        return;
    end

    peak_t = breaths.peak_t(:);
    ibi = breaths.ibi(:);
    ibi_start_t = peak_t(1:end-1);
    ibi_end_t = peak_t(2:end);

    if numel(ibi) ~= numel(ibi_start_t)
        error('breaths.ibi must have length numel(breaths.peak_t)-1.');
    end

    valid = isfinite(ibi) & ibi > 0 & ...
        isfinite(ibi_start_t) & isfinite(ibi_end_t);
    ibi = ibi(valid);
    ibi_start_t = ibi_start_t(valid);
    ibi_end_t = ibi_end_t(valid);

    if numel(ibi) < 5
        return;
    end

    for i = 1:numel(t_grid)
        t = t_grid(i);
        lb = t - win_sec;

        if lb < 0
            continue;
        end

        in_window = ibi_start_t >= lb & ibi_end_t <= t;
        ibi_win = ibi(in_window);
        if numel(ibi_win) < 5
            continue;
        end

        mu = mean(ibi_win);
        sd = std(ibi_win);
        if ~isfinite(mu) || mu <= 0 || ~isfinite(sd)
            continue;
        end

        cov_trace(i) = sd / mu;

        med_ibi = median(ibi_win);
        if isfinite(med_ibi) && med_ibi > 0
            mad_ibi = median(abs(ibi_win - med_ibi));
            if isfinite(mad_ibi)
                robust_cov_trace(i) = 1.4826 * mad_ibi / med_ibi;
            end
        end

        endpoint_mask(i) = cov_trace(i) >= cov_thr;
    end

    state_mask = analysis_window_endpoints_to_state_mask( ...
        endpoint_mask, t_grid, win_sec);
end
