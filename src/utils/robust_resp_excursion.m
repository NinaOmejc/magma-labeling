function excursion = robust_resp_excursion(x)
% ROBUST_RESP_EXCURSION Measure raw belt excursion as the finite P95-P5 range.
% x is a vector of raw respiratory-belt samples. At least three finite
% samples are required; otherwise excursion is NaN in the belt's raw units.

    x = x(isfinite(x));
    if numel(x) < 3
        excursion = NaN;
        return;
    end

    excursion = prctile(x, 95) - prctile(x, 5);
end
