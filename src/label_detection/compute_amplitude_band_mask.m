function mask = compute_amplitude_band_mask(resp_feat, use_lungs, use_diaph, t_grid, win_sec, ref_lungs, ref_diaph, r_lo, r_hi)
% compute_amplitude_band_mask
% True where either valid belt has all breath amplitudes inside [r_lo, r_hi]
% times its reference amplitude in the analysis window.

    mask = false(size(t_grid));

    if use_lungs
        mask = mask | compute_shallow_breathing_mask( ...
            resp_feat.lungs, t_grid, win_sec, ref_lungs, r_lo, r_hi);
    end

    if use_diaph
        mask = mask | compute_shallow_breathing_mask( ...
            resp_feat.diaph, t_grid, win_sec, ref_diaph, r_lo, r_hi);
    end
end
