function cells = read_master_cells(file, sheet)
% READ_MASTER_CELLS Native spreadsheet types with original text whitespace.
% readcell trims text by default. A public string-only import preserves its
% exact text while the native numeric/date/logical observations stay untouched.
    cells=readcell(file,'Sheet',sheet,'UseExcel',false);
    if isempty(cells), return; end
    opts=spreadsheetImportOptions('NumVariables',size(cells,2));
    opts.Sheet=sheet;
    opts.DataRange=sprintf('A1:%s%d',excel_column(size(cells,2)),size(cells,1));
    opts.VariableNamesRange='';
    opts=setvartype(opts,'string');
    opts=setvaropts(opts,opts.VariableNames,'WhitespaceRule','preserve','TreatAsMissing',{});
    text=table2cell(readtable(file,opts,'UseExcel',false));
    if ~isequal(size(text),size(cells))
        error('MAGMA:Metadata:TextAlignment','Text/native import dimensions differ for %s/%s.',file,sheet);
    end
    for i=1:numel(cells)
        if ischar(cells{i}) || isstring(cells{i})
            if ~ismissing(text{i}), cells{i}=char(text{i}); end
        end
    end
end

function label=excel_column(number)
    label='';
    while number>0
        remainder=mod(number-1,26); label=[char(65+remainder) label]; %#ok<AGROW>
        number=floor((number-1)/26);
    end
end
