function cond = compute_shallow_breathing_mask(breaths, t_grid, win_sec, ref, r_lo, r_hi)

cond = false(size(t_grid));

if ~breaths.ok
    return
end

if isscalar(ref)
    ref = ref * ones(size(t_grid));
end

for i = 1:numel(t_grid)
    t = t_grid(i);
    lb = t - win_sec;

    if lb < 0
        continue;
    end

    ref_i = ref(i);

    if ~isfinite(ref_i) || ref_i <= 0
        continue;
    end

    amplitudes_in_window = breaths.amp(breaths.peak_t <= t & breaths.peak_t >= lb);

    if numel(amplitudes_in_window) < 3
        continue;
    end

    lower_amp = ref_i * r_lo;
    upper_amp = ref_i * r_hi;

    is_shallow_window = all(isfinite(amplitudes_in_window) & ...
        amplitudes_in_window >= lower_amp & ...
        amplitudes_in_window <= upper_amp);

    if is_shallow_window
        cond(t_grid >= lb & t_grid <= t) = true;
    end
end

end
