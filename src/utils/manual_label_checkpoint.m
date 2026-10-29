function manual_label_review = manual_label_checkpoint(action, filename, manual_label_review)
% MANUAL_LABEL_CHECKPOINT Read legacy/current reviews and replace verified MATs.
% load maps schema-6 variables without rewriting the file or scientific values.
% save writes one container, verifies its complete contents, then replaces the
% destination. Existing observation transactions provide rollback/recovery.

    fields = {'automatic_event_sets', 'reviewed_event_sets', ...
        'review_coverage_mask', 'active_round_id', 'provenance', 'metadata', 'history'};
    legacy = {'manual_label_automatic_event_sets', 'manual_label_event_sets', ...
        'manual_label_review_mask', 'manual_label_active_round_id', ...
        'manual_label_review_provenance', 'manual_label_edit_meta', 'manual_label_review_history'};
    switch action
        case 'load'
            saved = load(filename);
            if isfield(saved, 'manual_label_review')
                if numel(fieldnames(saved)) ~= 1
                    error('MAGMA:ManualLabelEdit:MixedCheckpoint', ...
                        'Checkpoint mixes manual_label_review with other variables; reconcile explicitly: %s', filename);
                end
                manual_label_review = saved.manual_label_review;
            else
                if ~all(isfield(saved, legacy))
                    error('MAGMA:ManualLabelEdit:ObsoleteSchema', ...
                        'Expected a complete schema-6 manual-label checkpoint: %s', filename);
                end
                manual_label_review = struct();
                for i = 1:numel(fields)
                    manual_label_review.(fields{i}) = saved.(legacy{i});
                end
                extra = rmfield(saved, legacy);
                if ~isempty(fieldnames(extra))
                    if isfield(manual_label_review.metadata, 'legacy_top_level_variables')
                        error('MAGMA:ManualLabelEdit:UnknownFieldConflict', ...
                            'Cannot preserve extra checkpoint variables without a metadata collision: %s', filename);
                    end
                    manual_label_review.metadata.legacy_top_level_variables = extra;
                end
            end
        case 'save'
            % Validate below before staging any replacement.
        otherwise
            error('MAGMA:ManualLabelEdit:CheckpointAction', 'Unknown checkpoint action: %s', action);
    end
    if ~isstruct(manual_label_review) || ~isscalar(manual_label_review) || ...
            ~all(isfield(manual_label_review, fields)) || ...
            ~isstruct(manual_label_review.metadata) || ~isscalar(manual_label_review.metadata) || ...
            ~isstruct(manual_label_review.provenance) || ~isscalar(manual_label_review.provenance)
        error('MAGMA:ManualLabelEdit:InvalidCheckpoint', ...
            'manual_label_review must contain the complete review structure: %s', filename);
    end
    if strcmp(action, 'load'), return; end

    folder = fileparts(filename);
    ensure_output_directory(folder);
    edit_file = [tempname(folder) '.mat'];
    cleanup = onCleanup(@() remove_staged(edit_file));
    save(edit_file, 'manual_label_review');
    verified = load(edit_file);
    if ~isequal(fieldnames(verified), {'manual_label_review'}) || ...
            ~isequaln(verified.manual_label_review, manual_label_review)
        error('MAGMA:ManualLabelEdit:CheckpointVerification', ...
            'Checkpoint verification failed; original file retained: %s', filename);
    end
    [ok, message] = movefile(edit_file, filename, 'f');
    if ~ok
        error('MAGMA:Persistence:ReplaceFailed', 'Cannot replace %s: %s', filename, message);
    end
end

function remove_staged(filename)
% REMOVE_STAGED Remove only this save's temporary file after failure.
    if isfile(filename), delete(filename); end
end
