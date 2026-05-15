function [breaths_lungs, breaths_diaph, spo2_feat] = load_or_extract_features(data, baseline, config)
% Load cached feature extraction results, or run extraction and cache them.

    cache_file = feature_cache_file(config);
    cache_version = current_feature_cache_version();

    if exist(cache_file, 'file')
        cached = load(cache_file);
        if is_valid_feature_cache(cached, size(data,1), cache_version)
            breaths_lungs = cached.breaths_lungs;
            breaths_diaph = cached.breaths_diaph;
            spo2_feat = cached.spo2_feat;
            fprintf('Loaded cached feature extraction results: %s\n', cache_file);
            return;
        end

        warning('Feature cache exists but is incomplete or mismatched. Recomputing: %s', cache_file);
    end

    [breaths_lungs, breaths_diaph] = extract_respiration_features(data, baseline, config);
    spo2_feat = extract_spo2_features(data, baseline, config);

    feature_cache_meta = struct( ...
        'cache_version', cache_version, ...
        'subject', config.subject, ...
        'measure', config.measure, ...
        'fs', config.fs, ...
        'n_samples', size(data,1), ...
        'created_on', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), ...
        'manual_resp_control', isfield(config.resp, 'manual_control') && config.resp.manual_control);

    cache_dir = fileparts(cache_file);
    if ~isfolder(cache_dir)
        mkdir(cache_dir);
    end

    save(cache_file, 'breaths_lungs', 'breaths_diaph', 'spo2_feat', 'feature_cache_meta');
    fprintf('Saved feature extraction results: %s\n', cache_file);
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

function ok = is_valid_feature_cache(cached, n_samples, cache_version)
    required = {'breaths_lungs', 'breaths_diaph', 'spo2_feat'};
    ok = all(isfield(cached, required));
    if ~ok
        return;
    end

    if ~isfield(cached, 'feature_cache_meta') || ~isstruct(cached.feature_cache_meta) || ...
       ~isfield(cached.feature_cache_meta, 'cache_version') || cached.feature_cache_meta.cache_version ~= cache_version
        ok = false;
        return;
    end

    ok = isstruct(cached.breaths_lungs) && isstruct(cached.breaths_diaph) && isstruct(cached.spo2_feat) && ...
         isfield(cached.breaths_lungs, 'peak_idx') && isfield(cached.breaths_lungs, 'trough_idx') && ...
         isfield(cached.breaths_diaph, 'peak_idx') && isfield(cached.breaths_diaph, 'trough_idx') && ...
         isfield(cached.spo2_feat, 'spo2');
    if ~ok
        return;
    end

    if isfield(cached.breaths_lungs, 'x0') && numel(cached.breaths_lungs.x0) ~= n_samples
        ok = false;
        return;
    end

    if isfield(cached.breaths_diaph, 'x0') && numel(cached.breaths_diaph.x0) ~= n_samples
        ok = false;
        return;
    end

    if numel(cached.spo2_feat.spo2) ~= n_samples
        ok = false;
    end
end

function v = current_feature_cache_version()
    v = 2;
end
