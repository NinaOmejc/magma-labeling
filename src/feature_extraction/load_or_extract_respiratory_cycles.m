function resp_cycles = load_or_extract_respiratory_cycles(data, config)
% Load or extract respiratory cycles on the native config.fs master timeline.

    cache_file = feature_cache_file(config);
    cache_version = current_feature_cache_version();

    force_recompute = isfield(config, 'overwrite_features') && config.overwrite_features;

    if exist(cache_file, 'file') && ~force_recompute
        cached = load(cache_file);
        if is_valid_feature_cache(cached, size(data,1), cache_version, config)
            resp_cycles = cached_resp_cycles(cached);
            resp_cycles.provenance.loaded_from_cache = true;
            fprintf('Loaded cached respiratory cycle extraction results: %s\n', cache_file);
            return;
        end

        warning('Feature cache exists but is incomplete or mismatched. Recomputing: %s', cache_file);
    elseif exist(cache_file, 'file') && force_recompute
        fprintf('Recomputing respiratory features because config.overwrite_features is true: %s\n', cache_file);
    end

    resp_cycles = extract_respiration_features(data, config);

    feature_cache_meta = struct( ...
        'cache_version', cache_version, ...
        'subject', config.subject, ...
        'measurement', config.measure, ...
        'fs', config.fs, ...
        'n_samples', size(data,1), ...
        'data_columns', {config.data_columns}, ...
        'created_on', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), ...
        'manual_resp_control', isfield(config.resp, 'manual_control') && config.resp.manual_control);

    cache_dir = fileparts(cache_file);
    if ~isfolder(cache_dir)
        mkdir(cache_dir);
    end

    save(cache_file, 'resp_cycles', 'feature_cache_meta');
    fprintf('Saved respiratory cycle extraction results: %s\n', cache_file);
end

function cache_file = feature_cache_file(config)
    if isfield(config, 'sub_features_filename') && ~isempty(config.sub_features_filename)
        filename = config.sub_features_filename;
    else
        filename = ['Sub' num2str(config.subject) '_M' num2str(config.measure) '_features.mat'];
    end

    if isfield(config, 'sub_results_path') && ~isempty(config.sub_results_path)
        cache_file = fullfile(config.sub_results_path, filename);
    else
        cache_file = fullfile(config.path_results_out, filename);
    end
end

function ok = is_valid_feature_cache(cached, n_samples, cache_version, config)
    required_meta = {'cache_version', 'subject', 'measurement', 'fs', 'n_samples', 'data_columns'};
    ok = isfield(cached, 'feature_cache_meta') && isstruct(cached.feature_cache_meta) && ...
        all(isfield(cached.feature_cache_meta, required_meta));
    if ~ok
        return;
    end

    meta = cached.feature_cache_meta;
    ok = isequal(meta.cache_version, cache_version) && ...
        isequal(meta.subject, config.subject) && ...
        isequal(meta.measurement, config.measure) && ...
        isequal(meta.fs, config.fs) && ...
        isequal(meta.n_samples, n_samples) && ...
        isequal(cellstr(string(meta.data_columns)), cellstr(string(config.data_columns)));
    if ~ok
        ok = false;
        return;
    end

    if ~isfield(cached, 'resp_cycles')
        ok = false;
        return;
    end

    ok = is_valid_resp_cycles(cached.resp_cycles, n_samples);
end

function resp_cycles = cached_resp_cycles(cached)
    resp_cycles = cached.resp_cycles;
end

function ok = is_valid_resp_cycles(resp_cycles, n_samples)
    ok = isstruct(resp_cycles) && isfield(resp_cycles, 'lungs') && ...
         isfield(resp_cycles, 'diaph') && isfield(resp_cycles, 'provenance') && ...
         isstruct(resp_cycles.lungs) && isstruct(resp_cycles.diaph) && ...
         isfield(resp_cycles.lungs, 'peak_idx') && isfield(resp_cycles.lungs, 'trough_idx') && ...
         isfield(resp_cycles.diaph, 'peak_idx') && isfield(resp_cycles.diaph, 'trough_idx') && ...
         is_valid_cycle_provenance(resp_cycles.provenance);
    if ~ok
        return;
    end

    if isfield(resp_cycles.lungs, 'x0') && ~isempty(resp_cycles.lungs.x0) && ...
            numel(resp_cycles.lungs.x0) ~= n_samples
        ok = false;
        return;
    end

    if isfield(resp_cycles.diaph, 'x0') && ~isempty(resp_cycles.diaph.x0) && ...
            numel(resp_cycles.diaph.x0) ~= n_samples
        ok = false;
        return;
    end
end

function ok = is_valid_cycle_provenance(provenance)
    required = {'review_status', 'manual_review_performed', ...
        'manual_edits_made', 'loaded_from_cache'};
    valid_states = {'automatic', 'manual_reviewed_unchanged', ...
        'manual_reviewed_edited'};
    review_status = string.empty;
    if isstruct(provenance) && isfield(provenance, 'review_status')
        review_status = string(provenance.review_status);
    end
    ok = isstruct(provenance) && all(isfield(provenance, required)) && ...
        isscalar(review_status) && ismember(char(review_status), valid_states) && ...
        isscalar(provenance.manual_review_performed) && ...
        isscalar(provenance.manual_edits_made) && ...
        isscalar(provenance.loaded_from_cache) && ...
        logical(provenance.manual_review_performed) == ...
            ~strcmp(char(review_status), 'automatic') && ...
        logical(provenance.manual_edits_made) == ...
            strcmp(char(review_status), 'manual_reviewed_edited');
end

function v = current_feature_cache_version()
    v = 7;
end
