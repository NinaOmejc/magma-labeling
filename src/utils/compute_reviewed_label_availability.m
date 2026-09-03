function [reviewed_assessable_mask, reviewed_available, reviewed_reasons] = ...
    compute_reviewed_label_availability( ...
        label_available, label_availability_reason, ...
        label_assessable_mask, gold_review_mask)
% compute_reviewed_label_availability
% A reviewed label is available only when at least one sample is both
% explicitly reviewed and scientifically assessable. Reviewed negatives
% remain valid; a review drawn only over unavailable samples does not.

    if ~isequal(size(label_assessable_mask), size(gold_review_mask))
        error('MAGMA:ReviewedAvailability:MaskAlignment', ...
            'label_assessable_mask and gold_review_mask must align.');
    end
    L = size(label_assessable_mask, 2);
    if numel(label_available) ~= L || numel(label_availability_reason) ~= L
        error('MAGMA:ReviewedAvailability:LabelAlignment', ...
            'Availability vectors must contain one value per mask column.');
    end

    label_available = logical(label_available(:)');
    label_assessable_mask = logical(label_assessable_mask);
    gold_review_mask = logical(gold_review_mask);
    reviewed_assessable_mask = label_assessable_mask & gold_review_mask;
    reviewed_available = label_available & any(reviewed_assessable_mask, 1);
    reviewed_reasons = cellstr(string(label_availability_reason));
    reviewed_reasons = reshape(reviewed_reasons, 1, []);
    has_review_scope = any(gold_review_mask, 1);
    reviewed_reasons(~reviewed_available & has_review_scope) = ...
        {'review_scope_unassessable'};
    reviewed_reasons(~has_review_scope) = {'unreviewed'};
end
