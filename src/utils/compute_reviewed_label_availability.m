function [reviewed_assessable_mask, reviewed_available, reviewed_reasons] = ...
    compute_reviewed_label_availability( ...
        label_available, label_availability_reason, ...
        label_assessable_mask, review_coverage_mask, review_status)
% COMPUTE_REVIEWED_LABEL_AVAILABILITY Intersect evidence with effective review scope.
% label_available/reasons contain one value per label; label_assessable_mask and
% review_coverage_mask are aligned Nsample-by-Nlabel matrices. The returned mask
% marks assessable reviewed samples, reviewed_available is 1-by-Nlabel, and
% reviewed_reasons distinguishes unreviewed from reviewed-but-unassessable labels.
% Optional review_status adds assessable automatic acceptance for labels without
% manual coverage. The input manual coverage is never modified.

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
    effective_scope = review_coverage_mask;
    if nargin >= 5
        if numel(review_status) ~= L
            error('MAGMA:ReviewedAvailability:StatusAlignment', 'review_status must align with labels.');
        end
        review_status = reshape(cellstr(string(review_status)), 1, []);
        accepted = strcmp(review_status, 'automatically_accepted') & ...
            ~any(review_coverage_mask, 1);
        effective_scope(:, accepted) = true;
    end
    reviewed_assessable_mask = label_assessable_mask & effective_scope;
    reviewed_available = label_available & any(reviewed_assessable_mask, 1);
    reviewed_reasons = cellstr(string(label_availability_reason));
    reviewed_reasons = reshape(reviewed_reasons, 1, []);
    has_review_scope = any(effective_scope, 1);
    reviewed_reasons(label_available & ~reviewed_available & has_review_scope) = ...
        {'review_scope_unassessable'};
    reviewed_reasons(label_available & ~has_review_scope & ...
        ~strcmp(reviewed_reasons, 'not_computed')) = {'unreviewed'};
end
