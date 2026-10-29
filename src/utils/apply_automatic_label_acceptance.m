function annotations = apply_automatic_label_acceptance( ...
    annotations, available, reasons, assessable, config)
% APPLY_AUTOMATIC_LABEL_ACCEPTANCE Project policy without inventing manual coverage.
% All masks are Nsample-by-11. Genuine active manual coverage takes precedence
% for its entire label. Policy changes clear only previous policy-derived state;
% immutable review rounds and automatic annotations are never changed.
% Analyze mode creates no accepted review evidence; saved manual scope survives.

    labels = get_labels('short');
    configured = resolve_automatically_accepted_labels(config);
    review_enabled = ~strcmp(execution_mode(config), 'analyze');
    accepted = false(1, numel(labels));
    for i = 1:numel(labels)
        if ~available(i) || ~any(assessable(:, i))
            if strcmp(annotations.review_status{i}, 'automatically_accepted')
                annotations.mask_reviewed(:, i) = false;
                events = annotations.events_reviewed;
                annotations.events_reviewed = events(~strcmp({events.type}, labels{i}));
            end
            annotations.review_status{i} = reasons{i};
            if available(i), annotations.review_status{i} = 'unassessable'; end
            continue;
        end
        if any(annotations.review_coverage_mask(:, i)), continue; end
        was_accepted = strcmp(annotations.review_status{i}, 'automatically_accepted');
        accept = review_enabled && ismember(labels{i}, configured);
        if ~accept && ~was_accepted && review_enabled, continue; end
        annotations.mask_reviewed(:, i) = false;
        events = annotations.events_reviewed;
        annotations.events_reviewed = events(~strcmp({events.type}, labels{i}));
        annotations.review_status{i} = 'unreviewed';
        if ~accept, continue; end
        accepted(i) = true;
        mask = annotations.mask_automatic(:, i) & assessable(:, i);
        annotations.mask_reviewed(:, i) = mask;
        % Preserve automatic event identity/metadata when fully assessable.
        events = annotations.events_automatic(strcmp( ...
            {annotations.events_automatic.type}, labels{i}));
        automatic = annotations.mask_automatic(:, i);
        if strcmp(labels{i}, 'sigh')
            keep = arrayfun(@(e) assessable(round((e.start_idx+e.end_idx)/2), i), events);
            events = events(keep);
        elseif any(automatic & ~assessable(:, i))
            clipped = false(size(annotations.mask_automatic));
            clipped(:, i) = mask;
            events = label_mask_to_events(clipped, labels, config.fs);
        end
        annotations.events_reviewed = normalize_review_events( ...
            {annotations.events_reviewed, events}, config.fs);
        annotations.review_status{i} = 'automatically_accepted';
    end
    annotations.automatic_acceptance = struct( ...
        'version', 'automatic_label_acceptance_v1', 'enabled', review_enabled, ...
        'configured_labels', {configured}, 'accepted_labels', {labels(accepted)}, ...
        'source', 'saved_automatic_events_and_physiological_assessability', ...
        'manual_precedence', 'active_manual_coverage_for_entire_label');
end
