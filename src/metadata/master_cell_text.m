function text = master_cell_text(value)
% MASTER_CELL_TEXT Scalar text for keys/provenance; never changes source values.
    if iscell(value), value = value{1}; end
    if isempty(value) || (isscalar(value) && ismissing(value))
        text = "";
    elseif isdatetime(value)
        value.Format = 'yyyy-MM-dd''T''HH:mm:ss';
        text = string(value);
    else
        text = strtrim(string(value));
    end
end
