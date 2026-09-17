function [mean_phase_rad, resultant_length, n_valid] = circular_phase_summary(phase_rad)
% CIRCULAR_PHASE_SUMMARY Summarize finite angles without linear averaging.
% phase_rad contains signed angles in radians. The returned mean is the angle
% of the mean unit phasor, resultant_length is its magnitude, and n_valid is
% the number of finite angles used. Empty input remains undefined.

    phase_rad = phase_rad(:);
    phase_rad = phase_rad(isfinite(phase_rad));
    n_valid = numel(phase_rad);
    mean_phase_rad = NaN;
    resultant_length = NaN;
    if n_valid == 0
        return;
    end

    z = mean(exp(1i * phase_rad));
    mean_phase_rad = angle(z);
    resultant_length = abs(z);
end
