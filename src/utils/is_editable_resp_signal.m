function tf = is_editable_resp_signal(breaths)
% True when the manual breath editor has a usable signal to display/edit.

    tf = false;
    if isempty(breaths) || ~isstruct(breaths) || ~isfield(breaths, 'x0')
        return;
    end

    x = breaths.x0(:);
    tf = any(isfinite(x) & x ~= 0);
end
