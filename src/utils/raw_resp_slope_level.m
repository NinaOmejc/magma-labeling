function slope = raw_resp_slope_level(x)
% RAW_RESP_SLOPE_LEVEL Measure typical raw belt movement between samples.
% x is a vector of raw respiratory-belt samples. The result is the median
% absolute first difference in raw belt units per sample; at least three
% finite samples are required.

    x = x(:);
    x = x(isfinite(x));
    if numel(x) < 3
        slope = NaN;
        return;
    end

    slope = median(abs(diff(x)), 'omitnan');
end
