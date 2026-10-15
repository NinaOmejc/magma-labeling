function config = resolve_group_metadata(config)
% RESOLVE_GROUP_METADATA Use explicit lists or the nearby questionnaire workbook.
% An explicit metadata_file='' disables workbook discovery. Manual group lists
% take precedence. Subjects absent from both lists stay Unknown.
    if ~isempty(config.group.control_subjects) || ...
            ~isempty(config.group.patient_subjects)
        config.group.metadata_source = 'config.group lists';
        return;
    end
    explicit_file = isfield(config.group, 'metadata_file');
    if explicit_file
        workbook_path = char(string(config.group.metadata_file));
        if isempty(workbook_path), return; end
        if ~isfile(workbook_path)
            error('MAGMA:Group:MissingMetadataFile', ...
                'Configured questionnaire workbook not found: %s', workbook_path);
        end
    else
        project_root = fileparts(fileparts(config.path_results_out));
        workbook_path = fullfile(project_root, ...
            'ML_database_WORK_IN_PROGRESS_20Sep26_MG.xlsx');
        if ~isfile(workbook_path), return; end
    end
    metadata = read_group_subject_metadata(workbook_path);
    config.group.control_subjects = metadata.control_subjects;
    config.group.patient_subjects = metadata.patient_subjects;
    config.group.metadata_file = workbook_path;
    config.group.metadata_source = 'Questionnaire.grp';
end

