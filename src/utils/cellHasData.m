function tf = cellHasData(x)
    % Check whether a cell contains valid data

    if isempty(x)
        tf = false;
    else
        result = hasData(x);
        tf = any(result(:));
    end
end