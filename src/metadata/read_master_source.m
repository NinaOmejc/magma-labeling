function [source, audit] = read_master_source(spec)
% READ_MASTER_SOURCE Read source cells without guessing headers or dropping rows.
% Two-row category headers propagate only across their explicitly named section.
    if ~isfile(spec.file), error('MAGMA:Metadata:MissingInput','Missing source: %s',spec.file); end
    raw = read_master_cells(spec.file, spec.sheet);
    audit = master_audit_entry();
    if size(raw,1) < spec.header_row
        error('MAGMA:Metadata:Header','Missing configured header in %s.',spec.sheet);
    end
    original = strings(1,size(raw,2)); category = original; names = original;
    active_category = "";
    for c = 1:size(raw,2)
        original(c) = master_cell_text(raw{spec.header_row,c});
        value = raw{spec.header_row,c};
        if ischar(value) || (isstring(value) && ~ismissing(value)), original(c)=string(value); end
        if spec.category_row > 0
            section = master_cell_text(raw{spec.category_row,c});
            if strlength(section)>0, active_category = section; end
            category(c) = active_category;
        end
        base = original(c);
        if strlength(base)==0
            base = "source_column_" + c;
            audit = [audit; master_audit_entry('warning','unnamed_source_column',spec.target,'',base, ...
                spec.file,spec.sheet,spec.header_row,'Preserved without assigning a scientific meaning.')]; %#ok<AGROW>
        elseif spec.category_prefixes && strlength(category(c))>0 && ~strcmpi(base,spec.subject_column)
            base = category(c) + "_" + base;
        end
        override = find(strcmp(spec.column_map(:,1),char(original(c))),1);
        if ~isempty(override), base = string(spec.column_map{override,2}); end
        names(c) = normalize_name(base);
        if ismember(names(c), ["participant_id","participant_number","source_subject_id","visit_id","visit_number", ...
                "longitudinal_measure","longitudinal_measure_number","questionnaire_record_id","stress_test_record_id"]) || startsWith(names(c),'import_')
            names(c) = "source_" + names(c);
        end
        if any(names(1:c-1)==names(c))
            names(c) = extractBefore(names(c),min(strlength(names(c))+1,52)) + "_col_" + c;
        end
    end
    if numel(unique(names))~=numel(names), error('MAGMA:Metadata:Columns','Ambiguous column mapping.'); end
    rows = (spec.first_data_row:size(raw,1))';
    nonempty = false(size(rows));
    for i = 1:numel(rows)
        nonempty(i) = any(cellfun(@(x) ~isempty(x) && ~(isscalar(x) && ismissing(x)),raw(rows(i),:)));
    end
    rows = rows(nonempty); % keep every populated source row, even all-missing measurements
    T = table(); storage = strings(numel(names),1);
    for c = 1:numel(names)
        T.(names(c)) = master_typed_column(raw(rows,c));
        storage(c) = string(class(T.(names(c))));
    end
    T.import_source_id = repmat(string(spec.source_id),numel(rows),1);
    T.import_source_file = repmat(string(spec.file),numel(rows),1);
    T.import_source_sheet = repmat(string(spec.sheet),numel(rows),1);
    T.import_source_row = string(rows);
    units = strings(numel(names),1);
    for c = 1:numel(names)
        matches = regexp(char(original(c)), '\(([^)]*)\)|\[([^]]*)\]', 'match');
        if ~isempty(matches), units(c) = strjoin(string(matches),' '); end
    end
    mapping = table(repmat(string(spec.source_id),numel(names),1), ...
        repmat(string(spec.file),numel(names),1),repmat(string(spec.sheet),numel(names),1), ...
        repmat(string(spec.target),numel(names),1),(1:numel(names))',category',original',names',units,storage, ...
        'VariableNames',{'source_id','source_file','source_sheet','target_table','source_column', ...
        'source_category','original_name','output_column','original_units','matlab_type'});
    source = struct('spec',spec,'raw_cells',{raw},'source_rows',rows,'table',T,'mapping',mapping);
end

function name = normalize_name(text)
    name = lower(regexprep(char(text),'[^a-zA-Z0-9]+','_'));
    name = regexprep(name,'^_+|_+$','');
    if isempty(name) || isempty(regexp(name,'^[a-zA-Z]','once')), name=['x_' name]; end
    if numel(name)>namelengthmax
        % Header-derived suffix stays stable when unrelated columns are appended.
        digest = java.security.MessageDigest.getInstance('SHA-256');
        digest.update(typecast(uint8(unicode2native(char(text),'UTF-8')),'int8'));
        bytes = typecast(digest.digest(),'uint8');
        hex = lower(reshape(dec2hex(bytes,2)',1,[]));
        name = [name(1:namelengthmax-9) '_' hex(1:8)];
    end
    name = string(matlab.lang.makeValidName(name));
end
