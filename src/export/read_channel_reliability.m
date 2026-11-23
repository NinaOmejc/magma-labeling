function snapshot = read_channel_reliability(config, subject, measurement)
% READ_CHANNEL_RELIABILITY Freeze validated recording-level CSV rows for HDF5.
% config.HDF5.manual_channel_reliability_csv optionally selects the source.
% All original row strings and the source manifest are retained. Missing files,
% duplicate channels and unsupported statuses fail before an export is replaced.
% An explicit zero-row snapshot means unassessed, never confirmed clean.

    file = char(string(get_config_value(config, 'HDF5', ...
        'manual_channel_reliability_csv', ...
        'D:\Projects\MAGMA\data_analysis\features\qc\channel_reliability.csv')));
    [~, name, extension] = fileparts(file);
    if strcmpi([name extension], '5min_win_reliability.csv')
        error('MAGMA:HDF5:ManualQCSource', 'Five-minute QC is not recording-level manual QC.');
    end
    if ~isfile(file)
        error('MAGMA:HDF5:MissingManualQC', ...
            'Manual channel QC CSV not found: %s. Set config.HDF5.manual_channel_reliability_csv.', file);
    end
    before = master_input_manifest(string(file));
    options = detectImportOptions(file, 'TextType', 'string', 'VariableNamingRule', 'preserve');
    options = setvartype(options, options.VariableNames, 'string');
    options = setvaropts(options, options.VariableNames, ...
        'WhitespaceRule', 'preserve', 'TreatAsMissing', {});
    table_all = readtable(file, options);
    required = {'recording_id', 'signal', 'qc_status'};
    if ~all(ismember(required, table_all.Properties.VariableNames))
        error('MAGMA:HDF5:ManualQCColumns', 'Manual QC requires recording_id, signal and qc_status.');
    end
    for key = table_all.Properties.VariableNames
        values = table_all.(key{1});
        values(ismissing(values)) = "";
        table_all.(key{1}) = values;
    end
    recording_id = sprintf('Sub%d_M%d', subject, measurement);
    selected = table_all(table_all.recording_id == string(recording_id), :);
    if numel(unique(selected.signal)) ~= height(selected)
        error('MAGMA:HDF5:ManualQCConflict', 'Duplicate manual QC channels for %s.', recording_id);
    end
    if any(~ismember(selected.qc_status, ["usable", "weak", "unavailable", ""]))
        error('MAGMA:HDF5:ManualQCStatus', 'Unsupported manual QC status for %s.', recording_id);
    end
    if ismember('measurement', selected.Properties.VariableNames) && ...
            any(selected.measurement ~= string(measurement))
        error('MAGMA:HDF5:ManualQCIdentity', 'Manual QC measurement mismatch for %s.', recording_id);
    end
    after = master_input_manifest(string(file));
    if ~isequal(before.sha256, after.sha256)
        error('MAGMA:HDF5:ManualQCChanged', 'Manual QC source changed while reading: %s.', file);
    end
    rows = cell(height(selected), 1);
    for i = 1:height(selected)
        rows{i} = table2struct(selected(i, :));
    end
    snapshot = struct('schema_version', 'magma_manual_channel_reliability_v1', ...
        'recording_id', recording_id, 'scope', 'recording', 'authoritative', true, ...
        'source', table2struct(after), 'imported_at_utc', ...
        char(datetime('now', 'TimeZone', 'UTC', 'Format', "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")), ...
        'row_count', height(selected), 'rows', {rows});
end
