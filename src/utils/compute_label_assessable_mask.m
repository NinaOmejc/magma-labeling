function [assessable_mask, info] = compute_label_assessable_mask( ...
    N, label_names, label_available, diagnostics_Des, rea_diagnostics, config)
% COMPUTE_LABEL_ASSESSABLE_MASK Compute label assessable mask.
%
% Syntax:
%   [assessable_mask, info] = compute_label_assessable_mask(N, label_names, label_available, diagnostics_Des, rea_diagnostics, config)
%
% Inputs:
%   N - Number of samples.
%   label_names - Label identifier or label metadata.
%   label_available - Label identifier or label metadata.
%   diagnostics_Des - Detector diagnostic data.
%   rea_diagnostics - Detector diagnostic data.
%   config - Pipeline configuration structure.
%
% Outputs:
%   assessable_mask - Logical output mask.
%   info - Computed summary or metadata structure.

    label_names = cellstr(string(label_names));
    label_available = logical(label_available(:)');
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
    if ~isempty(desat_idx) && label_available(desat_idx) && ...
            isstruct(diagnostics_Des) && ...
            isfield(diagnostics_Des, 'valid_sample_mask') && ...
            numel(diagnostics_Des.valid_sample_mask) == N
        assessable_mask(:, desat_idx) = ...
            logical(diagnostics_Des.valid_sample_mask(:));
    end

    async_idx = find(strcmp(label_names, 'async'), 1);
    if ~isempty(async_idx) && label_available(async_idx) && ...
            isstruct(rea_diagnostics) && ...
            isfield(rea_diagnostics, 'valid_evidence_mask') && ...
            isfield(rea_diagnostics, 'time_sec')
        assessable_mask(:, async_idx) = grid_to_master_mask( ...
            rea_diagnostics.valid_evidence_mask, rea_diagnostics.time_sec, ...
            N, config.fs);
    end

    info = struct( ...
        'version', 'label_assessability_v1', ...
        'partial_labels', {{'desat', 'async'}}, ...
        'desat_rule', 'finite_native_spo2_sample_and_recording_level_detection_available', ...
        'async_rule', 'nearest_master_sample_projection_of_valid_local_coherence_evidence', ...
        'other_labels_rule', ['recording_level_availability; an incomplete initial ' ...
            'rolling window is estimator latency, not physiological unassessability']);
end

function master_mask = grid_to_master_mask(grid_mask, t_grid, N, fs)
% GRID_TO_MASTER_MASK Perform the grid to master mask operation.
%
% Syntax:
%   master_mask = grid_to_master_mask(grid_mask, t_grid, N, fs)
%
% Inputs:
%   grid_mask - Logical state or selection mask.
%   t_grid - Time coordinates in seconds.
%   N - Number of samples.
%   fs - Sampling frequency in hertz.
%
% Outputs:
%   master_mask - Logical output mask.

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
