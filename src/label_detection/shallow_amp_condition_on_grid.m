function cond = shallow_amp_condition_on_grid(b_l, b_d, t_grid, win_sec, ref_l, ref_d, r_lo, r_hi)
% At each grid time t, compute median breath amp in [t-win_sec, t] and compare to ref.
    cond = false(size(t_grid));
    tr_lo = 1 - r_hi;   % 0.65
    tr_hi = 1 - r_lo;   % 0.80

    for i = 1:numel(t_grid)
        t = t_grid(i);
        lb = t - win_sec;
        if lb < 0
            continue;  % not enough history for a full 60 s window yet
        end
        % lung_amplitudes_in_window (a_l) and
        % diaphragm_amplitudes_in_window  (a_d)
        % disp([num2str(i) '/' num2str(numel(t_grid))])
        a_l = b_l.amp(b_l.peak_t <= t & b_l.peak_t >= lb); 
        a_d = b_d.amp(b_d.peak_t <= t & b_d.peak_t >= lb);

        if numel(a_l) < 3 || numel(a_d) < 3
            continue;
        end

        med_l = median(a_l, 'omitnan');
        med_d = median(a_d, 'omitnan');

        rl = med_l / ref_l; % relative amplitude ratios (current_amplitude / baseline amplitude)
        rd = med_d / ref_d;

        cond(i) = (isfinite(rl) && rl >= tr_lo && rl <= tr_hi) || ...
                  (isfinite(rd) && rd >= tr_lo && rd <= tr_hi);   % OR (or use && if you truly require both)
    end
end
