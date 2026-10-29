function plot_reviewed_label_masks(results, config)
% PLOT_REVIEWED_LABEL_MASKS Refresh current views and preserve round figures.
    if ~isfield(config, 'LabelMask') || ~config.LabelMask.do_plot
        return;
    end
    round_id = NaN;
    if isfield(results, 'review_provenance')
        round_id = results.review_provenance.latest_round_id;
    end
    new_round = isfield(results, 'manual_label_edit') && ...
        isfield(results.manual_label_edit, 'editor_opened') && ...
        results.manual_label_edit.editor_opened && ~results.manual_label_edit.cancelled;
    automatic_plot_events = results.events_automatic;
    legacy_sigh = strcmp({automatic_plot_events.type}, 'sigh') & ...
        [automatic_plot_events.start_idx] ~= [automatic_plot_events.end_idx];
    if any(legacy_sigh) && isfield(results, 'resp_cycles')
        [candidates, ~, panel_peaks] = build_sigh_breath_candidates( ...
            results.resp_cycles, size(results.mask_automatic, 1), config.fs);
        historical_peaks = sigh_events_at_peaks( ...
            automatic_plot_events(legacy_sigh), candidates, panel_peaks, config.fs);
        automatic_plot_events = normalize_review_events( ...
            {automatic_plot_events(~legacy_sigh), historical_peaks}, config.fs);
    end
    reviewed_events = results.events_reviewed;
    if isfield(results, 'label_reviewed_assessable_mask')
        sigh_row = find(strcmp(results.label_names, 'sigh'), 1);
        keep = true(numel(reviewed_events), 1);
        for event = 1:numel(reviewed_events)
            if ~strcmp(reviewed_events(event).type, 'sigh'), continue; end
            peak = round((reviewed_events(event).start_idx + reviewed_events(event).end_idx)/2);
            keep(event) = results.label_reviewed_assessable_mask(peak, sigh_row);
        end
        reviewed_events = reviewed_events(keep);
    end
    names = {'reviewed', 'comparison'};
    for i = 1:2
      for snapshot = 0:1
        if snapshot && (~isfinite(round_id) || ~new_round), continue; end
        view = config;
        view.LabelMask.artifact_context = results;
        view.LabelMask.basename = sprintf('label_mask_%s_current', names{i});
        view.LabelMask.title = sprintf('Label %s | Current review policy', names{i});
        if snapshot
            view.LabelMask.basename = sprintf('label_mask_%s_round_%d', names{i}, round_id);
            view.LabelMask.title = sprintf('Label %s | Review round %d', names{i}, round_id);
        end
        view.LabelMask.review_coverage = false(size(results.mask_reviewed));
        if isfield(results, 'label_reviewed_assessable_mask')
            view.LabelMask.review_coverage = results.label_reviewed_assessable_mask;
        elseif isfield(results, 'review_coverage_mask')
            view.LabelMask.review_coverage = results.review_coverage_mask;
        end
        if isfield(results, 'label_assessable_mask')
            view.LabelMask.assessable_mask = results.label_assessable_mask;
        end
        if snapshot && isfield(config, 'sub_results_path')
            pattern = fullfile(config.sub_results_path, sprintf('Sub%d_M%d_%s.*', ...
                config.subject, config.measure, view.LabelMask.basename));
            if ~isempty(dir(pattern)), continue; end
        end
        reason = results.label_availability_reason;
        if i == 1
            plot_label_mask(results.mask_reviewed, results.label_names, view, ...
                reason, reviewed_events);
        else
            plot_label_mask(results.mask_reviewed, results.label_names, view, ...
                reason, reviewed_events, results.mask_automatic, automatic_plot_events);
        end
      end
    end
end
