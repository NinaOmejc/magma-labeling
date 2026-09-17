function pathological = classify_guyot_modulation( ...
    h, fm_hz, evaluable, h_threshold, fm_band_hz)
% CLASSIFY_GUYOT_MODULATION Apply the published h and frequency criteria.
% A window is pathological only when h is strictly above its threshold and
% modulation frequency lies within the inclusive Guyot band.

    h = h(:);
    fm_hz = fm_hz(:);
    evaluable = logical(evaluable(:));
    if ~isequal(size(h), size(fm_hz), size(evaluable))
        error('MAGMA:Periodic:GuyotClassificationSizeMismatch', ...
            'h, fm_hz, and evaluable must have equal sizes.');
    end
    if ~isscalar(h_threshold) || ~isfinite(h_threshold) || h_threshold < 0
        error('MAGMA:Periodic:InvalidGuyotThreshold', ...
            'The Guyot h threshold must be a nonnegative finite scalar.');
    end
    if ~isnumeric(fm_band_hz) || numel(fm_band_hz) ~= 2 || ...
            any(~isfinite(fm_band_hz)) || fm_band_hz(1) <= 0 || ...
            fm_band_hz(2) <= fm_band_hz(1)
        error('MAGMA:Periodic:InvalidGuyotFrequencyBand', ...
            'The Guyot modulation-frequency band must contain two increasing positive values.');
    end

    pathological = evaluable & isfinite(h) & isfinite(fm_hz) & ...
        h > h_threshold & fm_hz >= fm_band_hz(1) & ...
        fm_hz <= fm_band_hz(2);
end
