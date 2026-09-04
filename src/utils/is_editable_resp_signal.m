function tf = is_editable_resp_signal(breaths)
% IS_EDITABLE_RESP_SIGNAL Determine whether editable resp signal.
%
% Syntax:
%   tf = is_editable_resp_signal(breaths)
%
% Inputs:
%   breaths - Respiratory-cycle or belt-evidence structure.
%
% Outputs:
%   tf - Computed output value `tf`.

    tf = false;
    if isempty(breaths) || ~isstruct(breaths) || ~isfield(breaths, 'x0')
        return;
    end

    x = breaths.x0(:);
    tf = any(isfinite(x) & x ~= 0);
end
