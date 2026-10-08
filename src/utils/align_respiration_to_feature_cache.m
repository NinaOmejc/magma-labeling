function [data, trend, config] = align_respiration_to_feature_cache(data, trend, config)
% ALIGN_RESPIRATION_TO_FEATURE_CACHE Keep reviewed landmarks on their saved sign.
% Reusing a cycle cache also reuses the respiratory orientation in which its
% peaks and troughs were reviewed. A polarity-method change must not silently
% turn those saved peaks into troughs or overwrite the reviewed cache.

    if isvector(data) || ~isfield(config, 'overwrite_features') || ...
            config.overwrite_features || ...
            ~isfield(config, 'subject') || ~isfield(config, 'measure') || ...
            ~isfield(config, 'channels') || ~isfield(config, 'preprocessing') || ...
            (~isfield(config, 'path_results_out') && ...
             ~isfield(config, 'sub_results_path'))
        return;
    end
    if isfield(config, 'execution') && isstruct(config.execution) && ...
            isfield(config.execution, 'mode') && ...
            strcmpi(char(string(config.execution.mode)), 'review_only')
        return;
    end

    filename = sprintf('Sub%d_M%d_features.mat', config.subject, config.measure);
    if isfield(config, 'sub_features_filename') && ...
            ~isempty(config.sub_features_filename)
        filename = config.sub_features_filename;
    end
    cache_dir = '';
    if isfield(config, 'path_results_out')
        cache_dir = config.path_results_out;
    end
    if isfield(config, 'sub_results_path') && ~isempty(config.sub_results_path)
        cache_dir = config.sub_results_path;
    end
    cache_file = fullfile(cache_dir, filename);
    if ~isfile(cache_file)
        return;
    end

    cached = load(cache_file, 'feature_cache_meta');
    if ~isfield(cached, 'feature_cache_meta') || ...
            ~isstruct(cached.feature_cache_meta)
        return;
    end
    meta = cached.feature_cache_meta;
    required = {'cache_version', 'subject', 'measurement', 'fs', ...
        'n_samples', 'data_columns', 'belt_polarity_checked', ...
        'diaphragm_polarity_flipped'};
    if ~all(isfield(meta, required)) || meta.cache_version ~= 9 || ...
            ~isequal(meta.subject, config.subject) || ...
            ~isequal(meta.measurement, config.measure) || ...
            ~isequal(meta.fs, config.fs) || ...
            ~isequal(meta.n_samples, size(data, 1)) || ...
            ~isequal(cellstr(string(meta.data_columns)), ...
                cellstr(string(config.data_columns)))
        return;
    end

    relative_qc = config.preprocessing.belt_polarity_qc;
    absolute_qc = config.preprocessing.absolute_polarity_qc;
    current_relative_flip = logical(relative_qc.flipped);
    current_absolute_flip = logical(absolute_qc.absolute_polarity_flipped);
    cached_relative_checked = logical(meta.belt_polarity_checked);
    cached_absolute_checked = cached_logical(meta, 'absolute_polarity_checked');
    cached_relative_flip = logical(meta.diaphragm_polarity_flipped);
    cached_absolute_flip = cached_logical(meta, 'absolute_polarity_flipped');
    flip_lungs = xor(current_absolute_flip, cached_absolute_flip);
    flip_diaph = xor(xor(current_relative_flip, current_absolute_flip), ...
        xor(cached_relative_flip, cached_absolute_flip));

    if flip_lungs && config.channels.has_lungs
        idx = config.channels.lungs_idx;
        data(:, idx) = -data(:, idx);
        trend = flip_trend_column(trend, idx, size(data, 1));
    end
    if flip_diaph && config.channels.has_diaph
        idx = config.channels.diaph_idx;
        data(:, idx) = -data(:, idx);
        trend = flip_trend_column(trend, idx, size(data, 1));
    end

    config.preprocessing.computed_polarity_qc = struct( ...
        'belt', relative_qc, 'absolute', absolute_qc);
    config.preprocessing.belt_polarity_qc.checked = cached_relative_checked;
    config.preprocessing.belt_polarity_qc.flipped = cached_relative_flip;
    config.preprocessing.belt_polarity_qc.orientation_source = 'feature_cache';
    if relative_qc.checked ~= cached_relative_checked || ...
            current_relative_flip ~= cached_relative_flip
        config.preprocessing.belt_polarity_qc.reason = 'reused_feature_cache';
    end
    config.preprocessing.absolute_polarity_qc.absolute_polarity_checked = ...
        cached_absolute_checked;
    config.preprocessing.absolute_polarity_qc.absolute_polarity_flipped = ...
        cached_absolute_flip;
    config.preprocessing.absolute_polarity_qc.orientation_source = 'feature_cache';
    if absolute_qc.absolute_polarity_checked ~= cached_absolute_checked || ...
            current_absolute_flip ~= cached_absolute_flip
        config.preprocessing.absolute_polarity_qc.absolute_polarity_decision = ...
            'reused_feature_cache';
    end
    config.preprocessing.feature_cache_polarity_used = true;
    if relative_qc.checked ~= cached_relative_checked || ...
            absolute_qc.absolute_polarity_checked ~= cached_absolute_checked || ...
            flip_lungs || flip_diaph
        log_message(config, 1, ...
            ['Respiratory polarity: using the saved feature-cache ' ...
             'orientation so reviewed peaks and troughs remain valid.']);
    end
end

function value = cached_logical(meta, name)
    value = false;
    if isfield(meta, name) && isscalar(meta.(name))
        value = logical(meta.(name));
    end
end

function trend = flip_trend_column(trend, idx, n_samples)
    if ~isempty(trend) && ~isvector(trend) && ...
            size(trend, 1) == n_samples && idx <= size(trend, 2)
        trend(:, idx) = -trend(:, idx);
    end
end
