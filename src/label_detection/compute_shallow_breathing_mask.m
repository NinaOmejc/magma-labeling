function cond = compute_shallow_breathing_mask(breaths, t_grid, win_sec, ...
                                              ref, r_lo, r_hi)
% At each grid time t, compute breath amps in [t-win_sec, t] and compare to
% ref and threshold. If all breath amps are below the threshold, consider
% this shallow breathing period.
    
    cond = false(size(t_grid));

    if ~breaths.ok 
        return
    end

    tr_lo = 1 - r_hi; 
    tr_hi = 1 - r_lo; 

    for i = 1:numel(t_grid)
        t = t_grid(i);
        lb = t - win_sec;
        if lb < 0
            continue;  % not enough history for a full 60 s window yet
        end

        amplitudes_in_window = breaths.amp(breaths.peak_t <= t & breaths.peak_t >= lb); 

        if numel(amplitudes_in_window) < 3
            continue;
        end

        % med = median(amplitudes_in_window, 'omitnan');
        % r = amplitudes_in_window ./ ref; % relative amplitude ratios (window amplitudes / baseline amplitude)
        % cond(i) = all(isfinite(r) & r >= tr_lo & r <= tr_hi);
        thr_1 = ref*r_hi;
        thr_2 = ref*r_lo;
        is_shallow_window = all(isfinite(amplitudes_in_window) & ...
                                amplitudes_in_window < thr_1 & ...
                                amplitudes_in_window > thr_2);

        if is_shallow_window
            cond(t_grid >= lb & t_grid <= t) = true;
        end
    end
end
