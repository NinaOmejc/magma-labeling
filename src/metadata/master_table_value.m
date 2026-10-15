function value = master_table_value(T, column, row)
% MASTER_TABLE_VALUE Unwrap a scalar table observation without converting it.
    values = T.(column);
    if iscell(values), value = values{row}; else, value = values(row,:); end
end
