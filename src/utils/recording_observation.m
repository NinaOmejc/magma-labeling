function [observation, extra] = recording_observation(action, config, varargin)
% RECORDING_OBSERVATION Shared, recording-keyed observation and mirror updates.
% load/default are read-only. set accepts checked, source, expected revision,
% and optionally a review-save callback plus checkpoint filename. complete
% clears pending only after outputs using that revision have been saved.
% A small recovery journal makes interrupted/failed updates explicit to readers.

    extra = [];
    observation = default_observation(config);
    if strcmp(action, 'default'), return; end
    paths = observation_paths(config);
    if strcmp(action, 'recover')
        saved = load(paths.journal);
        publish(paths, saved.old_observation);
        restore_checkpoint(saved);
        save_state(paths.state, saved.old_observation);
        delete(paths.journal);
        if isfolder(paths.lock), rmdir(paths.lock); end
        if ~isempty(saved.review_backup) && isfile(saved.review_backup), delete(saved.review_backup); end
        observation = saved.old_observation;
        return;
    end
    observation = load_state(paths, observation);
    if strcmp(action, 'load'), return; end
    ensure_output_directory(paths.folder);
    [ok, message, message_id] = mkdir(paths.lock);
    if ~ok || strcmp(message_id, 'MATLAB:MKDIR:DirectoryExists')
        error('MAGMA:Observation:Busy', 'Observation update already in progress: %s %s', paths.lock, message);
    end
    cleanup_lock = onCleanup(@() rmdir(paths.lock));
    observation = load_state(paths, observation);
    old_observation = observation;
    callback = [];
    review_file = ''; review_backup = ''; review_existed = false;
    switch action
        case 'set'
            checked = logical(varargin{1});
            if numel(varargin) >= 3 && observation.revision ~= varargin{3}
                error('MAGMA:Observation:ChangedDuringReview', ...
                    'Observation changed in another session. Reopen this recording before saving.');
            end
            if numel(varargin) >= 4, callback = varargin{4}; end
            if numel(varargin) >= 5, review_file = varargin{5}; end
            if checked == strcmp(observation.status, 'observed')
                if ~isempty(callback), extra = callback(observation); end
                return;
            end
            if checked && is_lung_belt_ignored(config)
                error('MAGMA:Observation:MissingBelt', ...
                    'A belt-present observation cannot be established for a configured missing thoracic belt.');
            end
            observation.status = 'not_observed';
            if checked, observation.status = 'observed'; end
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
        case 'complete'
            if observation.revision ~= varargin{1} || ~observation.pending_reanalysis, return; end
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
        publish(paths, observation);
        if ~isempty(callback), extra = callback(observation); end
        save_state(paths.state, observation); % Commit point, after every mirror/save succeeds.
    catch failure
        try
            publish(paths, old_observation);
            restore_checkpoint(struct('review_file', review_file, ...
                'review_backup', review_backup, 'review_existed', review_existed));
            save_state(paths.state, old_observation);
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
    paths.hdf5 = fullfile(folder, [stem get_config_value(config, 'HDF5', 'filename_suffix', '_results.h5')]);
end

function observation = load_state(paths, observation)
    if isfile(paths.journal)
        error('MAGMA:Observation:IncompleteUpdate', ...
            ['Interrupted observation update: %s. Close both GUIs, fix any file-access ' ...
             'problem, then call recording_observation(''recover'', config).'], paths.journal);
    end
    candidates = {};
    if isfile(paths.state)
        saved = load(paths.state, 'recording_observations');
        candidates{end+1} = saved.recording_observations;
    end
    for i = 1:numel(paths.mat)
        file = paths.mat{i};
        if ~isfile(file), continue; end
        names = who('-file', file);
        requested = intersect(names, {'recording_observations','subject','measure','feature_cache_meta'});
        if isempty(requested), continue; end
        saved = load(file, requested{:});
        if all(isfield(saved, {'subject','measure'})) && (saved.subject ~= observation.subject || saved.measure ~= observation.measurement)
            error('MAGMA:Observation:IdentityMismatch', 'Recording identity mismatch: %s', file);
        end
        if isfield(saved, 'feature_cache_meta') && ...
                all(isfield(saved.feature_cache_meta, {'subject','measurement'})) && ...
                (saved.feature_cache_meta.subject ~= observation.subject || saved.feature_cache_meta.measurement ~= observation.measurement)
            error('MAGMA:Observation:IdentityMismatch', 'Feature-cache identity mismatch: %s', file);
        end
        if isfield(saved, 'recording_observations'), candidates{end+1} = saved.recording_observations; end
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
            candidates{end+1} = payload.current;
        end
    end
    for i = 1:numel(candidates)
        value = candidates{i};
        if value.subject ~= observation.subject || value.measurement ~= observation.measurement
            error('MAGMA:Observation:IdentityMismatch', 'Observation belongs to another recording.');
        end
        if i == 1
            observation = value;
        elseif value.revision ~= observation.revision || ~strcmp(value.status, observation.status) || ...
                value.pending_reanalysis ~= observation.pending_reanalysis
            error('MAGMA:Observation:InconsistentState', 'Observation mirrors disagree: %s', paths.state);
        end
    end
end

function publish(paths, recording_observations)
    for i = 1:numel(paths.mat)
        if isfile(paths.mat{i}), save(paths.mat{i}, 'recording_observations', '-append'); end
    end
    if isfile(paths.hdf5), write_recording_observation_hdf5(paths.hdf5, recording_observations); end
end

function save_state(filename, recording_observations)
    staged = [tempname(fileparts(filename)) '.mat'];
    cleanup = onCleanup(@() delete_if_present(staged));
    save(staged, 'recording_observations');
    [ok, message] = movefile(staged, filename, 'f');
    if ~ok, error('MAGMA:Observation:SaveFailed', '%s: %s', filename, message); end
end

function restore_checkpoint(saved)
    if isempty(saved.review_file), return; end
    if saved.review_existed
        copyfile(saved.review_backup, saved.review_file, 'f');
    elseif isfile(saved.review_file)
        delete(saved.review_file);
    end
end

function delete_if_present(filename)
    if isfile(filename), delete(filename); end
end
