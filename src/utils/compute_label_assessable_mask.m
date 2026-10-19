function [assessable_mask, info] = compute_label_assessable_mask( ...
    data, label_names, label_available, rea_diagnostics, t_grid, config, resp_features, diagnostics)
% COMPUTE_LABEL_ASSESSABLE_MASK Refine recording-level availability by sample.
% label_available aligns with label_names; data/config.fs define the master sample
% grid. Most labels are assessable for the full recording when available.
% Desaturation follows finite native SpO2 samples; asynchrony projects valid
% coherence-grid evidence to master samples. info documents schema version,
% partial_labels, and the desat/async/other-label rules. Fixed-reference sighs
% additionally require session amplitude and per-breath evaluability.

    label_names = cellstr(string(label_names));
    label_available = logical(label_available(:)');
    N = size(data, 1);
    if ~isscalar(N) || ~isnumeric(N) || ~isfinite(N) || N < 0 || N ~= round(N)
        error('MAGMA:Assessability:InvalidSampleCount', ...
            'N must be a finite nonnegative integer.');
    end
    if numel(label_available) ~= numel(label_names)
        error('MAGMA:Assessability:LabelAlignment', ...
            'label_names and label_available must have equal lengths.');
    end
    assessable_mask = repmat(label_available, N, 1);

    desat_idx = find(strcmp(label_names, 'desat'), 1);
    if ~isempty(desat_idx) && label_available(desat_idx)
        if ~isfield(config, 'channels')
            config = resolve_signal_channels(config);
        end
        idx_spo2 = config.channels.spo2_idx;
        if ~isempty(idx_spo2) && idx_spo2 <= size(data, 2)
            assessable_mask(:, desat_idx) = isfinite(data(:, idx_spo2));
        else
            assessable_mask(:, desat_idx) = false(N, 1);
        end
    end

    async_idx = find(strcmp(label_names, 'async'), 1);
    if ~isempty(async_idx) && label_available(async_idx) && ...
            isstruct(rea_diagnostics)
        if isfield(rea_diagnostics, 'primary_valid_evidence_mask')
            async_evidence = rea_diagnostics.primary_valid_evidence_mask;
            async_projection = 'selected_method';
        elseif isfield(rea_diagnostics, 'valid_evidence_mask')
            async_evidence = rea_diagnostics.valid_evidence_mask;
            async_projection = 'coherence';
        else
            async_evidence = [];
            async_projection = 'unavailable';
        end
    else
        async_evidence = [];
        async_projection = 'selected_method';
    end
    if ~isempty(async_idx) && label_available(async_idx) && ...
            ~isempty(async_evidence)
        assessable_mask(:, async_idx) = grid_to_master_mask( ...
            async_evidence, t_grid, ...
            N, config.fs);
    end

    if nargin < 8, diagnostics = struct(); end
    if nargin >= 7
        assessable_mask = assessable_mask & respiratory_artifact_label_mask(resp_features,label_names,N,config,diagnostics);
    end
    sigh_idx = find(strcmp(label_names, 'sigh'), 1);
    session_sigh = nargin >= 7 && ...
        strcmp(get_config_value(config, 'sigh', 'method', 'session_reference_2x'), 'session_reference_2x');
    if session_sigh && ~isempty(sigh_idx)
        assessable_mask(:, sigh_idx) = assessable_mask(:, sigh_idx) & ...
            session_sigh_assessability(resp_features, diagnostics, N, config.fs);
    end
    info = struct( ...
        'version', 'label_assessability_v3', ...
        'partial_labels', {{'desat', 'async'}}, ...
        'async_projection', async_projection, ...
        'respiratory_artifact_model', 'shared_breath_ibi_window_support_v1');
    if session_sigh
        info.partial_labels{end+1} = 'sigh';
        info.sigh_projection = 'session_reference_evaluable_breaths_nearest';
    end
end

function mask = session_sigh_assessability(features, diagnostics, N, fs)
% SESSION_SIGH_ASSESSABILITY Missing reference/ratios are never negative evidence.
% Nearest-breath projection follows the detector's midpoint-bounded events.
    mask = false(N, 1);
    master_t = (0:N-1)' / fs;
    for name = {'lungs', 'diaph'}
        key = name{1}; belt = features.(key);
        required = {'available', 'session_amplitude_available', 'session_reference_value', ...
            'amp_ratio_session', 'amp', 'peak_t'};
        if ~all(isfield(belt, required)) || ~belt.available || ...
                ~isequal(belt.session_amplitude_available, true) || ...
                ~isnumeric(belt.session_reference_value) || ~isreal(belt.session_reference_value) || ...
                ~isscalar(belt.session_reference_value) || ...
                ~isfinite(belt.session_reference_value) || belt.session_reference_value <= 0
            continue;
        end
        t = belt.peak_t(:);
        evaluable = isfinite(belt.amp_ratio_session(:)) & belt.amp_ratio_session(:) > 0 & ...
            isfinite(belt.amp(:)) & belt.amp(:) > 0;
        if isfield(diagnostics, 'sigh') && isfield(diagnostics.sigh, key)
            evaluable = evaluable & diagnostics.sigh.(key).evaluable_mask(:);
        end
        finite_t = isfinite(t);
        t = t(finite_t); evaluable = evaluable(finite_t);
        if isempty(t), continue; end
        if numel(t) == 1
            mask = mask | evaluable;
        else
            mask = mask | (interp1(t, double(evaluable), master_t, 'nearest', 'extrap') ~= 0);
        end
    end
end

function master_mask = grid_to_master_mask(grid_mask, t_grid, N, fs)
% GRID_TO_MASTER_MASK Project a logical analysis-grid mask to N raw samples.
% t_grid is finite, strictly increasing seconds; nearest-neighbor interpolation
% at fs hertz uses false outside the analysis grid.

    grid_mask = logical(grid_mask(:));
    t_grid = t_grid(:);
    if numel(grid_mask) ~= numel(t_grid) || isempty(t_grid)
        error('MAGMA:Assessability:ReAGridAlignment', ...
            'ReA valid_evidence_mask and time_sec must align.');
    end
    if any(~isfinite(t_grid)) || any(diff(t_grid) <= 0)
        error('MAGMA:Assessability:ReAGridTime', ...
            'ReA time_sec must be finite and strictly increasing.');
    end
    master_t = (0:N-1)' / fs;
    master_mask = interp1(t_grid, double(grid_mask), master_t, ...
        'nearest', 0) ~= 0;
end
