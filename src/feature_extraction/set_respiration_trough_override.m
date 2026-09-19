function b = set_respiration_trough_override( ...
    b, left_peak_idx, right_peak_idx, trough_idx, config)
% SET_RESPIRATION_TROUGH_OVERRIDE Move one trough within an anchored peak pair.
% The three sample indices are one-based. The peak samples must identify a
% currently consecutive pair, and the trough sample must be finite and lie
% strictly between them. Existing overrides for other peak pairs are retained.

    validate_belt(b);
    left_peak_idx = validate_sample_index(left_peak_idx, 'left peak');
    right_peak_idx = validate_sample_index(right_peak_idx, 'right peak');
    trough_idx = validate_sample_index(trough_idx, 'trough');

    pair_idx = find(b.peak_idx(1:end-1) == left_peak_idx & ...
        b.peak_idx(2:end) == right_peak_idx, 1);
    if isempty(pair_idx)
        error('MAGMA:Respiration:TroughPeakPairChanged', ...
            'The selected surrounding peaks are no longer consecutive.');
    end
    if trough_idx <= left_peak_idx || trough_idx >= right_peak_idx
        error('MAGMA:Respiration:TroughOutsidePeakPair', ...
            'The trough must be placed strictly between its surrounding peaks.');
    end
    if trough_idx > numel(b.x0) || ~isfinite(b.x0(trough_idx))
        error('MAGMA:Respiration:InvalidTroughSample', ...
            'The trough must be placed on a finite-valued signal sample.');
    end

    overrides = valid_override_rows(b);
    same_pair = overrides(:, 1) == left_peak_idx & ...
        overrides(:, 2) == right_peak_idx;
    overrides(same_pair, :) = [];
    b.trough_overrides = [overrides; ...
        left_peak_idx, right_peak_idx, trough_idx];
    b = recompute_respiration_breath_fields( ...
        b, b.x0, b.peak_idx, config);
end

function validate_belt(b)
% VALIDATE_BELT Require the fields needed for an anchored trough edit.

    if ~isstruct(b) || ~isfield(b, 'x0') || ~isfield(b, 'peak_idx') || ...
            numel(b.peak_idx) < 2
        error('MAGMA:Respiration:InvalidTroughEditState', ...
            'Trough editing requires a signal and at least two breath peaks.');
    end
end

function idx = validate_sample_index(idx, description)
% VALIDATE_SAMPLE_INDEX Require a finite integer scalar sample index.

    if ~isnumeric(idx) || ~isscalar(idx) || ~isfinite(idx) || ...
            idx ~= round(idx) || idx < 1
        error('MAGMA:Respiration:InvalidTroughSample', ...
            'The %s sample index must be a finite positive integer.', description);
    end
    idx = double(idx);
end

function overrides = valid_override_rows(b)
% VALID_OVERRIDE_ROWS Read compatible optional override metadata.

    overrides = zeros(0, 3);
    if ~isfield(b, 'trough_overrides') || ...
            ~isnumeric(b.trough_overrides) || isempty(b.trough_overrides) || ...
            size(b.trough_overrides, 2) ~= 3
        return;
    end
    candidate = double(b.trough_overrides);
    keep = all(isfinite(candidate), 2) & ...
        all(candidate == round(candidate), 2) & all(candidate >= 1, 2);
    overrides = candidate(keep, :);
end
