function [irregular_condition, cov_trace, rmssd_trace] = compute_irregularity_metrics( ...
    breaths, t_grid, win_sec, cov_thr, rmssd_thr, pause_thr_sec)
% compute_irregularity_metrics (irregularity in time)
% Return an analysis-window irregularity mask and endpoint IBI variability
% traces on t_grid. When a rolling window meets the irregularity criterion,
% the full window is marked as irregular because that whole interval
% contributed to the decision.

    irregular_condition = false(size(t_grid));
    cov_trace = nan(size(t_grid));
    rmssd_trace = nan(size(t_grid));

    if isempty(breaths) || ~isstruct(breaths) || ~isfield(breaths, 'peak_t') || ...
            ~isfield(breaths, 'ibi') || ~isfield(breaths, 'ok') || ~breaths.ok
        return;
    end

    peak_t = breaths.peak_t(:);
    ibi = breaths.ibi(:);
    ibi_t = peak_t(2:end);

    if numel(ibi) ~= numel(ibi_t)
        error('breaths.ibi must have length numel(breaths.peak_t)-1.');
    end

    valid = isfinite(ibi) & ibi > 0 & isfinite(ibi_t);
    ibi = ibi(valid);
    ibi_t = ibi_t(valid);

    if numel(ibi) < 5
        return;
    end

    use_rmssd = isfinite(rmssd_thr) && rmssd_thr > 0;

    for i = 1:numel(t_grid)
        t = t_grid(i);
        lb = t - win_sec;

        if lb < 0
            continue;
        end

        ibi_win = ibi(ibi_t >= lb & ibi_t <= t);

        if numel(ibi_win) < 5
            continue;
        end

        has_pause = isfinite(pause_thr_sec) && pause_thr_sec > 0 && ...
            any(ibi_win >= pause_thr_sec);

        mu = mean(ibi_win, 'omitnan');
        sd = std(ibi_win, 0, 'omitnan');

        if ~isfinite(mu) || mu <= 0 || ~isfinite(sd)
            continue;
        end

        cov_trace(i) = sd / mu;
        is_irregular_window = ~has_pause && cov_trace(i) >= cov_thr;

        if use_rmssd
            dibi = diff(ibi_win);
            if ~isempty(dibi)
                rmssd_trace(i) = sqrt(mean(dibi.^2, 'omitnan'));
                rmssd_is_irregular = isfinite(rmssd_trace(i)) && rmssd_trace(i) >= rmssd_thr;
                is_irregular_window = is_irregular_window || (~has_pause && rmssd_is_irregular);
            end
        end

        if is_irregular_window
            irregular_condition(t_grid >= lb & t_grid <= t) = true;
        end
    end
end
