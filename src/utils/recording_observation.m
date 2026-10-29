function [observation, extra] = recording_observation(action, config, varargin)
% RECORDING_OBSERVATION Shared, recording-keyed observation and mirror updates.
% load/default are read-only; migrate reconciles legacy mirrors durably.
% set accepts checked, source, expected revision,
% and optionally a review-save callback plus checkpoint filename. complete
% clears pending only after outputs using that revision have been saved.
% A small recovery journal makes interrupted/failed updates explicit to readers.
% Results own current state; before results exist a compatible feature cache
% persists it. Before either exists, state is retained only in this MATLAB session.

    persistent transient
    if isempty(transient), transient = containers.Map('KeyType', 'char', 'ValueType', 'any'); end
    extra = [];
    observation = default_observation(config);
    if strcmp(action, 'default'), return; end
    paths = observation_paths(config);
    if strcmp(action, 'recover')
        saved = load(paths.journal);
        publish(paths, saved.old_observation, config);
        restore_checkpoint(saved);
        transient(paths.results) = saved.old_observation;
        delete(paths.journal);
        if isfolder(paths.lock), rmdir(paths.lock); end
        if ~isempty(saved.review_backup) && isfile(saved.review_backup), delete(saved.review_backup); end
        observation = saved.old_observation;
        return;
    end
    memory = [];
    if isKey(transient, paths.results), memory = transient(paths.results); end
    [observation, needs_migration] = load_state(paths, observation, config, memory);
    if strcmp(action, 'load'), return; end
    if strcmp(action, 'migrate') && ~needs_migration, return; end
    ensure_output_directory(paths.folder);
    [ok, message, message_id] = mkdir(paths.lock);
    if ~ok || strcmp(message_id, 'MATLAB:MKDIR:DirectoryExists')
        error('MAGMA:Observation:Busy', 'Observation update already in progress: %s %s', paths.lock, message);
    end
    cleanup_lock = onCleanup(@() rmdir(paths.lock));
    observation = load_state(paths, observation, config, memory);
    old_observation = observation;
    callback = [];
    review_file = ''; review_backup = ''; review_existed = false;
    switch action
        case 'set'
            requested = varargin{1};
            if islogical(requested) || isnumeric(requested)
                status = 'not_observed';
                if logical(requested), status = 'observed'; end
            else
                status = char(string(requested));
            end
            if ~ismember(status, {'observed','not_observed','not_assessed'})
                error('MAGMA:Observation:Status', 'Invalid observation status: %s', status);
            end
            if numel(varargin) >= 3 && observation.revision ~= varargin{3}
                error('MAGMA:Observation:ChangedDuringReview', ...
                    'Observation changed in another session. Reopen this recording before saving.');
            end
            if numel(varargin) >= 4, callback = varargin{4}; end
            if numel(varargin) >= 5, review_file = varargin{5}; end
            changed = ~strcmp(status, observation.status);
            if strcmp(status,'observed') && is_lung_belt_ignored(config)
                error('MAGMA:Observation:MissingBelt', ...
                    'A belt-present observation cannot be established for a configured missing thoracic belt.');
            end
            if changed
                observation.status = status;
                observation.timestamp = char(datetime('now', 'TimeZone', 'UTC', ...
                    'Format', 'yyyy-MM-dd HH:mm:ss.SSS XXX'));
                observation.reviewer_role = get_config_value(config, 'LabelEdit', 'reviewer_role', 'researcher');
                observation.annotation_source = varargin{2};
                observation.revision = observation.revision + 1;
                observation.pending_reanalysis = true;
                observation.affected_labels = {'shallow','deep','slow','rapid','irregular', ...
                    'apnea','sigh','periodic','thoracic','async'};
                observation.affected_outputs = {'respiratory_polarity','respiratory_cycles','respiratory_reference', ...
                    'respiratory_features','automatic_respiratory_labels', ...
                    'reviewed_summaries','phenotypes'};
            end
        case 'migrate'
            % Reconciliation below writes only existing results/cache/HDF5.
            warning('MAGMA:Observation:LegacyMigration', ...
                'Reconciling observation revision %d into existing results/cache/HDF5. Legacy files are retained: %s', ...
                observation.revision, paths.state);
        case 'complete'
            if observation.revision ~= varargin{1} || ~observation.pending_reanalysis, return; end
            if ~isfile(paths.results)
                error('MAGMA:Observation:IncompleteAnalysis', 'Save a full analysis before clearing pending observation state.');
            end
            analyzed = recording_results('load', paths.results);
            if ~isfield(analyzed, 'analysis_recording_observations') || ...
                    analyzed.analysis_recording_observations.revision ~= observation.revision
                error('MAGMA:Observation:IncompleteAnalysis', 'Saved automatic results do not use the current observation revision.');
            end
            observation.pending_reanalysis = false;
            observation.affected_labels = {};
            observation.affected_outputs = {};
        otherwise
            error('MAGMA:Observation:Action', 'Unknown observation action: %s', action);
    end
    if ~isempty(review_file) && isfile(review_file)
        review_existed = true;
        review_backup = [tempname(paths.folder) '.mat'];
        copyfile(review_file, review_backup);
    end
    save(paths.journal, 'old_observation', 'review_file', 'review_backup', 'review_existed');
    try
        publish(paths, observation, config);
        if ~isempty(callback)
            extra = callback(observation);
            % The callback may have created the first compatible feature cache.
            publish(paths, observation, config);
        end
        transient(paths.results) = observation;
    catch failure
        try
            publish(paths, old_observation, config);
            restore_checkpoint(struct('review_file', review_file, ...
                'review_backup', review_backup, 'review_existed', review_existed));
            transient(paths.results) = old_observation;
            delete(paths.journal);
            if ~isempty(review_backup) && isfile(review_backup), delete(review_backup); end
        catch rollback_failure
            failure = addCause(failure, rollback_failure);
            % Keep journal/backups: subsequent readers refuse mixed revisions.
        end
        rethrow(failure);
    end
    delete(paths.journal);
    if ~isempty(review_backup) && isfile(review_backup), delete(review_backup); end
end

function observation = default_observation(config)
    observation = struct('code', 'minimal_thoracic_excursion', ...
        'subject', config.subject, 'measurement', config.measure, ...
        'scope', 'recording', 'status', 'not_assessed', 'timestamp', '', ...
        'reviewer_role', '', 'annotation_source', 'legacy_default', 'revision', 0, ...
        'pending_reanalysis', false, 'affected_labels', {{}}, 'affected_outputs', {{}});
end

function paths = observation_paths(config)
    folder = fullfile(config.path_results_out, sprintf('Sub%d_M%d', config.subject, config.measure));
    if isfield(config, 'sub_results_path') && ~isempty(config.sub_results_path), folder = config.sub_results_path; end
    stem = sprintf('Sub%d_M%d', config.subject, config.measure);
    result_name = [stem '_results.mat']; cache_name = [stem '_features.mat'];
    if isfield(config, 'sub_results_filename'), result_name = config.sub_results_filename; end
    if isfield(config, 'sub_features_filename'), cache_name = config.sub_features_filename; end
    paths.folder = folder;
    paths.state = fullfile(folder, [stem '_recording_observations.mat']);
    paths.journal = [paths.state '.pending.mat']; paths.lock = [paths.state '.lock'];
    paths.mat = unique({fullfile(folder, result_name), fullfile(folder, cache_name)}, 'stable');
    paths.results = fullfile(folder,result_name);
    paths.hdf5 = fullfile(folder, [stem get_config_value(config, 'HDF5', 'filename_suffix', '_results.h5')]);
end

function [observation, needs_migration] = load_state(paths, observation, config, memory)
    if isfile(paths.journal)
        error('MAGMA:Observation:IncompleteUpdate', ...
            ['Interrupted observation update: %s. Close both GUIs, fix any file-access ' ...
             'problem, then call recording_observation(''recover'', config).'], paths.journal);
    end
    candidates = {}; sources = {};
    needs_migration = false;
    completed_revision = -1;
    if isfile(paths.state)
        saved = load(paths.state, 'recording_observations');
        if isfield(saved, 'recording_observations')
            candidates{end+1} = saved.recording_observations;
            sources{end+1} = paths.state;
        else
            error('MAGMA:Observation:InvalidLegacyState', 'Missing observation in %s.', paths.state);
        end
    end
    for i = 1:numel(paths.mat)
        file = paths.mat{i};
        if ~isfile(file), continue; end
        if strcmp(file,paths.results)
            saved = recording_results('existing',file,config);
            if isempty(fieldnames(saved))
                % Preserve observations in obsolete results during explicit regeneration.
                saved = load(file, 'results', 'recording_observations', 'analysis_recording_observations');
                if isfield(saved, 'results') && isfield(saved.results, 'qc')
                    saved = saved.results.qc;
                elseif isfield(saved, 'results') && isfield(saved.results, 'recording_observations')
                    saved = saved.results;
                end
            end
            if isfield(saved, 'analysis_recording_observations') && ...
                    isfield(saved, 'recording_observations') && ...
                    ~saved.recording_observations.pending_reanalysis && ...
                    saved.analysis_recording_observations.revision == saved.recording_observations.revision
                completed_revision = saved.analysis_recording_observations.revision;
            end
        else
            names = who('-file', file);
            requested = intersect(names, {'recording_observations','subject','measure','feature_cache_meta'});
            if isempty(requested), continue; end
            saved = load(file, requested{:});
            if ~isfield(saved, 'feature_cache_meta') || ...
                    ~all(ismember({'resp_cycles','feature_cache_meta'}, names))
                error('MAGMA:Observation:IncompatibleCache', 'Observation persistence requires a respiratory feature cache: %s', file);
            end
            validate_cache(saved.feature_cache_meta, config, file);
        end
        if all(isfield(saved, {'subject','measure'})) && (saved.subject ~= observation.subject || saved.measure ~= observation.measurement)
            error('MAGMA:Observation:IdentityMismatch', 'Recording identity mismatch: %s', file);
        end
        if isfield(saved, 'feature_cache_meta') && ...
                all(isfield(saved.feature_cache_meta, {'subject','measurement'})) && ...
                (saved.feature_cache_meta.subject ~= observation.subject || saved.feature_cache_meta.measurement ~= observation.measurement)
            error('MAGMA:Observation:IdentityMismatch', 'Feature-cache identity mismatch: %s', file);
        end
        if isfield(saved, 'recording_observations')
            candidates{end+1} = saved.recording_observations;
            sources{end+1} = file;
        else
            needs_migration = true;
        end
    end
    if isfile(paths.hdf5)
        fid = H5F.open(paths.hdf5, 'H5F_ACC_RDONLY', 'H5P_DEFAULT');
        cleanup_hdf5 = onCleanup(@() H5F.close(fid));
        exists = H5L.exists(fid, '/observations', 'H5P_DEFAULT') && ...
            H5L.exists(fid, '/observations/recording_json', 'H5P_DEFAULT');
        clear cleanup_hdf5;
        if exists
            text = read_hdf5_text(paths.hdf5, '/observations/recording_json');
            payload = jsondecode(text{1});
            payload.current.affected_labels = reshape(cellstr(string(payload.current.affected_labels)), 1, []);
            payload.current.affected_outputs = reshape(cellstr(string(payload.current.affected_outputs)), 1, []);
            candidates{end+1} = payload.current;
            sources{end+1} = paths.hdf5;
        end
    end
    if ~isempty(memory)
        candidates{end+1} = memory;
        sources{end+1} = 'current MATLAB session';
    end
    for i = 1:numel(candidates)
        value = candidates{i};
        validate_observation(value, sources{i});
        if value.subject ~= observation.subject || value.measurement ~= observation.measurement
            error('MAGMA:Observation:IdentityMismatch', 'Observation belongs to another recording.');
        end
        if i == 1 || value.revision > observation.revision || ...
                (value.revision == observation.revision && strcmp(sources{i}, paths.results))
            observation = value;
        end
    end
    % Pending evidence is conservative unless the saved results prove completion.
    pending = cellfun(@(x) x.revision == observation.revision && x.pending_reanalysis, candidates);
    if any(pending) && completed_revision ~= observation.revision
        observation = candidates{find(pending, 1)};
    end
    for i = 1:numel(candidates)
        value = candidates{i};
        same_revision = value.revision == observation.revision;
        pending_fields = {'pending_reanalysis','affected_labels','affected_outputs'};
        same_annotation = isequaln(rmfield(value, pending_fields), ...
            rmfield(observation, pending_fields));
        completed = completed_revision == observation.revision;
        conflict = same_revision && ~same_annotation;
        same_dependencies = isequal(string(value.affected_labels(:)), string(observation.affected_labels(:))) && ...
            isequal(string(value.affected_outputs(:)), string(observation.affected_outputs(:)));
        if same_revision && value.pending_reanalysis == observation.pending_reanalysis
            conflict = conflict || ~same_dependencies;
        end
        if value.pending_reanalysis && ~observation.pending_reanalysis && ~completed
            conflict = true; % Never discard a pending revision without completed analysis.
        end
        if ~same_revision && value.revision > 0 && ...
                (isempty(value.timestamp) || isempty(observation.timestamp) || ...
                 ~timestamp_precedes(value.timestamp, observation.timestamp))
            conflict = true;
        end
        if conflict
            error('MAGMA:Observation:InconsistentState', ...
                'Conflicting observation revisions/statuses in %s. Reconcile explicitly; no files were discarded.', sources{i});
        end
        if ~strcmp(sources{i}, 'current MATLAB session') && ~strcmp(sources{i}, paths.state)
            needs_migration = needs_migration || ~same_annotation || ~same_dependencies || ...
                value.pending_reanalysis ~= observation.pending_reanalysis;
        end
    end
end

function publish(paths, recording_observations, config)
    for i = 1:numel(paths.mat)
        file = paths.mat{i};
        if ~isfile(file), continue; end
        if strcmp(file,paths.results)
            current = recording_results('existing',file,config);
            if ~isempty(fieldnames(current))
                patch = struct('recording_observations', recording_observations);
                if all(isfield(current, {'mask_automatic','resp_cycles'}))
                    context = current; context.recording_observations = recording_observations;
                    patch.respiratory_artifact_qc = respiratory_artifact_qc( ...
                        context, size(current.mask_automatic, 1), config.fs);
                end
                recording_results('update',file,patch,current);
            end
        else
            saved = load(file);
            if ~all(isfield(saved, {'resp_cycles','feature_cache_meta'}))
                error('MAGMA:Observation:IncompatibleCache', ...
                    'Observation persistence requires a compatible respiratory feature cache: %s', file);
            end
            validate_cache(saved.feature_cache_meta, config, file);
            if ~isfield(saved, 'recording_observations') || ...
                    ~isequaln(saved.recording_observations, recording_observations)
                saved.recording_observations = recording_observations;
                atomic_save_mat(file, saved);
            end
        end
    end
    if isfile(paths.hdf5), write_recording_observation_hdf5(paths.hdf5, recording_observations); end
end

function validate_observation(value, source)
% VALIDATE_OBSERVATION Reject malformed legacy state before selecting a revision.
    required = {'code','scope','subject','measurement','status','revision','pending_reanalysis', ...
        'timestamp','reviewer_role','annotation_source','affected_labels','affected_outputs'};
    if ~isstruct(value) || ~isscalar(value) || ~all(isfield(value, required)) || ...
            ~isnumeric(value.revision) || ~isreal(value.revision) || ...
            ~isscalar(value.revision) || ~isfinite(value.revision) || ...
            value.revision < 0 || value.revision ~= round(value.revision) || ...
            ~isscalar(value.pending_reanalysis) || ...
            ~strcmp(value.code, 'minimal_thoracic_excursion') || ~strcmp(value.scope, 'recording') || ...
            ~ismember(value.status, {'not_assessed','not_observed','observed'})
        error('MAGMA:Observation:InvalidState', 'Invalid observation state: %s', source);
    end
end

function precedes = timestamp_precedes(older, newer)
% TIMESTAMP_PRECEDES Compare the saved UTC change times without guessing order.
    times = sort({char(older), char(newer)});
    precedes = strcmp(times{1}, older);
end

function validate_cache(meta, config, file)
% VALIDATE_CACHE Validate existing persistence before touching any output mirror.
    if ~all(isfield(meta, {'subject','measurement','fs'})) || ...
            meta.subject ~= config.subject || meta.measurement ~= config.measure || ...
            (isfield(config, 'fs') && meta.fs ~= config.fs)
        error('MAGMA:Observation:IncompatibleCache', 'Feature-cache identity/sampling mismatch: %s', file);
    end
end

function restore_checkpoint(saved)
    if isempty(saved.review_file), return; end
    if saved.review_existed
        copyfile(saved.review_backup, saved.review_file, 'f');
    elseif isfile(saved.review_file)
        delete(saved.review_file);
    end
end
