function [tables, audit] = integrate_master_sources(sources, config)
% INTEGRATE_MASTER_SOURCES Union columns and merge only validated recording keys.
% Same-source duplicate primary keys are errors. Cross-source complementary
% observations may merge; conflicts require explicit documented precedence.
    targets = {'Questionnaire','Physiology','Label_burden','Phenotypes'};
    specs = [sources.spec];
    if any(strcmp({specs.target},'StressTest')), targets{end+1}='StressTest'; end
    tables = struct(); audit = master_audit_entry();
    for t=1:numel(targets)
        target = targets{t}; combined = table();
        for s=1:numel(sources)
            if ~strcmp(sources(s).spec.target,target), continue; end
            incoming = sources(s).table;
            key = master_primary_key(incoming,target);
            [~,~,group] = unique(key);
            repeated = find(accumarray(group,1)>1);
            for g=repeated'
                rows = find(group==g);
                audit = [audit; master_audit_entry('error','duplicate_source_key',target,key(rows(1)), ...
                    'primary_key',sources(s).spec.file,sources(s).spec.sheet,sources(s).source_rows(rows(1)), ...
                    'Multiple rows in this source share a primary key; none were silently discarded.')]; %#ok<AGROW>
            end
            if width(combined)==0, combined=incoming; continue; end
            [combined,incoming] = align_columns(combined,incoming);
            existing_key = master_primary_key(combined,target);
            for r=1:height(incoming)
                match = find(existing_key==key(r));
                if isempty(match) || ismember(target,{'Questionnaire','StressTest'})
                    combined = [combined; incoming(r,:)]; %#ok<AGROW>
                    existing_key(end+1,1)=key(r); %#ok<AGROW>
                    continue;
                end
                if numel(match)~=1, continue; end % fatal duplicate is already in audit
                for c=1:width(combined)
                    name=combined.Properties.VariableNames{c};
                    a=master_table_value(combined,name,match); b=master_table_value(incoming,name,r);
                    if startsWith(name,'import_source_')
                        combined=assign_value(combined,name,match,join_provenance(a,b));
                    elseif master_value_missing(a) && ~master_value_missing(b)
                        combined=assign_value(combined,name,match,b);
                    elseif ~master_value_missing(a) && ~master_value_missing(b) && ~isequaln(a,b)
                        [allowed,selected]=precedence_value(sources,target,key(r),name,config);
                        severity='error'; code='conflicting_source_values';
                        detail="Conflicting nonmissing values: " + master_cell_text(a) + " versus " + master_cell_text(b);
                        if allowed
                            severity='info'; code='configured_source_precedence';
                            combined=assign_value(combined,name,match,selected);
                            detail=detail + ". Configured rule: " + string(config.source_precedence_reason);
                        end
                        audit=[audit; master_audit_entry(severity,code,target,key(r),name, ...
                            incoming.import_source_file(r),incoming.import_source_sheet(r), ...
                            str2double(incoming.import_source_row(r)),detail)]; %#ok<AGROW>
                    end
                end
            end
        end
        if width(combined)==0
            error('MAGMA:Metadata:MissingTable','No source rows configured for %s.',target);
        end
        [~,order]=sort(master_primary_key(combined,target));
        tables.(target)=combined(order,:);
    end
end

function [allowed,selected]=precedence_value(sources,target,key,field,config)
    allowed=false; selected=[]; best=Inf;
    if isempty(config.source_precedence) || strlength(string(config.source_precedence_reason))==0, return; end
    for s=1:numel(sources)
        source=sources(s);
        if ~strcmp(source.spec.target,target) || ~ismember(field,source.table.Properties.VariableNames), continue; end
        match=find(master_primary_key(source.table,target)==key);
        if numel(match)~=1, continue; end
        value=master_table_value(source.table,field,match);
        if master_value_missing(value), continue; end
        priority=find(string(config.source_precedence)==string(source.spec.source_id),1);
        if isempty(priority), return; end % every contributing source needs a documented rank
        if priority<best, best=priority; selected=value; end
    end
    allowed=isfinite(best);
end

function [A,B] = align_columns(A,B)
    names=unique([A.Properties.VariableNames B.Properties.VariableNames],'stable');
    for i=1:numel(names)
        name=names{i};
        ca=cell(height(A),1); cb=cell(height(B),1);
        if ismember(name,A.Properties.VariableNames)
            for r=1:height(A), ca{r}=master_table_value(A,name,r); end
        end
        if ismember(name,B.Properties.VariableNames)
            for r=1:height(B), cb{r}=master_table_value(B,name,r); end
        end
        all_values=master_typed_column([ca;cb]);
        A.(name)=all_values(1:height(A),:); B.(name)=all_values(height(A)+1:end,:);
    end
    A=A(:,names); B=B(:,names);
end

function T=assign_value(T,name,row,value)
    if iscell(T.(name)), T.(name){row}=value; else, T.(name)(row,:)=value; end
end

function text=join_provenance(a,b)
    parts=unique([split(master_cell_text(a),'; '); split(master_cell_text(b),'; ')],'stable');
    text=strjoin(parts,'; ');
end
