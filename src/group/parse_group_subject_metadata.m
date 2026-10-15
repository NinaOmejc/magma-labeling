function metadata = parse_group_subject_metadata(cells)
% PARSE_GROUP_SUBJECT_METADATA Map Questionnaire Sub_code and grp columns.
% The workbook dictionary defines grp=0 as Control and grp=1 as Patient.
    if size(cells, 2) < 2
        error('MAGMA:Group:InvalidMetadata', 'Questionnaire requires Sub_code and grp columns.');
    end
    header = [];
    for row = 1:size(cells, 1)
        if strcmpi(cell_text(cells{row, 1}), 'Sub_code') && ...
                strcmpi(cell_text(cells{row, 2}), 'grp')
            header = row;
            break;
        end
    end
    if isempty(header)
        error('MAGMA:Group:InvalidMetadata', ...
            'Questionnaire columns Sub_code and grp were not found.');
    end
    ids = zeros(0, 1);
    codes = zeros(0, 1);
    for row = header+1:size(cells, 1)
        id_text = cell_text(cells{row, 1});
        match = regexp(id_text, '^Sub(\d+)$', 'tokens', 'once', 'ignorecase');
        if isempty(match), continue; end
        code = str2double(string(cells{row, 2}));
        if ~isscalar(code) || ~ismember(code, [0 1]), continue; end
        ids(end+1, 1) = str2double(match{1}); %#ok<AGROW>
        codes(end+1, 1) = code; %#ok<AGROW>
    end
    [subjects, ~, group_index] = unique(ids);
    unique_codes = nan(numel(subjects), 1);
    for i = 1:numel(subjects)
        present_codes = unique(codes(group_index == i));
        if numel(present_codes) ~= 1
            error('MAGMA:Group:ConflictingMetadata', ...
                'Conflicting grp values for Sub%d.', subjects(i));
        end
        unique_codes(i) = present_codes;
    end
    metadata = struct();
    metadata.control_subjects = subjects(unique_codes == 0)';
    metadata.patient_subjects = subjects(unique_codes == 1)';
end


function value = cell_text(item)
    value = '';
    if isempty(item), return; end
    converted = string(item);
    if numel(converted) ~= 1 || ismissing(converted), return; end
    value = strtrim(char(converted));
end