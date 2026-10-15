function [identities, enriched_links, audit] = resolve_master_visits(sources, repeat_source, questionnaire, config)
% RESOLVE_MASTER_VISITS Directed repeat identities and explicitly supported order.
% Subject numbers affect presentation order only, never visit chronology.
    audit=master_audit_entry();
    parent_col=master_source_column(repeat_source,config.repeat_mapping.parent_column);
    child_col=master_source_column(repeat_source,config.repeat_mapping.child_column);
    links=repeat_source.table;
    parents=strings(height(links),1); children=parents;
    for r=1:height(links)
        parents(r)=master_subject_id(master_table_value(links,parent_col,r));
        children(r)=master_subject_id(master_table_value(links,child_col,r));
        if parents(r)=="" || children(r)==""
            audit=[audit; entry('error','unresolved_repeat_link','',config.repeat_mapping.file, ...
                config.repeat_mapping.sheet,repeat_source.source_rows(r),'Repeat link requires two valid original subject identifiers.')]; %#ok<AGROW>
        end
    end
    ids=[parents;children];
    for s=1:numel(sources), ids=[ids;sources(s).table.source_subject_id]; end %#ok<AGROW>
    ids=unique(ids(ids~=""));
    numbers=str2double(erase(ids,'Sub')); [~,order]=sort(numbers); ids=ids(order);
    participant=strings(size(ids));
    for i=1:numel(ids)
        node=ids(i); visited=strings(0,1);
        while true
            if any(visited==node)
                audit=[audit; entry('error','cyclic_repeat_mapping',ids(i),'','',NaN,'No canonical identity assigned to a cyclic repeat chain.')]; %#ok<AGROW>
                break;
            end
            visited(end+1,1)=node; %#ok<AGROW>
            upstream=unique(parents(children==node)); upstream=upstream(upstream~="");
            if isempty(upstream), participant(i)=node; break; end
            if numel(upstream)>1
                audit=[audit; entry('error','conflicting_repeat_parents',ids(i),'','',NaN,'Repeat ID is linked to more than one original participant.')]; %#ok<AGROW>
                break;
            end
            node=upstream;
        end
    end
    dates=NaT(numel(ids),1); date_provenance=strings(numel(ids),1);
    for i=1:numel(ids)
        rows=find(questionnaire.source_subject_id==ids(i));
        values=NaT(0,1); refs=strings(0,1);
        for r=rows'
            d=master_table_value(questionnaire,'import_study_date',r);
            if isdatetime(d) && ~isnat(d)
                values(end+1,1)=d; %#ok<AGROW>
                refs(end+1,1)=questionnaire.import_source_file(r)+":"+questionnaire.import_source_sheet(r)+":"+questionnaire.import_source_row(r); %#ok<AGROW>
            end
        end
        distinct=unique(values);
        if numel(distinct)==1
            dates(i)=distinct; date_provenance(i)=strjoin(unique(refs,'stable'),'; ');
        elseif numel(distinct)>1
            audit=[audit; entry('warning','conflicting_study_dates',ids(i),'','',NaN,'Multiple study dates for one source visit; no date selected.')]; %#ok<AGROW>
        end
    end
    dates.Format='yyyy-MM-dd';
    identities=table(participant,ids,"Visit_"+ids,nan(numel(ids),1),dates, ...
        repmat("unresolved",numel(ids),1),date_provenance,strings(numel(ids),1), ...
        'VariableNames',{'participant_id','source_subject_id','visit_id','visit_number', ...
        'confirmed_study_date','visit_order_basis','study_date_provenance','visit_order_notes'});
    [overrides,override_notes,override_audit]=read_overrides(ids,config);
    audit=[audit;override_audit];
    groups=unique(participant(participant~=""));
    for p=1:numel(groups)
        idx=find(participant==groups(p)); n=numel(idx); local_ids=ids(idx);
        edges=false(n); root=find(local_ids==groups(p),1);
        if isempty(root), continue; end
        edges(root,:)=true; edges(root,root)=false;
        for r=1:numel(parents)
            a=find(local_ids==parents(r),1); b=find(local_ids==children(r),1);
            if ~isempty(a) && ~isempty(b), edges(a,b)=true; end
        end
        d=dates(idx);
        dated=find(~isnat(d));
        for a=dated'
            for b=dated'
                if d(a)<d(b), edges(a,b)=true; end
            end
        end
        fixed=overrides(idx); fixed(root)=1;
        if isfinite(overrides(idx(root))) && overrides(idx(root))~=1
            audit=[audit; entry('error','baseline_override_conflict',local_ids(root),config.visit_order_overrides_file,'',NaN,'The original participant visit must be visit 1.')]; %#ok<AGROW>
        end
        known=find(isfinite(fixed));
        if numel(unique(fixed(known)))~=numel(known)
            audit=[audit; entry('error','duplicate_visit_number',groups(p),config.visit_order_overrides_file,'',NaN,'Two source visits have the same explicit visit number.')]; %#ok<AGROW>
            continue;
        end
        for a=known'
            for b=known'
                if fixed(a)<fixed(b), edges(a,b)=true; end
            end
        end
        % Reject date/mapping/override contradictions before accepting any order.
        graph=digraph(edges);
        if ~isdag(graph)
            audit=[audit; entry('error','contradictory_visit_order',groups(p),'','',NaN,'Confirmed dates, repeat links or overrides contradict one another.')]; %#ok<AGROW>
            continue;
        end
        assigned=fixed; basis=repmat("manual_override",n,1);
        basis(root)="original_visit_mapping";
        if n==1, basis(root)="single_source_visit"; end
        unresolved=~isfinite(assigned); basis(unresolved)="unresolved";
        remaining=true(n,1);
        if all(fixed(known)<=n)
            for slot=1:n
                available=find(remaining & ~any(edges(remaining,:),1)');
                prescribed=find(fixed==slot);
                if ~isempty(prescribed)
                    available=intersect(available,prescribed);
                else
                    available=available(~isfinite(fixed(available)));
                end
                if numel(available)~=1, break; end % ambiguity remains explicit
                chosen=available(1); assigned(chosen)=slot;
                if ~isfinite(fixed(chosen))
                    if numel(dated)>=2, basis(chosen)="confirmed_study_dates";
                    else, basis(chosen)="repeat_mapping_order"; end
                end
                remaining(chosen)=false;
            end
        end
        identities.visit_number(idx)=assigned;
        identities.visit_order_basis(idx)=basis;
        identities.visit_order_notes(idx)=override_notes(idx);
        for u=find(~isfinite(assigned))'
            audit=[audit; entry('warning','unresolved_visit_order',local_ids(u),'','',NaN, ...
                'Supply a confirmed visit_number in visit_order_overrides.csv; longitudinal measure remains missing.')]; %#ok<AGROW>
        end
    end
    enriched_links=links;
    [~,a]=ismember(parents,ids); [~,b]=ismember(children,ids);
    enriched_links.first_source_subject_id=parents;
    enriched_links.repeat_source_subject_id=children;
    enriched_links.participant_id=strings(height(links),1);
    enriched_links.first_visit_id=strings(height(links),1);
    enriched_links.repeat_visit_id=strings(height(links),1);
    enriched_links.first_visit_number=nan(height(links),1);
    enriched_links.repeat_visit_number=nan(height(links),1);
    valid=a>0 & b>0;
    enriched_links.participant_id(valid)=identities.participant_id(a(valid));
    enriched_links.first_visit_id(valid)=identities.visit_id(a(valid));
    enriched_links.repeat_visit_id(valid)=identities.visit_id(b(valid));
    enriched_links.first_visit_number(valid)=identities.visit_number(a(valid));
    enriched_links.repeat_visit_number(valid)=identities.visit_number(b(valid));
end

function [numbers,notes,audit]=read_overrides(ids,config)
    numbers=nan(numel(ids),1); notes=strings(numel(ids),1); audit=master_audit_entry();
    file=config.visit_order_overrides_file;
    if ~isfile(file), return; end
    T=readtable(file,'Delimiter',',','ReadVariableNames',true,'NumHeaderLines',0, ...
        'TextType','string','VariableNamingRule','preserve');
    required={'source_subject_id','visit_number','confirmed'};
    if ~all(ismember(required,T.Properties.VariableNames))
        error('MAGMA:Metadata:Overrides','Overrides require source_subject_id, visit_number, confirmed. Found: %s', ...
            strjoin(string(T.Properties.VariableNames),', '));
    end
    for r=1:height(T)
        confirmed=lower(master_cell_text(master_table_value(T,'confirmed',r)));
        if ~ismember(confirmed,["true","1","yes"]), continue; end
        id=master_subject_id(master_table_value(T,'source_subject_id',r));
        number=str2double(master_cell_text(master_table_value(T,'visit_number',r)));
        idx=find(ids==id,1);
        if ~isfinite(number) || number<1 || number~=fix(number)
            audit=[audit; entry('error','invalid_visit_override',id,file,'',r+1,'Confirmed visit number must be a positive integer.')]; %#ok<AGROW>
        elseif isempty(idx)
            audit=[audit; entry('warning','unused_visit_override',id,file,'',r+1,'Override retained, but the source ID is absent from the configured inputs.')]; %#ok<AGROW>
        elseif isfinite(numbers(idx)) && numbers(idx)~=number
            audit=[audit; entry('error','conflicting_visit_overrides',id,file,'',r+1,'Conflicting confirmed assignments for one source visit.')]; %#ok<AGROW>
        else
            numbers(idx)=number;
            if ismember('notes',T.Properties.VariableNames), notes(idx)=master_cell_text(master_table_value(T,'notes',r)); end
        end
    end
end

function row=entry(severity,code,id,file,sheet,r,detail)
    row=master_audit_entry(severity,code,'Identity_map',id,'visit_number',file,sheet,r,detail);
end
