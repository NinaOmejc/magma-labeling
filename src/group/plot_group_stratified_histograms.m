function outputs = plot_group_stratified_histograms(config, data)
% PLOT_GROUP_STRATIFIED_HISTOGRAMS Repeat automatic label histograms by group.
% Unknown subjects remain in the all-subject figures, not in either split.
    paths = {};
    outputs = struct('figures', {paths}, 'counts', table(), 'bins', table());
    if ~strcmp(data.layer, 'automatic'), return; end
    groups = {'Control', 'Patient'};
    for i = 1:numel(groups)
        keep = data.groups == string(groups{i});
        if ~any(keep), continue; end
        subset = data;
        subset.subjects = data.subjects(keep);
        subset.groups = data.groups(keep);
        subset.label_values = data.label_values(keep, :, :);
        subset.label_available = data.label_available(keep, :, :);
        subset.recording_present = data.recording_present(keep, :);
        subset.histogram_group = groups{i};
        label = plot_group_label_histograms(config, subset);
        paths{end+1, 1} = label.distribution_figure; %#ok<AGROW>
        outputs.counts = [outputs.counts; label.counts];
        outputs.bins = [outputs.bins; label.bins];
    end
    if any(data.groups == "Control") && any(data.groups == "Patient")
        data.histogram_bins = outputs.bins;
        paths{end+1, 1} = plot_group_combined_label_burden_histograms(config, data);
    end
    outputs.figures = paths;
end

