function [assessable_mask, info] = compute_label_assessable_mask( ...
    data, label_names, label_available, rea_diagnostics, t_grid, config)
% COMPUTE_LABEL_ASSESSABLE_MASK Refine recording-level availability by sample.
% label_available aligns with label_names; data/config.fs define the master sample
% grid. Most labels are assessable for the full recording when available.
% Desaturation follows finite native SpO2 samples; asynchrony projects valid
% coherence-grid evidence to master samples. info documents schema version,
% partial_labels, and the desat/async/other-label rules.

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
            async_rule = ['nearest_master_sample_projection_of_selected_' ...
                'asynchrony_method_assessable_evidence'];
        elseif isfield(rea_diagnostics, 'valid_evidence_mask')
            async_evidence = rea_diagnostics.valid_evidence_mask;
            async_rule = ['nearest_master_sample_projection_of_valid_' ...
                'local_coherence_evidence'];
        else
            async_evidence = [];
            async_rule = 'asynchrony_evidence_unavailable';
        end
    else
        async_evidence = [];
        async_rule = ['nearest_master_sample_projection_of_selected_' ...
            'asynchrony_method_assessable_evidence'];
    end
    if ~isempty(async_idx) && label_available(async_idx) && ...
            ~isempty(async_evidence)
        assessable_mask(:, async_idx) = grid_to_master_mask( ...
            async_evidence, t_grid, ...
            N, config.fs);
    end

    info = struct( ...
        'version', 'label_assessability_v2', ...
        'partial_labels', {{'desat', 'async'}}, ...
        'desat_rule', 'finite_native_spo2_sample_and_recording_level_detection_available', ...
        'async_rule', async_rule, ...
        'other_labels_rule', ['recording_level_availability; an incomplete initial ' ...
            'rolling window is estimator latency, not physiological unassessability']);
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
