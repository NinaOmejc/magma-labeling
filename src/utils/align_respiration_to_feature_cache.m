function [data, trend, config, reused] = align_respiration_to_feature_cache(data, trend, config, reuse_saved)
% ALIGN_RESPIRATION_TO_FEATURE_CACHE Keep reviewed landmarks on their saved sign.
% Reusing a cycle cache also reuses the respiratory orientation in which its
% peaks and troughs were reviewed. A polarity-method change must not silently
% turn those saved peaks into troughs or overwrite the reviewed cache.
% reuse_saved applies the saved orientation to freshly detrended input before
% manual polarity review, so rechecking cached landmarks never asks again.

    if nargin < 4, reuse_saved = false; end
    reused = false;

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
            strcmpi(char(string(config.execution.mode)), 'review')
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
        if reuse_saved
            error('MAGMA:Respiration:RecheckCacheMissing', ...
                'Restore the reviewed feature cache before rechecking: %s', cache_file);
        end
        return;
    end

    cached = load(cache_file, 'feature_cache_meta');
    if ~isfield(cached, 'feature_cache_meta') || ...
            ~isstruct(cached.feature_cache_meta)
        if reuse_saved
            error('MAGMA:Respiration:RecheckCacheMismatch', ...
                'Saved polarity metadata is unavailable; cache was not changed: %s', cache_file);
        end
        return;
    end
    meta = cached.feature_cache_meta;
    required = {'cache_version', 'subject', 'measurement', 'fs', ...
        'n_samples', 'data_columns', 'belt_polarity_checked', ...
        'diaphragm_polarity_flipped'};
    if ~all(isfield(meta, required)) || ...
            ~ismember(meta.cache_version, [9 10]) || ...
            (meta.cache_version == 10 && ~isfield(meta, 'thoracic_polarity_flipped')) || ...
            ~isequal(meta.subject, config.subject) || ...
            ~isequal(meta.measurement, config.measure) || ...
            ~isequal(meta.fs, config.fs) || ...
            ~isequal(meta.n_samples, size(data, 1)) || ...
            ~isequal(cellstr(string(meta.data_columns)), ...
                cellstr(string(config.data_columns)))
        if reuse_saved
            error('MAGMA:Respiration:RecheckCacheMismatch', ...
                'Saved polarity metadata does not match this recording; cache was not changed: %s', cache_file);
        end
        return;
    end

    if reuse_saved
        [data, trend, config] = apply_saved_polarity(data, trend, config, meta);
        reused = true;
        return;
    end

    relative_qc = config.preprocessing.belt_polarity_qc;
    absolute_qc = config.preprocessing.absolute_polarity_qc;
    [current_relative_checked, current_thoracic_flip, current_relative_flip] = ...
        respiratory_belt_polarity_state(config);
    current_absolute_flip = logical(absolute_qc.absolute_polarity_flipped);
    cached_relative_checked = logical(meta.belt_polarity_checked);
    cached_absolute_checked = cached_logical(meta, 'absolute_polarity_checked');
    cached_relative_flip = logical(meta.diaphragm_polarity_flipped);
    cached_thoracic_flip = cached_logical(meta, 'thoracic_polarity_flipped');
    cached_absolute_flip = cached_logical(meta, 'absolute_polarity_flipped');
    relative_mismatch = current_relative_checked ~= cached_relative_checked || ...
        current_thoracic_flip ~= cached_thoracic_flip || ...
        current_relative_flip ~= cached_relative_flip;
    if relative_mismatch
        % Keep manual choices (and a disabled relative check) authoritative.
        % Cache validation will reject landmarks on a different belt sign.
        return;
    end
    flip_lungs = xor(xor(current_thoracic_flip, current_absolute_flip), ...
        xor(cached_thoracic_flip, cached_absolute_flip));
    flip_diaph = xor(xor(current_relative_flip, current_absolute_flip), ...
        xor(cached_relative_flip, cached_absolute_flip));
    if isfield(relative_qc, 'manual_choice') && ...
            isscalar(relative_qc.manual_choice) && ...
            ismember(relative_qc.manual_choice, [0 1 2]) && ...
            (flip_lungs || flip_diaph)
        % A saved common-sign flip must not undo an explicit manual choice.
        return;
    end
    if isfield(relative_qc, 'manual_choice') && ...
            isscalar(relative_qc.manual_choice) && ...
            ismember(relative_qc.manual_choice, [0 1 2]) && ...
            (flip_lungs || flip_diaph)
        % A saved common-sign flip must not undo an explicit manual choice.
        return;
    end

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
    config.preprocessing.belt_polarity_qc.flipped = cached_thoracic_flip || cached_relative_flip;
    config.preprocessing.belt_polarity_qc.thoracic_polarity_flipped = cached_thoracic_flip;
    config.preprocessing.belt_polarity_qc.diaphragm_polarity_flipped = cached_relative_flip;
    config.preprocessing.belt_polarity_qc.orientation_source = 'feature_cache';
    if relative_mismatch
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

function [data, trend, config] = apply_saved_polarity(data, trend, config, meta)
% APPLY_SAVED_POLARITY Restore acquisition-relative signs without new decisions.
    thoracic_flip = cached_logical(meta, 'thoracic_polarity_flipped');
    diaph_flip = logical(meta.diaphragm_polarity_flipped);
    absolute_flip = cached_logical(meta, 'absolute_polarity_flipped');
    roles = {'lungs', 'diaph'};
    flips = [xor(thoracic_flip, absolute_flip), xor(diaph_flip, absolute_flip)];
    for i = 1:2
        if flips(i) && config.channels.(['has_' roles{i}])
            idx = config.channels.([roles{i} '_idx']);
            data(:, idx) = -data(:, idx);
            trend = flip_trend_column(trend, idx, size(data, 1));
        end
    end

    % Older caches contain only the sign flags, so do not invent a manual choice.
    qc = struct('checked', logical(meta.belt_polarity_checked), ...
        'flipped', thoracic_flip || diaph_flip, ...
        'thoracic_polarity_flipped', thoracic_flip, ...
        'diaphragm_polarity_flipped', diaph_flip, ...
        'mode', 'feature_cache', 'manual_choice', NaN, ...
        'reference_belt', '', 'corrected_belt', '', ...
        'median_window_corr', NaN, 'negative_window_fraction', NaN, ...
        'informative_window_fraction', NaN, 'n_windows', 0, ...
        'n_informative_windows', 0, 'reason', 'reused_feature_cache');
    if isfield(meta, 'belt_polarity_qc') && ...
            isstruct(meta.belt_polarity_qc) && isscalar(meta.belt_polarity_qc)
        names = fieldnames(meta.belt_polarity_qc);
        for i = 1:numel(names)
            qc.(names{i}) = meta.belt_polarity_qc.(names{i});
        end
    end
    qc.checked = logical(meta.belt_polarity_checked);
    qc.flipped = thoracic_flip || diaph_flip;
    qc.thoracic_polarity_flipped = thoracic_flip;
    qc.diaphragm_polarity_flipped = diaph_flip;
    qc.orientation_source = 'feature_cache';
    config.preprocessing.belt_polarity_qc = qc;

    absolute_qc = struct();
    if isfield(meta, 'absolute_polarity_qc') && ...
            isstruct(meta.absolute_polarity_qc) && isscalar(meta.absolute_polarity_qc)
        absolute_qc = meta.absolute_polarity_qc;
    end
    absolute_qc.absolute_polarity_checked = cached_logical(meta, 'absolute_polarity_checked');
    absolute_qc.absolute_polarity_flipped = absolute_flip;
    absolute_qc.absolute_polarity_decision = 'reused_feature_cache';
    absolute_qc.orientation_source = 'feature_cache';
    config.preprocessing.absolute_polarity_qc = absolute_qc;
    config.preprocessing.feature_cache_polarity_used = true;
    log_message(config, 1, ...
        'Respiratory polarity: reusing saved feature-cache orientation; no new polarity review.');
    if isnumeric(qc.median_window_corr) && isscalar(qc.median_window_corr) && ...
            isfinite(qc.median_window_corr)
        if isnumeric(qc.negative_window_fraction) && isscalar(qc.negative_window_fraction) && ...
                isfinite(qc.negative_window_fraction)
            log_message(config, 1, ...
                ['Saved belt-polarity QC (before correction): median r = %.3f, ' ...
                 'negative informative windows = %.1f%%.'], ...
                qc.median_window_corr, 100*qc.negative_window_fraction);
        else
            log_message(config, 1, ...
                'Saved belt-polarity QC (before correction): median r = %.3f.', ...
                qc.median_window_corr);
        end
    else
        log_message(config, 1, ...
            'Saved belt-polarity correlation statistics are unavailable in this feature cache.');
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
