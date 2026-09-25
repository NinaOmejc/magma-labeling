function tf = should_analyze_recording( ...
    result_exists, overwrite_results, mode, selected_labels)
% SHOULD_ANALYZE_RECORDING Resolve full-run versus selective-update skip logic.

    selected_labels = cellstr(string(selected_labels));
    if ~result_exists
        tf = true;
        return;
    end
    if ~isempty(selected_labels)
        tf = true;
        return;
    end
    tf = strcmp(mode, 'review_only') || ...
        strcmp(mode, 'analyze_and_review') || logical(overwrite_results);
end
