function tf = is_editable_resp_signal(breaths)
% IS_EDITABLE_RESP_SIGNAL Check for any finite nonzero sample in belt.x0.

    tf = false;
    if isempty(breaths) || ~isstruct(breaths) || ~isfield(breaths, 'x0')
        return;
    end

    x = breaths.x0(:);
    tf = any(isfinite(x) & x ~= 0);
end
