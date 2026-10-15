function tables = sort_master_participants(tables)
% SORT_MASTER_PARTICIPANTS Numeric presentation order without changing identities.
% Repeat recordings use the canonical participant number, not the source ID.
    targets=master_table_names(tables);
    for t=1:numel(targets)
        name=targets{t}; T=tables.(name);
        T.participant_number=str2double(erase(string(T.participant_id),'Sub'));
        T=movevars(T,'participant_number','After','participant_id');
        keys={'participant_number'};
        if ismember('visit_number',T.Properties.VariableNames)
            keys{end+1}='visit_number'; %#ok<AGROW>
        end
        if ismember('measure',T.Properties.VariableNames)
            keys{end+1}='measure'; %#ok<AGROW>
        end
        if strcmp(name,'StressTest')
            % Preserve source test order within each visit, including later tests.
            T.import_sort_row=str2double(T.import_source_row);
            keys=[keys {'import_source_id','import_sort_row'}];
        end
        tables.(name)=sortrows(T,keys,'MissingPlacement','last');
        if strcmp(name,'StressTest'), tables.(name).import_sort_row=[]; end
    end
end
