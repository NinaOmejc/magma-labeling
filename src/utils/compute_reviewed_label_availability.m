function [reviewed_assessable_mask, reviewed_available, reviewed_reasons] = ...
    compute_reviewed_label_availability( ...
        label_available, label_availability_reason, ...
        label_assessable_mask, review_coverage_mask)
% COMPUTE_REVIEWED_LABEL_AVAILABILITY Compute reviewed label availability.
%
% Syntax:
%   [reviewed_assessable_mask, reviewed_available, reviewed_reasons] = compute_reviewed_label_availability(label_available, label_availability_reason, label_assessable_mask, review_coverage_mask)
%
% Inputs:
%   label_available - Label identifier or label metadata.
%   label_availability_reason - Label identifier or label metadata.
%   label_assessable_mask - Logical state or selection mask.
%   review_coverage_mask - Logical mask of manually reviewed samples.
%
% Outputs:
%   reviewed_assessable_mask - Logical output mask.
%   reviewed_available - Logical availability result.
%   reviewed_reasons - Output text or identifier.

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
