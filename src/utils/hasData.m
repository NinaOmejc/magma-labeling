
function tf = hasData(x)
    % Check whether each row contains at least one valid value.
    % NaN, Inf, missing strings, and empty cells are invalid.
    % Numeric zero and logical false are valid observations.

    n = size(x,1);

    if isnumeric(x)
        tf = any(isfinite(x),2);

    elseif islogical(x)
        tf = true(n,1);

    elseif isstring(x)
        tf = any(~ismissing(x) & ...
            strlength(strtrim(x)) > 0,2);

    elseif iscategorical(x)
        tf = any(~ismissing(x),2);

    elseif isdatetime(x) || isduration(x)
        tf = any(~ismissing(x),2);

    elseif ischar(x)
        tf = strlength(strtrim(string(cellstr(x)))) > 0;

    elseif iscell(x)
        tf = false(n,1);
        for i = 1:n
            cells = x(i,:);
            tf(i) = any(cellfun(@cellHasData,cells));
        end

    else
        tf = false(n,1);
    end
end
