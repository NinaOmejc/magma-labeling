function metadata = read_group_subject_metadata(workbook_path)
% READ_GROUP_SUBJECT_METADATA Read Questionnaire grp without editing the workbook.
% Row 1 contains section headers; row 2 contains Sub_code and grp.
    if ~isfile(workbook_path)
        error('MAGMA:Group:MissingMetadataFile', ...
            'Questionnaire workbook not found: %s', workbook_path);
    end
    cells = readcell(workbook_path, 'Sheet', 'Questionnaire', 'Range', 'A:B');
    metadata = parse_group_subject_metadata(cells);
    metadata.source_file = char(string(workbook_path));
end

