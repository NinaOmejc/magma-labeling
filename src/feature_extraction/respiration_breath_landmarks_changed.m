function tf = respiration_breath_landmarks_changed(before, after)
% RESPIRATION_BREATH_LANDMARKS_CHANGED Compare reviewed peak/trough state.
% Optional trough override metadata is included so adding or resetting an
% override counts as a manual edit even when its signal height is unchanged.

    tf = ~isequal(before.peak_idx(:), after.peak_idx(:)) || ...
        ~isequal(before.trough_idx(:), after.trough_idx(:)) || ...
        ~isequal(trough_overrides_or_empty(before), ...
            trough_overrides_or_empty(after));
end

function overrides = trough_overrides_or_empty(b)
% TROUGH_OVERRIDES_OR_EMPTY Normalize optional legacy override metadata.

    overrides = zeros(0, 3);
    if isfield(b, 'trough_overrides') && isnumeric(b.trough_overrides) && ...
            size(b.trough_overrides, 2) == 3
        overrides = b.trough_overrides;
    end
end
