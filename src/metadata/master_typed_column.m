function values = master_typed_column(cells)
% MASTER_TYPED_COLUMN Preserve numbers/dates natively and heterogeneous tokens.
    cells = cells(:);
    present = false(size(cells));
    for r = 1:numel(cells)
        x = cells{r};
        if isempty(x) || (isscalar(x) && ismissing(x))
            cells{r} = [];
        else
            present(r) = true;
        end
    end
    found = cells(present);
    if isempty(found) || all(cellfun(@(x) (isnumeric(x) || islogical(x)) && isscalar(x), found))
        values = nan(numel(cells),1);
        for r = find(present)', values(r) = double(cells{r}); end
    elseif all(cellfun(@(x) isdatetime(x) && isscalar(x),found))
        values = NaT(numel(cells),1);
        for r = find(present)', values(r) = cells{r}; end
        values.Format = 'yyyy-MM-dd';
    elseif all(cellfun(@(x) ischar(x) || (isstring(x) && isscalar(x)),found))
        values = strings(numel(cells),1); values(:) = missing;
        for r = find(present)', values(r) = string(cells{r}); end
    else
        values = cells; % e.g. numeric observations alongside literal N/A
    end
end
