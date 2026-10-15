function format_master_workbook(filename, sheets)
% FORMAT_MASTER_WORKBOOK Plain headers, readable widths, filters and frozen keys.
% Edits XLSX presentation only; cell values/types and source references are intact.
    folder=tempname; mkdir(folder); cleanup=onCleanup(@() rmdir(folder,'s'));
    unzip(filename,folder);
    file=fullfile(folder,'xl','styles.xml'); styles=xmlread(file);
    fonts=styles.getElementsByTagName('fonts').item(0); font_id=fonts.getElementsByTagName('font').getLength;
    font=styles.createElement('font'); font.appendChild(styles.createElement('b'));
    color=styles.createElement('color'); color.setAttribute('rgb','FFFFFFFF'); font.appendChild(color);
    fonts.appendChild(font); fonts.setAttribute('count',num2str(font_id+1));
    fills=styles.getElementsByTagName('fills').item(0); fill_id=fills.getElementsByTagName('fill').getLength;
    fill=styles.createElement('fill'); pattern=styles.createElement('patternFill'); pattern.setAttribute('patternType','solid');
    color=styles.createElement('fgColor'); color.setAttribute('rgb','FF233955'); pattern.appendChild(color); fill.appendChild(pattern);
    fills.appendChild(fill); fills.setAttribute('count',num2str(fill_id+1));
    formats=styles.getElementsByTagName('cellXfs').item(0); header_id=formats.getElementsByTagName('xf').getLength;
    header=formats.getElementsByTagName('xf').item(0).cloneNode(true);
    header.setAttribute('fontId',num2str(font_id)); header.setAttribute('fillId',num2str(fill_id));
    header.setAttribute('applyFont','1'); header.setAttribute('applyFill','1');
    alignment=styles.createElement('alignment'); alignment.setAttribute('wrapText','1'); alignment.setAttribute('vertical','center');
    alignment.setAttribute('horizontal','center');
    old=header.getElementsByTagName('alignment'); if old.getLength>0, header.removeChild(old.item(0)); end
    header.appendChild(alignment); formats.appendChild(header);
    wrapped_id=formats.getElementsByTagName('xf').getLength;
    wrapped=formats.getElementsByTagName('xf').item(0).cloneNode(true);
    old=wrapped.getElementsByTagName('alignment'); if old.getLength>0, wrapped.removeChild(old.item(0)); end
    alignment=styles.createElement('alignment'); alignment.setAttribute('wrapText','1'); alignment.setAttribute('vertical','top');
    wrapped.appendChild(alignment); wrapped.setAttribute('applyAlignment','1'); formats.appendChild(wrapped);
    number_formats=styles.getElementsByTagName('numFmts');
    if number_formats.getLength==0
        number_formats=styles.createElement('numFmts'); styles.getDocumentElement.insertBefore(number_formats,fonts);
    else, number_formats=number_formats.item(0); end
    date_format_id=164; existing=number_formats.getElementsByTagName('numFmt');
    for n=0:existing.getLength-1, date_format_id=max(date_format_id,str2double(char(existing.item(n).getAttribute('numFmtId')))+1); end
    date_format=styles.createElement('numFmt'); date_format.setAttribute('numFmtId',num2str(date_format_id));
    date_format.setAttribute('formatCode','yyyy-mm-dd'); number_formats.appendChild(date_format);
    number_formats.setAttribute('count',num2str(existing.getLength));
    date_id=formats.getElementsByTagName('xf').getLength;
    date_style=formats.getElementsByTagName('xf').item(0).cloneNode(true);
    date_style.setAttribute('numFmtId',num2str(date_format_id)); date_style.setAttribute('applyNumberFormat','1'); formats.appendChild(date_style);
    time_id=formats.getElementsByTagName('xf').getLength;
    time_style=formats.getElementsByTagName('xf').item(0).cloneNode(true);
    time_style.setAttribute('numFmtId','20'); % source End time display is h:mm
    time_style.setAttribute('applyNumberFormat','1'); formats.appendChild(time_style);
    formats.setAttribute('count',num2str(time_id+1));
    xmlwrite(file,styles);
    top_styles=containers.Map('KeyType','char','ValueType','double');
    for i=1:numel(sheets)
        file=fullfile(folder,'xl','worksheets',sprintf('sheet%d.xml',i)); doc=xmlread(file); root=doc.getDocumentElement;
        data=doc.getElementsByTagName('sheetData').item(0); T=sheets(i).table; h=sheets(i).header_row;
        views=doc.getElementsByTagName('sheetViews');
        if views.getLength==0
            views=doc.createElement('sheetViews'); view=doc.createElement('sheetView'); view.setAttribute('workbookViewId','0');
            views.appendChild(view); root.insertBefore(views,data);
        else, view=views.item(0).getElementsByTagName('sheetView').item(0); end
        view.setAttribute('showGridLines','0');
        old=view.getElementsByTagName('pane');
        while old.getLength>0, view.removeChild(old.item(0)); end
        if h>0
            pane=doc.createElement('pane'); pane.setAttribute('ySplit',num2str(h)); pane.setAttribute('topLeftCell',sprintf('A%d',h+1));
            pane.setAttribute('state','frozen'); pane.setAttribute('activePane','bottomLeft'); view.insertBefore(pane,view.getFirstChild);
            if ismember(sheets(i).name,{'Subjects','Questionnaire','Physiology','Label_burden','Phenotypes','StressTest'}) && width(T)>8
                pane.setAttribute('xSplit','2'); pane.setAttribute('topLeftCell',sprintf('C%d',h+1)); pane.setAttribute('activePane','bottomRight');
            end
        end
        cols=doc.createElement('cols'); widths=zeros(1,width(T));
        for c=1:width(T)
            name=T.Properties.VariableNames{c}; w=max(16,min(42,0.8*numel(name)+4));
            values=T.(name);
            if isstring(values)
                lengths=strlength(values); lengths=lengths(~ismissing(lengths));
                if ~isempty(lengths), w=max(w,min(60,max(lengths)+2)); end
            end
            if contains(name,'file')||contains(name,'provenance'), w=48; end
            if strcmp(sheets(i).name,'StressTest') && strcmp(name,'clininet_pl_txt'), w=90; end
            widths(c)=w;
            col=doc.createElement('col'); col.setAttribute('min',num2str(c)); col.setAttribute('max',num2str(c));
            col.setAttribute('width',num2str(w)); col.setAttribute('customWidth','1'); cols.appendChild(col);
        end
        old=doc.getElementsByTagName('cols'); if old.getLength>0, root.removeChild(old.item(0)); end
        root.insertBefore(cols,data);
        rows=data.getElementsByTagName('row');
        primary=ismember(sheets(i).name,{'Subjects','Questionnaire','Physiology','Label_burden','Phenotypes','StressTest'});
        status_text=find(ismember(T.Properties.VariableNames,{'study_status_provenance','study_status_notes'}));
        if strcmp(sheets(i).name,'StressTest')
            status_text=find(ismember(T.Properties.VariableNames, ...
                {'clinical_status','tolerance_clinical_assessment','clininet_pl_txt'}));
        end
        confirmation_dates=find(ismember(T.Properties.VariableNames,{'confirmed_on','study_status_confirmed_on'}));
        time_columns=[];
        if strcmp(sheets(i).name,'StressTest')
            time_columns=find(strcmp(T.Properties.VariableNames,'end_time'));
        end
        raw_reference=all(startsWith(string(T.Properties.VariableNames),'column_'));
        for r=0:rows.getLength-1
            row=rows.item(r);
            excel_row=str2double(char(row.getAttribute('r')));
            if excel_row==h
                row.setAttribute('ht','60'); row.setAttribute('customHeight','1'); cells=row.getElementsByTagName('c');
                for c=0:cells.getLength-1, cells.item(c).setAttribute('s',num2str(header_id)); end
            elseif ~primary || ~isempty(status_text)
                cells=row.getElementsByTagName('c');
                for c=0:cells.getLength-1
                    cell_node=cells.item(c);
                    letters=regexprep(char(cell_node.getAttribute('r')),'[0-9]',''); column=0;
                    for letter=letters, column=26*column+double(letter)-double('A')+1; end
                    if (~primary || ismember(column,status_text)) && ismember(char(cell_node.getAttribute('t')),{'s','str','inlineStr'})
                        cell_node.setAttribute('s',num2str(wrapped_id));
                    end
                    if ismember(column,confirmation_dates), cell_node.setAttribute('s',num2str(date_id)); end
                    if ismember(column,time_columns) && isempty(char(cell_node.getAttribute('t')))
                        cell_node.setAttribute('s',num2str(time_id));
                    end
                end
                index=excel_row-1; if raw_reference, index=excel_row; end
                required=1;
                if index>=1 && index<=height(T)
                    for c=1:width(T)
                        if primary && ~ismember(c,status_text), continue; end
                        value=master_table_value(T,T.Properties.VariableNames{c},index);
                        if ischar(value) || (isstring(value) && ~ismissing(value))
                            lengths=strlength(split(string(value),newline));
                            lines=max(ceil(lengths/max(5,widths(c)-4)));
                            if any(lengths>widths(c)-4), lines=lines+1; end
                            required=max(required,lines);
                        end
                    end
                end
                row.setAttribute('ht',num2str(min(409,max(18,15*required+4)))); row.setAttribute('customHeight','1');
            end
        end
        old=doc.getElementsByTagName('autoFilter');
        while old.getLength>0, root.removeChild(old.item(0)); end
        if h>0 && rows.getLength>h
            dimension=doc.getElementsByTagName('dimension').item(0); span=char(dimension.getAttribute('ref'));
            parts=split(string(span),':'); finish=parts(end);
            filter=doc.createElement('autoFilter'); filter.setAttribute('ref',char("A"+h+":"+finish)); root.insertBefore(filter,data.getNextSibling);
        end
        if strcmp(sheets(i).name,'StressTest')
            % Align keys with the first line of wrapped clinical notes, while
            % retaining each cell's numeric/date/time format.
            cells=data.getElementsByTagName('c');
            for c=0:cells.getLength-1
                cell_node=cells.item(c);
                row_number=str2double(regexprep(char(cell_node.getAttribute('r')),'[A-Z]',''));
                if row_number<=h, continue; end
                original_style=char(cell_node.getAttribute('s'));
                if isempty(original_style), original_style='0'; end
                if ~isKey(top_styles,original_style)
                    style=formats.getElementsByTagName('xf').item(str2double(original_style)).cloneNode(true);
                    alignment=style.getElementsByTagName('alignment');
                    if alignment.getLength==0
                        alignment=styles.createElement('alignment'); style.appendChild(alignment);
                    else, alignment=alignment.item(0); end
                    alignment.setAttribute('vertical','top'); style.setAttribute('applyAlignment','1');
                    top_styles(original_style)=formats.getElementsByTagName('xf').getLength;
                    formats.appendChild(style);
                end
                cell_node.setAttribute('s',num2str(top_styles(original_style)));
            end
        end
        xmlwrite(file,doc);
    end
    formats.setAttribute('count',num2str(formats.getElementsByTagName('xf').getLength));
    xmlwrite(fullfile(folder,'xl','styles.xml'),styles);
    entries=dir(folder); names={entries.name}; names=names(~ismember(names,{'.','..'}));
    package=[tempname '.zip']; package_cleanup=onCleanup(@() delete_if_present(package));
    zip(package,names,folder); movefile(package,filename,'f');
end

function delete_if_present(file)
    if isfile(file), delete(file); end
end


