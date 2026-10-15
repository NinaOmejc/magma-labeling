function yes = master_value_missing(value)
% MASTER_VALUE_MISSING Missing for integration decisions, retaining raw tokens.
    if iscell(value), value = value{1}; end
    yes = isempty(value);
    if yes, return; end
    if ischar(value) || isstring(value)
        s = lower(strtrim(string(value)));
        yes = ismissing(s) || ismember(s, ["", "n/a", "na", "not reported", "unknown", "#n/a"]);
    elseif isscalar(value)
        yes = ismissing(value);
    end
end
