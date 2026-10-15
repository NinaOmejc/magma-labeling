function outputs = export_master_database(database, config)
% EXPORT_MASTER_DATABASE Native MATLAB tables to XLSX, CSV and optional MAT.
% Stage outputs before replacing generated files. Never write to a raw workbook.
    out=char(config.output_dir); base=char(config.output_basename);
    if isempty(regexp(base,'^[A-Za-z0-9_-]+$','once'))
        error('MAGMA:Metadata:OutputName','Output basename must be a plain filename without a path.');
    end
    if ~isfolder(out), mkdir(out); end
    targets=master_table_names(database.tables);
    outputs=struct('workbook',fullfile(out,[base '.xlsx']), ...
        'mat',fullfile(out,[base '.mat']),'audit',fullfile(out,[base '_audit.csv']), ...
        'report',fullfile(out,[base '_audit.txt']),'csv',strings(numel(targets),1));
    for t=1:numel(targets), outputs.csv(t)=fullfile(out,[targets{t} '.csv']); end
    generated=[string(outputs.workbook);string(outputs.mat);string(outputs.audit);string(outputs.report);outputs.csv];
    input_paths=[database.input_manifest.source_file;string(config.visit_order_overrides_file)];
    for i=1:numel(generated)
        absolute=canonical_path(generated(i));
        for j=1:numel(input_paths)
            if strcmpi(absolute,canonical_path(input_paths(j)))
                error('MAGMA:Metadata:SourceOverwrite','Refusing to overwrite configured input %s.',input_paths(j));
            end
        end
    end
    needed=database.identity_map(~isfinite(database.identity_map.visit_number),{'source_subject_id','participant_id'});
    needed.visit_number=nan(height(needed),1); needed.confirmed=false(height(needed),1);
    needed.notes=repmat("Enter a verified visit assignment, then set confirmed=true.",height(needed),1);
    overrides=char(config.visit_order_overrides_file);
    if ~isfile(overrides)
        parent=fileparts(overrides); if ~isempty(parent) && ~isfolder(parent), mkdir(parent); end
        writetable(needed,overrides);
    end
    writetable(needed,fullfile(out,'visit_order_overrides_needed.csv'));
    writetable(database.audit,outputs.audit);
    write_report(database,outputs.report);
    if any(database.audit.severity=="error")
        error('MAGMA:Metadata:Validation','Master tables were not exported: resolve errors in %s. Existing master outputs were not updated.',outputs.audit);
    end
    stage=tempname(out); mkdir(stage);
    cleanup=onCleanup(@() rmdir(stage,'s'));
    workbook=fullfile(stage,[base '.xlsx']); infos=struct('name',{},'table',{},'header_row',{});
    for t=1:numel(targets)
        name=targets{t}; T=database.tables.(name);
        writetable(T,workbook,'Sheet',name);
        writetable(T,fullfile(stage,[name '.csv']));
        infos(end+1)=struct('name',name,'table',T,'header_row',1); %#ok<AGROW>
    end
    reference_names={'Repeat_ID_mapping','Identity_map','Import_mapping','Input_manifest','Audit'};
    reference_tables={database.repeat_mapping,database.identity_map,database.import_mapping,database.input_manifest,database.audit};
    if isfield(database,'study_status_source') && width(database.study_status_source.table)>0
        reference_names{end+1}='Study_status_overrides';
        reference_tables{end+1}=database.study_status_source.table;
    end
    for r=1:numel(database.reference_sheets)
        ref=database.reference_sheets(r);
        if strlength(string(ref.name))>31 || ismember(ref.name,[targets reference_names])
            error('MAGMA:Metadata:SheetName','Reference sheet names must be unique Excel names of at most 31 characters.');
        end
        values=ref.cells;
        for c=1:numel(values)
            value=values{c};
            if isempty(value) || (isscalar(value) && ismissing(value)), values{c}=[]; end
        end
        writecell(values,workbook,'Sheet',ref.name);
        header=1;
        if strcmp(ref.name,'Job_mapping_key'), header=3; end
        if strcmp(ref.name,'Source_exclusions'), header=0; end
        T=table();
        for c=1:size(values,2), T.(sprintf('column_%d',c))=master_typed_column(values(:,c)); end
        infos(end+1)=struct('name',ref.name,'table',T,'header_row',header); %#ok<AGROW>
    end
    for r=1:numel(reference_names)
        writetable(reference_tables{r},workbook,'Sheet',reference_names{r});
        infos(end+1)=struct('name',reference_names{r},'table',reference_tables{r},'header_row',1); %#ok<AGROW>
    end
    if config.format_workbook, format_master_workbook(workbook,infos); end
    if config.export_mat
        version='-v7'; if isfield(config,'mat_version'), version=char(config.mat_version); end
        if ~ismember(version,{'-v7','-v7.3'}), error('MAGMA:Metadata:MatVersion','Use -v7 or -v7.3.'); end
        save(fullfile(stage,[base '.mat']),'database',version);
    end
    entries=dir(stage);
    for i=1:numel(entries)
        if entries(i).isdir, continue; end
        staged_file=fullfile(stage,entries(i).name);
        generated_file=fullfile(out,entries(i).name);
        try
            movefile(staged_file,generated_file,'f');
        catch move_error
            % A read-only preview may allow writes while denying rename/delete.
            [copied,~]=copyfile(staged_file,generated_file,'f');
            if ~copied, rethrow(move_error); end
        end
    end
end

function path=canonical_path(path)
    file=java.io.File(char(path)); path=char(file.getCanonicalPath());
end

function write_report(database,file)
    fid=fopen(file,'w','n','UTF-8');
    if fid<0, error('MAGMA:Metadata:AuditWrite','Cannot write audit report.'); end
    cleanup=onCleanup(@() fclose(fid));
    fprintf(fid,'MAGMA master database integration audit\n\n');
    if any(database.audit.severity=="error")
        fprintf(fid,'EXPORT NOT UPDATED: validation errors must be resolved.\n\n');
    else
        fprintf(fid,'No fatal integration errors. Unconfirmed visit numbers remain missing.\n\n');
    end
    for i=1:height(database.row_counts)
        fprintf(fid,'%s: %d output rows; %d input rows\n',database.row_counts.table_name(i), ...
            database.row_counts.output_rows(i),database.row_counts.input_rows(i));
    end
    fprintf(fid,'\nAudit issue counts (integration checks, not scientific statistics):\n');
    codes=unique(database.audit.issue);
    for c=1:numel(codes), fprintf(fid,'%s: %d\n',codes(c),sum(database.audit.issue==codes(c))); end
    unresolved=database.identity_map(~isfinite(database.identity_map.visit_number),:);
    fprintf(fid,'\nUnresolved source visits: %d\n',height(unresolved));
    for r=1:height(unresolved), fprintf(fid,'%s -> %s: confirmed visit-order override needed\n',unresolved.source_subject_id(r),unresolved.participant_id(r)); end
    if ismember('study_status',database.tables.Subjects.Properties.VariableNames)
        dropped=database.tables.Subjects.participant_id(database.tables.Subjects.study_status=="dropped_out");
        fprintf(fid,'\nConfirmed study dropouts: %s\n',strjoin(dropped,', '));
        fprintf(fid,'Original source rows remain. Missing-source entries for confirmed dropouts are informational.\n');
    end
    fprintf(fid,'\nSource/override hashes are recorded in Input_manifest. Scientific values were not recomputed.\n');
    fprintf(fid,'Full row/field details: %s_audit.csv\n',char(database.config.output_basename));
end
