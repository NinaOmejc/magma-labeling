function tf = should_run_label(label_name, selected_labels)
% SHOULD_RUN_LABEL Run all labels for an empty selection, otherwise the subset.

    label_name = char(string(label_name));
    selected_labels = cellstr(string(selected_labels));
    tf = isempty(selected_labels) || ismember(label_name, selected_labels);
end
