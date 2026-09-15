function result = reconstruct_guyot_envelope( ...
    breath_t, canonical_breath_amp, recording_end_t, resample_hz, gap_factor)
% RECONSTRUCT_GUYOT_ENVELOPE Interpolate reviewed canonical breath amplitudes.
% Ordinary breath intervals are linear. When an interval exceeds gap_factor
% times the median positive IBI, interior samples are set to zero as in Guyot
% et al. 2020. Times outside the first/final valid breath remain unevaluable.

    result = struct( ...
        'available', false, ...
        'breath_t', [], ...
        'canonical_breath_amp', [], ...
        'median_ibi_sec', NaN, ...
        'long_gap_mask', [], ...
        'envelope_t', [], ...
        'envelope', [], ...
        'evaluable_mask', []);
    if ~isnumeric(breath_t) || ~isnumeric(canonical_breath_amp) || ...
            ~isscalar(recording_end_t) || ~isfinite(recording_end_t) || ...
            recording_end_t < 0 || ~isscalar(resample_hz) || ...
            ~isfinite(resample_hz) || resample_hz <= 0 || ...
            ~isscalar(gap_factor) || ~isfinite(gap_factor) || gap_factor <= 1
        return;
    end

    breath_t = breath_t(:);
    canonical_breath_amp = canonical_breath_amp(:);
    n = min(numel(breath_t), numel(canonical_breath_amp));
    breath_t = breath_t(1:n);
    canonical_breath_amp = canonical_breath_amp(1:n);
    valid = isfinite(breath_t) & isfinite(canonical_breath_amp) & ...
        canonical_breath_amp > 0 & breath_t >= 0 & ...
        breath_t <= recording_end_t;
    breath_t = breath_t(valid);
    canonical_breath_amp = canonical_breath_amp(valid);
    [breath_t, order] = sort(breath_t, 'ascend');
    canonical_breath_amp = canonical_breath_amp(order);
    [breath_t, canonical_breath_amp] = collapse_duplicate_times( ...
        breath_t, canonical_breath_amp);

    result.breath_t = breath_t;
    result.canonical_breath_amp = canonical_breath_amp;
    result.envelope_t = (0:1 / resample_hz:recording_end_t)';
    result.envelope = nan(size(result.envelope_t));
    result.evaluable_mask = false(size(result.envelope_t));
    result.long_gap_mask = false(size(result.envelope_t));
    if numel(breath_t) < 2
        return;
    end

    ibi = diff(breath_t);
    positive_ibi = ibi(isfinite(ibi) & ibi > 0);
    if isempty(positive_ibi)
        return;
    end
    result.median_ibi_sec = median(positive_ibi, 'omitnan');
    if ~isfinite(result.median_ibi_sec) || result.median_ibi_sec <= 0
        return;
    end

    support = result.envelope_t >= breath_t(1) & ...
        result.envelope_t <= breath_t(end);
    result.envelope(support) = interp1( ...
        breath_t, canonical_breath_amp, result.envelope_t(support), 'linear');
    result.evaluable_mask(support) = isfinite(result.envelope(support));

    long_gap = ibi > gap_factor * result.median_ibi_sec;
    for i = find(long_gap(:))'
        inside_gap = result.envelope_t > breath_t(i) & ...
            result.envelope_t < breath_t(i + 1);
        result.envelope(inside_gap) = 0;
        result.evaluable_mask(inside_gap) = true;
        result.long_gap_mask(inside_gap) = true;
    end
    result.available = any(result.evaluable_mask);
end

function [unique_t, unique_amp] = collapse_duplicate_times(t, amp)
% COLLAPSE_DUPLICATE_TIMES Median-combine amplitudes at identical breath times.

    if isempty(t)
        unique_t = t;
        unique_amp = amp;
        return;
    end
    [unique_t, ~, group] = unique(t, 'sorted');
    unique_amp = accumarray(group, amp, [], @median);
end
