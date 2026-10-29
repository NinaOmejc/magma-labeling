function results = attach_review_phenotypes(results)
% ATTACH_REVIEW_PHENOTYPES Freeze computed phenotypes on the active review round.
% Older rounds without snapshots remain readable; existing snapshots are immutable.

    if ~isfield(results, 'review_history') || isempty(results.review_history) || ...
            ~isfield(results, 'review_provenance') || ...
            ~isfinite(results.review_provenance.latest_round_id)
        return;
    end
    if isfield(results, 'manual_label_edit') && ...
            isfield(results.manual_label_edit, 'cancelled') && results.manual_label_edit.cancelled
        return;
    end
    index = find([results.review_history.round_id] == ...
        results.review_provenance.latest_round_id, 1, 'last');
    if isempty(index)
        error('MAGMA:PhenotypeHistory:MissingRound', ...
            'The active review round is missing from review_history.');
    end
    changed = false;
    original_history = results.review_history;
    if ~isfield(results.review_history, 'phenotypes_reviewed') || ...
            isempty(results.review_history(index).phenotypes_reviewed)
        results.review_history(index).phenotypes_reviewed = results.phenotypes.reviewed;
        changed = true;
    end
    if ~isfield(results.review_history, 'phenotype_numeric_summary_reviewed') || ...
            isempty(results.review_history(index).phenotype_numeric_summary_reviewed)
        results.review_history(index).phenotype_numeric_summary_reviewed = ...
            results.review_history(index).phenotypes_reviewed.numeric_summary;
        changed = true;
    end
    if isfield(results, 'manual_label_edit')
        results.manual_label_edit.review_history = results.review_history;
        if changed && isfield(results.manual_label_edit, 'edit_file') && ...
                isfile(results.manual_label_edit.edit_file)
            edit_file = results.manual_label_edit.edit_file;
            manual_label_review = manual_label_checkpoint('load', edit_file);
            if ~isequaln(manual_label_review.history, original_history)
                error('MAGMA:PhenotypeHistory:CheckpointChanged', ...
                    'Checkpoint history changed; no snapshots were overwritten: %s', edit_file);
            end
            manual_label_review.history = results.review_history;
            manual_label_checkpoint('save', edit_file, manual_label_review);
        end
    end
end
