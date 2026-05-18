function [cond, rr_bpm] = compute_breath_rate_mask(peak_t, t_grid, win_sec, rr_thr_bpm, comparison, fill_window)
% compute_breath_rate_mask
% Respiratory-rate condition on an evaluation grid.
%
% comparison:
%   '>=' rapid/tachypnea condition
%   '<=' slow/bradypnea condition
%
% If fill_window is true, every grid sample inside a qualifying window is
% marked true. If false, only the window endpoint is marked true.

    if nargin < 6 || isempty(fill_window)
        fill_window = false;
    end

    cond = false(size(t_grid));
    rr_bpm = nan(size(t_grid));
    peak_t = peak_t(:);
    peak_t = peak_t(isfinite(peak_t));

    for i = 1:numel(t_grid)
        t = t_grid(i);
        lb = t - win_sec;
        if lb < 0
            continue;
        end

        n_breaths = sum(peak_t >= lb & peak_t < t);
        if n_breaths < 2
            continue;
        end

        rr_mean = n_breaths / win_sec * 60;
        if ~isfinite(rr_mean)
            continue;
        end
        rr_bpm(i) = rr_mean;

        switch comparison
            case '>='
                is_match = rr_mean >= rr_thr_bpm;
            case '<='
                is_match = rr_mean <= rr_thr_bpm;
            otherwise
                error('Unsupported comparison: %s', comparison);
        end

        if is_match
            if fill_window
                cond(t_grid >= lb & t_grid < t) = true;
            else
                cond(i) = true;
            end
        end
    end
end
