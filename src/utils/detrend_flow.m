% Subtract the moving trend and global mean offset from a time series.
% Uses centered moving mean with shrinking endpoints to avoid edge artifacts.

function [output, trend, trend1] = detrend_flow(t_series, sampl_freq, window_l)

input_was_row = isrow(t_series);
x = t_series(:);

window_s = round(window_l * sampl_freq);
if mod(window_s, 2) == 0
    window_s = window_s + 1;
end
window_s = max(3, min(window_s, numel(x)));

% Endpoint-aware trend estimate (no flat replication at the right edge).
trend1 = movmean(x, window_s, 'Endpoints', 'shrink');

residual = x - trend1;
trend = trend1 + mean(residual, 'omitnan');
output = x - trend;

if input_was_row
    output = output';
    trend = trend';
    trend1 = trend1';
end
