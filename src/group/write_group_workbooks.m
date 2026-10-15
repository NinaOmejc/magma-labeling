function paths = write_group_workbooks(results_path, group_table, cohort, data)
% WRITE_GROUP_WORKBOOKS Export two workbooks with indexed, related worksheets.
% Build fresh temporary workbooks so reruns never retain stale sheets/rows.
    out_dir = fullfile(results_path, 'group_analysis');
    if ~isfolder(out_dir), mkdir(out_dir); end
    if nargin < 4
        books = collect_group_workbook_tables(group_table, cohort);
    else
        books = collect_group_workbook_tables(group_table, cohort, data);
    end
    paths = {fullfile(out_dir, 'group_summary.xlsx'), ...
        fullfile(out_dir, 'group_details.xlsx')};
    tables = {books.summary, books.details};
    for b = 1:2
        temporary = [tempname(out_dir) '.xlsx'];
        cleanup = onCleanup(@() delete_if_present(temporary));
        entries = tables{b};
        sheet = string(entries(:, 1));
        description = string(entries(:, 3));
        rows = cellfun(@height, entries(:, 2));
        index = table(sheet, description, rows);
        writetable(index, temporary, 'Sheet', 'Index', 'UseExcel', false);
        for i = 1:size(entries, 1)
            T = entries{i, 2};
            if width(T) == 0
                writecell({'No records in the selected cohort'}, temporary, ...
                    'Sheet', entries{i, 1}, 'UseExcel', false);
            else
                writetable(T, temporary, 'Sheet', entries{i, 1}, 'UseExcel', false);
            end
        end
        format_group_workbook(temporary, [{index}; entries(:, 2)]);
        movefile(temporary, paths{b}, 'f');
        clear cleanup;
    end
end

function delete_if_present(path)
    if isfile(path), delete(path); end
end
