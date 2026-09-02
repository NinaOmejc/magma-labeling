function state_mask = analysis_window_endpoints_to_state_mask(endpoint_mask, t_grid, analysis_win_sec)
% analysis_window_endpoints_to_state_mask
% Convert qualifying trailing-window endpoints into their inferred support.
%
% endpoint_mask(i) says that the analysis window ending at t_grid(i)
% qualified. The returned state marks the union of those complete preceding
% windows. A later minimum-duration filter may reject short inferred states;
% it must not require the endpoint mask itself to persist for another full
% analysis window.

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
