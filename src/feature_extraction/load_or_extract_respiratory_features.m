function resp_feat = load_or_extract_respiratory_features(data, config)
% Load cached respiratory feature extraction results, or run extraction and cache them.

    cache_file = feature_cache_file(config);
    cache_version = current_feature_cache_version();

    force_recompute = isfield(config, 'overwrite_features') && config.overwrite_features;

    if exist(cache_file, 'file') && ~force_recompute
        cached = load(cache_file);
        if is_valid_feature_cache(cached, size(data,1), cache_version, config)
            resp_feat = cached_resp_feat(cached);
            fprintf('Loaded cached respiratory feature extraction results: %s\n', cache_file);
            return;
        end

        warning('Feature cache exists but is incomplete or mismatched. Recomputing: %s', cache_file);
    elseif exist(cache_file, 'file') && force_recompute
        fprintf('Recomputing respiratory features because config.overwrite_features is true: %s\n', cache_file);
    end

    resp_feat = extract_respiration_features(data, config);

    feature_cache_meta = struct( ...
        'cache_version', cache_version, ...
        'subject', config.subject, ...
        'measure', config.measure, ...
        'fs', config.new_fs, ...
        'n_samples', size(data,1), ...
        'data_columns', {config.data_columns}, ...
        'created_on', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), ...
        'manual_resp_control', isfield(config.resp, 'manual_control') && config.resp.manual_control);

    cache_dir = fileparts(cache_file);
    if ~isfolder(cache_dir)
        mkdir(cache_dir);
    end

    save(cache_file, 'resp_feat', 'feature_cache_meta');
    fprintf('Saved respiratory feature extraction results: %s\n', cache_file);
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
    ok = isfield(cached, 'feature_cache_meta') && isstruct(cached.feature_cache_meta) && ...
       isfield(cached.feature_cache_meta, 'cache_version') && cached.feature_cache_meta.cache_version == cache_version;
    if ~ok
        return;
    end

    if isfield(cached.feature_cache_meta, 'data_columns') && ...
            ~isequal(cellstr(string(cached.feature_cache_meta.data_columns)), cellstr(string(config.data_columns)))
        ok = false;
        return;
    end

    if isfield(cached, 'resp_feat')
        resp_feat = cached.resp_feat;
    elseif all(isfield(cached, {'breaths_lungs', 'breaths_diaph'}))
        resp_feat = struct('lungs', cached.breaths_lungs, 'diaph', cached.breaths_diaph);
    else
        ok = false;
        return;
    end

    ok = is_valid_resp_feat(resp_feat, n_samples);
end

function resp_feat = cached_resp_feat(cached)
    if isfield(cached, 'resp_feat')
        resp_feat = cached.resp_feat;
    else
        resp_feat = struct('lungs', cached.breaths_lungs, 'diaph', cached.breaths_diaph);
    end
end

function ok = is_valid_resp_feat(resp_feat, n_samples)
    ok = isstruct(resp_feat) && isfield(resp_feat, 'lungs') && isfield(resp_feat, 'diaph') && ...
         isstruct(resp_feat.lungs) && isstruct(resp_feat.diaph) && ...
         isfield(resp_feat.lungs, 'peak_idx') && isfield(resp_feat.lungs, 'trough_idx') && ...
         isfield(resp_feat.diaph, 'peak_idx') && isfield(resp_feat.diaph, 'trough_idx');
    if ~ok
        return;
    end

    if isfield(resp_feat.lungs, 'x0') && ~isempty(resp_feat.lungs.x0) && numel(resp_feat.lungs.x0) ~= n_samples
        ok = false;
        return;
    end

    if isfield(resp_feat.diaph, 'x0') && ~isempty(resp_feat.diaph.x0) && numel(resp_feat.diaph.x0) ~= n_samples
        ok = false;
        return;
    end
end

function v = current_feature_cache_version()
    v = 4;
end
