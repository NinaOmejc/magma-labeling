function labels = resolve_automatically_accepted_labels(config)
% RESOLVE_AUTOMATICALLY_ACCEPTED_LABELS Validate the canonical acceptance policy.
% Missing settings use the default; an explicitly empty subset disables acceptance.

    labels = {'desat', 'slow', 'rapid'};
    if isfield(config, 'LabelEdit') && ...
            isfield(config.LabelEdit, 'review_automatically_accepted')
        labels = config.LabelEdit.review_automatically_accepted;
    end
    if ischar(labels), labels = {labels}; end
    if isstring(labels), labels = cellstr(labels); end
    if ~iscell(labels) || (~isempty(labels) && ~isvector(labels)) || ...
            any(~cellfun(@(x) ischar(x) && isrow(x), labels))
        error('MAGMA:ReviewAcceptance:InvalidLabels', ...
            'LabelEdit.review_automatically_accepted must be a subset of canonical label names.');
    end
    labels = reshape(labels, 1, []);
    if any(~ismember(labels, get_labels('short')))
        error('MAGMA:ReviewAcceptance:UnknownLabel', ...
            'Use canonical label names (including rapid, not fast).');
    end
    if numel(unique(labels)) ~= numel(labels)
        error('MAGMA:ReviewAcceptance:DuplicateLabel', ...
            'Automatically accepted labels must not contain duplicates.');
    end
end
