function format_group_workbook(filename, tables)
% FORMAT_GROUP_WORKBOOK Add readable headers, filters, and frozen identifiers.
% Uses the XLSX package directly; no interactive Excel session is needed.
    folder = tempname;
    mkdir(folder);
    cleanup = onCleanup(@() rmdir(folder, 's'));
    unzip(filename, folder);
    style_path = fullfile(folder, 'xl', 'styles.xml');
    styles = xmlread(style_path);
    fonts = styles.getElementsByTagName('fonts').item(0);
    font_id = fonts.getElementsByTagName('font').getLength;
    font = styles.createElement('font');
    font.appendChild(styles.createElement('b'));
    color = styles.createElement('color'); color.setAttribute('rgb', 'FFFFFFFF');
    font.appendChild(color);
    fonts.appendChild(font); fonts.setAttribute('count', num2str(font_id+1));
    fills = styles.getElementsByTagName('fills').item(0);
    fill_id = fills.getElementsByTagName('fill').getLength;
    fill = styles.createElement('fill');
    pattern = styles.createElement('patternFill'); pattern.setAttribute('patternType', 'solid');
    color = styles.createElement('fgColor'); color.setAttribute('rgb', 'FF233955');
    pattern.appendChild(color); fill.appendChild(pattern);
    fills.appendChild(fill); fills.setAttribute('count', num2str(fill_id+1));
    formats = styles.getElementsByTagName('cellXfs').item(0);
    header_id = formats.getElementsByTagName('xf').getLength;
    header = formats.getElementsByTagName('xf').item(0).cloneNode(true);
    header.setAttribute('fontId', num2str(font_id)); header.setAttribute('fillId', num2str(fill_id));
    header.setAttribute('applyFont', '1'); header.setAttribute('applyFill', '1');
    alignment = styles.createElement('alignment');
    alignment.setAttribute('wrapText', '1'); alignment.setAttribute('vertical', 'center');
    alignment.setAttribute('horizontal', 'center');
    old = header.getElementsByTagName('alignment');
    if old.getLength > 0, header.removeChild(old.item(0)); end
    header.appendChild(alignment); formats.appendChild(header);
    formats.setAttribute('count', num2str(header_id+1)); xmlwrite(style_path, styles);

    for i = 1:numel(tables)
        T = tables{i};
        sheet_path = fullfile(folder, 'xl', 'worksheets', sprintf('sheet%d.xml', i));
        doc = xmlread(sheet_path); root = doc.getDocumentElement;
        sheet_data = doc.getElementsByTagName('sheetData').item(0);
        views = doc.getElementsByTagName('sheetViews');
        if views.getLength == 0
            views = doc.createElement('sheetViews');
            view = doc.createElement('sheetView'); view.setAttribute('workbookViewId', '0');
            views.appendChild(view);
            next = doc.getElementsByTagName('sheetFormatPr');
            if next.getLength > 0
                root.insertBefore(views, next.item(0));
            else
                root.insertBefore(views, sheet_data);
            end
        else
            view = views.item(0).getElementsByTagName('sheetView').item(0);
        end
        view.setAttribute('showGridLines', '0');
        pane = doc.createElement('pane'); pane.setAttribute('ySplit', '1');
        pane.setAttribute('topLeftCell', 'A2'); pane.setAttribute('state', 'frozen');
        pane.setAttribute('activePane', 'bottomLeft');
        if width(T) > 8
            pane.setAttribute('xSplit', '4'); pane.setAttribute('topLeftCell', 'E2');
            pane.setAttribute('activePane', 'bottomRight');
        end
        view.insertBefore(pane, view.getFirstChild);
        cols = doc.createElement('cols');
        for c = 1:max(1, width(T))
            w = 24;
            if width(T) > 0
                name = T.Properties.VariableNames{c};
                w = max(14, min(42, 0.7*numel(name)+4));
                values = T.(name);
                if isstring(values) || iscellstr(values)
                    lengths = strlength(string(values));
                    if ~isempty(lengths), w = max(w, min(58, max(lengths)+3)); end
                end
                if ismember(name, {'variable','feature_name','source_file','result_file'}), w = 42; end
                if strcmp(name, 'description'), w = 96; end
            end
            col = doc.createElement('col');
            col.setAttribute('min', num2str(c)); col.setAttribute('max', num2str(c));
            col.setAttribute('width', num2str(w)); col.setAttribute('customWidth', '1');
            cols.appendChild(col);
        end
        old_cols = doc.getElementsByTagName('cols');
        if old_cols.getLength > 0, root.removeChild(old_cols.item(0)); end
        root.insertBefore(cols, sheet_data);
        row = sheet_data.getElementsByTagName('row').item(0);
        row.setAttribute('ht', '48'); row.setAttribute('customHeight', '1');
        cells = row.getElementsByTagName('c');
        for c = 0:cells.getLength-1, cells.item(c).setAttribute('s', num2str(header_id)); end
        if width(T) > 0
            filter = doc.createElement('autoFilter');
            dimension = doc.getElementsByTagName('dimension').item(0);
            filter.setAttribute('ref', dimension.getAttribute('ref'));
            root.insertBefore(filter, sheet_data.getNextSibling);
        end
        xmlwrite(sheet_path, doc);
    end
    entries = dir(folder); names = {entries.name};
    names = names(~ismember(names, {'.', '..'}));
    package = [tempname '.zip'];
    package_cleanup = onCleanup(@() delete_if_present(package));
    zip(package, names, folder);
    movefile(package, filename, 'f');
end

function delete_if_present(path)
    if isfile(path), delete(path); end
end
