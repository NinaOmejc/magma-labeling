function [reviewed_assessable_mask, reviewed_available, reviewed_reasons] = ...
    compute_reviewed_label_availability( ...
        label_available, label_availability_reason, ...
        label_assessable_mask, review_coverage_mask)
% COMPUTE_REVIEWED_LABEL_AVAILABILITY Intersect assessability with explicit review.
% label_available/reasons contain one value per label; label_assessable_mask and
% review_coverage_mask are aligned Nsample-by-Nlabel matrices. The returned mask
% marks assessable reviewed samples, reviewed_available is 1-by-Nlabel, and
% reviewed_reasons distinguishes unreviewed from reviewed-but-unassessable labels.

    if ~isequal(size(label_assessable_mask), size(review_coverage_mask))
        error('MAGMA:ReviewedAvailability:MaskAlignment', ...
            'label_assessable_mask and review_coverage_mask must align.');
    end
    L = size(label_assessable_mask, 2);
    if numel(label_available) ~= L || numel(label_availability_reason) ~= L
        error('MAGMA:ReviewedAvailability:LabelAlignment', ...
            'Availability vectors must contain one value per mask column.');
    end

    label_available = logical(label_available(:)');
    label_assessable_mask = logical(label_assessable_mask);
    review_coverage_mask = logical(review_coverage_mask);
    reviewed_assessable_mask = label_assessable_mask & review_coverage_mask;
    reviewed_available = label_available & any(reviewed_assessable_mask, 1);
    reviewed_reasons = cellstr(string(label_availability_reason));
    reviewed_reasons = reshape(reviewed_reasons, 1, []);
    has_review_scope = any(review_coverage_mask, 1);
    reviewed_reasons(~reviewed_available & has_review_scope) = ...
        {'review_scope_unassessable'};
    reviewed_reasons(~has_review_scope) = {'unreviewed'};
end
