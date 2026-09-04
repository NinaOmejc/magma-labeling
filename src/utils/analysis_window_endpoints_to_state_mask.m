function state_mask = analysis_window_endpoints_to_state_mask(endpoint_mask, t_grid, analysis_win_sec)
% ANALYSIS_WINDOW_ENDPOINTS_TO_STATE_MASK Perform the analysis window endpoints to state mask operation.
%
% Syntax:
%   state_mask = analysis_window_endpoints_to_state_mask(endpoint_mask, t_grid, analysis_win_sec)
%
% Inputs:
%   endpoint_mask - Logical state or selection mask.
%   t_grid - Time coordinates in seconds.
%   analysis_win_sec - Duration or window length in seconds.
%
% Outputs:
%   state_mask - Logical output mask.

    endpoint_mask = endpoint_mask(:) ~= 0;
    t_grid = t_grid(:);
    if numel(endpoint_mask) ~= numel(t_grid)
        error('MAGMA:TemporalSemantics:SizeMismatch', ...
            'endpoint_mask and t_grid must have equal lengths.');
    end
    if ~isnumeric(analysis_win_sec) || ~isscalar(analysis_win_sec) || ...
            ~isfinite(analysis_win_sec) || analysis_win_sec < 0
        error('MAGMA:TemporalSemantics:InvalidWindow', ...
            'analysis_win_sec must be a finite nonnegative scalar.');
    end

    state_mask = false(size(endpoint_mask));
    qualifying = find(endpoint_mask);
    for i = 1:numel(qualifying)
        endpoint_t = t_grid(qualifying(i));
        state_mask(t_grid >= endpoint_t - analysis_win_sec & ...
            t_grid <= endpoint_t) = true;
    end
end
