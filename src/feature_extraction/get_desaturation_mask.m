function desat_mask = get_desaturation_mask(desat_events, t_grid)
% GET_DESATURATION_MASK Return desaturation mask.
%
% Syntax:
%   desat_mask = get_desaturation_mask(desat_events, t_grid)
%
% Inputs:
%   desat_events - Event structure data.
%   t_grid - Time coordinates in seconds.
%
% Outputs:
%   desat_mask - Logical output mask.

    desat_mask = false(size(t_grid));

    if isempty(desat_events) || isempty(t_grid)
        return;
    end

    if ~isstruct(desat_events) || ...
       ~isfield(desat_events, 'start_t') || ...
       ~isfield(desat_events, 'end_t')
        return;
    end

    for k = 1:numel(desat_events)
        s = desat_events(k).start_t;
        e = desat_events(k).end_t;

        if ~isfinite(s) || ~isfinite(e) || e < s
            continue;
        end

        desat_mask = desat_mask | (t_grid >= s & t_grid <= e);
    end
end