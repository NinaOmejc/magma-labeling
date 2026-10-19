function [qc,state] = respiratory_artifact_qc(recording,N,fs)
% RESPIRATORY_ARTIFACT_QC Describe saved annotations, never infer from label masks.
% Missing legacy metadata is distinct from an explicitly empty annotation.
    source = struct(); known = false; legacy = false;
    if isfield(recording,'respiratory_artifact_state') && has_annotation(recording.respiratory_artifact_state)
        source = recording.respiratory_artifact_state;
        known = true; legacy = ~isfield(source,'artifact_intervals_idx');
    elseif isfield(recording,'resp_cycles') && has_annotation(recording.resp_cycles)
        source = recording.resp_cycles;
        known = true; legacy = ~isfield(source,'artifact_intervals_idx');
    elseif has_annotation(recording)
        source = recording; known = true; legacy = ~isfield(source,'artifact_intervals_idx');
    end
    if isfield(source,'annotation_known'), known = logical(source.annotation_known); end
    config = struct('fs',fs);
    if isfield(recording,'subject'), config.subject = recording.subject; end
    if isfield(recording,'measure'), config.measure = recording.measure; end
    if isfield(source,'revision'), config.respiratory_artifact_state = source; end
    cycles = source;
    if isfield(source,'revision'), cycles = struct(); end
    state = respiratory_artifact_state(cycles,config,N);
    state.annotation_known = known;
    ranges = state.artifact_intervals_idx;
    duration = NaN; fraction = NaN; count = NaN; revision = NaN;
    if known
        duration = sum(ranges(:,2)-ranges(:,1)+1)/fs;
        if N > 0, fraction = duration/(N/fs); end
        count = size(ranges,1); revision = state.revision;
    end
    analysis_revision = 0; % Old analyses predate artifact revisions.
    if isfield(recording,'analysis_respiratory_artifact_revision')
        analysis_revision = recording.analysis_respiratory_artifact_revision;
    end
    stale = state.pending_reanalysis || (known && revision ~= analysis_revision) || ...
        (legacy && ~isempty(ranges));
    qc = struct('respiratory_artifact_duration_sec',duration, ...
        'respiratory_artifact_fraction',fraction,'respiratory_artifact_n_intervals',count, ...
        'respiratory_artifact_revision',revision, ...
        'analysis_respiratory_artifact_revision',analysis_revision, ...
        'respiratory_artifact_pending_reanalysis',logical(stale), ...
        'respiratory_artifact_annotation_known',known, ...
        'automatic_respiratory_results_current',~stale, ...
        'automatic_respiratory_training_eligible',known && ~stale);
end

function known = has_annotation(source)
    known = isfield(source,'artifact_intervals_idx');
    for name = {'lungs','diaph'}
        if ~isfield(source,name{1}), continue; end
        belt = source.(name{1});
        known = known || isnumeric(belt) || ...
            (isstruct(belt) && isfield(belt,'artifact_intervals_idx'));
    end
end
