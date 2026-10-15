function names = master_table_names(tables)
% MASTER_TABLE_NAMES Required main tables plus configured visit-level sources.
    names = {'Subjects','Questionnaire','Physiology','Label_burden','Phenotypes'};
    if isfield(tables,'StressTest'), names{end+1}='StressTest'; end
end
