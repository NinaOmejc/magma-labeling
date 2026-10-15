function database = build_master_database(config)
% BUILD_MASTER_DATABASE Rebuild relational metadata from configured source files.
% No detectors, clinical feature extraction, review GUI or HDF5 writes are called.
% See docs/MASTER_DATABASE.md for keys, mappings, overrides and extension policy.
    required={'sources','repeat_mapping','references','output_dir','output_basename'};
    if ~all(isfield(config,required)), error('MAGMA:Metadata:Config','Use get_master_database_config first.'); end
    ids=string({config.sources.source_id});
    if numel(unique(ids))~=numel(ids), error('MAGMA:Metadata:SourceIDs','Source IDs must be unique.'); end
    if any(~ismember(string({config.sources.target}),["Questionnaire","Physiology","Label_burden","Phenotypes","StressTest"]))
        error('MAGMA:Metadata:Target','Additional sources need an explicit primary target; use references for other tables.');
    end
    if ~isempty(config.source_precedence) && strlength(string(config.source_precedence_reason))==0
        error('MAGMA:Metadata:Precedence','Document source_precedence_reason before enabling precedence.');
    end
    files=unique([string({config.sources.file})';string(config.repeat_mapping.file);string({config.references.file})']);
    if isfile(config.visit_order_overrides_file), files=[files;string(config.visit_order_overrides_file)]; end
    if isfield(config,'study_status_overrides_file') && isfile(config.study_status_overrides_file)
        files=[files;string(config.study_status_overrides_file)];
    end
    manifest=master_input_manifest(files);
    audit=master_audit_entry(); sources=struct([]); mapping=table();
    for s=1:numel(config.sources)
        [source,issues]=read_master_source(config.sources(s)); audit=[audit;issues]; %#ok<AGROW>
        [source,issues]=normalize_master_source_keys(source,config); audit=[audit;issues]; %#ok<AGROW>
        if isempty(sources), sources=source; else, sources(end+1,1)=source; end %#ok<AGROW>
        mapping=[mapping;source.mapping]; %#ok<AGROW>
    end
    [repeat_source,issues]=read_master_source(config.repeat_mapping); audit=[audit;issues];
    mapping=[mapping;repeat_source.mapping];
    [tables,issues]=integrate_master_sources(sources,config); audit=[audit;issues];
    [identities,repeat_links,issues]=resolve_master_visits(sources,repeat_source,tables.Questionnaire,config);
    audit=[audit;issues];
    tables=link_master_keys(tables,identities);
    [tables,issues]=build_master_subjects(tables,identities,config); audit=[audit;issues];
    [issues,counts]=validate_master_database(tables,identities,sources,audit); audit=[audit;issues];
    [tables,audit,study_status_source]=apply_master_study_status(tables,identities,audit,config);
    tables=sort_master_participants(tables);
    tables=add_master_subject_availability(tables);
    if ~isempty(audit), audit=sortrows(audit,{'severity','issue','table_name','key','field','source_file','source_row'}); end
    references=struct('name',{},'cells',{},'source_file',{},'source_sheet',{});
    for r=1:numel(config.references)
        ref=config.references(r);
        references(r)=struct('name',ref.name,'cells',{read_master_cells(ref.file,ref.sheet)}, ...
            'source_file',ref.file,'source_sheet',ref.sheet);
    end
    after=master_input_manifest(files);
    if ~isequaln(manifest,after), error('MAGMA:Metadata:InputChanged','A source changed during the build. Rerun against stable inputs.'); end
    database=struct('tables',tables,'identity_map',identities,'repeat_mapping',repeat_links, ...
        'reference_sheets',references,'import_mapping',mapping,'input_manifest',manifest, ...
        'audit',audit,'row_counts',counts,'config',config,'sources',sources);
    database.study_status_source=study_status_source;
    database.output_files=export_master_database(database,config);
    fprintf('Master database: %s\n',database.output_files.workbook);
    for i=1:height(counts), fprintf('  %s: %d rows\n',counts.table_name(i),counts.output_rows(i)); end
    fprintf('  Unresolved source visits: %d\n',sum(~isfinite(identities.visit_number)));
end
