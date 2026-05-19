function group_table = build_group_label_table(config_or_results_path)
% build_group_label_table
% Join saved subject label files into one group-level CSV summary.
%
% Usage:
%   build_group_label_table()
%   build_group_label_table(config)
%   build_group_label_table('D:\Projects\MAGMA\data_analyis\disorder_classification')

    if nargin < 1 || isempty(config_or_results_path)
        config = get_config();
        results_path = config.path_results_out;
    elseif isstruct(config_or_results_path)
        config = config_or_results_path;
        results_path = config.path_results_out;
    else
        config = struct();
        results_path = char(config_or_results_path);
    end

    files = dir(fullfile(results_path, 'Sub*_M*', '*_labels.mat'));
    out_dir = fullfile(results_path, 'group_analysis');
    if ~isfolder(out_dir)
        mkdir(out_dir);
    end

    rows = {};
    all_fields = {};
    for i = 1:numel(files)
        label_file = fullfile(files(i).folder, files(i).name);
        row = label_file_to_summary_row(label_file, config);
        rows{end+1} = row; %#ok<AGROW>
        all_fields = union(all_fields, fieldnames(row), 'stable');
    end

    if isempty(rows)
        group_table = table();
    else
        rows = fill_missing_fields(rows, all_fields);
        group_table = struct2table([rows{:}]);
    end

    out_csv = fullfile(out_dir, 'group_label_summary.csv');
    out_mat = fullfile(out_dir, 'group_label_summary.mat');
    writetable(group_table, out_csv);
    save(out_mat, 'group_table');
    fprintf('Saved group label summary: %s\n', out_csv);
end

function row = label_file_to_summary_row(label_file, config)
    loaded = load(label_file);

    row = struct();
    row.label_file = label_file;
    row.subject = get_loaded_value(loaded, 'subject', nan);
    row.condition = get_loaded_value(loaded, 'condition', nan);

    if isfield(loaded, 'mask') && isfield(loaded, 'label_names')
        fs = get_results_fs(loaded, config);
        duration_sec = size(loaded.mask, 1) / fs;
        row.duration_sec = duration_sec;
        for j = 1:numel(loaded.label_names)
            label = matlab.lang.makeValidName(loaded.label_names{j});
            label_samples = nnz(loaded.mask(:,j) ~= 0);
            row.(['label_' label '_duration_sec']) = label_samples / fs;
            row.(['label_' label '_fraction']) = (label_samples / fs) / duration_sec;
        end
    else
        row.duration_sec = nan;
    end

    if isfield(loaded, 'events')
        row = add_event_counts(row, loaded.events);
    end

    if isfield(loaded, 'diagnostic_signals')
        row = add_diagnostic_summaries(row, loaded.diagnostic_signals);
    end
end

function value = get_loaded_value(loaded, field_name, default_value)
    if isfield(loaded, field_name)
        value = loaded.(field_name);
    else
        value = default_value;
    end
end

function fs = get_results_fs(loaded, config)
    fs = nan;
    if isfield(loaded, 'config') && isfield(loaded.config, 'new_fs')
        fs = loaded.config.new_fs;
    elseif isfield(loaded, 'config') && isfield(loaded.config, 'fs')
        fs = loaded.config.fs;
    elseif isfield(config, 'new_fs')
        fs = config.new_fs;
    elseif isfield(config, 'fs')
        fs = config.fs;
    end
    if ~isfinite(fs) || fs <= 0
        fs = 1;
    end
end

function row = add_event_counts(row, events)
    if isempty(events)
        return;
    end

    event_types = unique({events.type}, 'stable');
    for i = 1:numel(event_types)
        label = matlab.lang.makeValidName(event_types{i});
        row.(['events_' label '_count']) = sum(strcmp({events.type}, event_types{i}));
    end

    if isfield(events, 'subtype')
        subtypes = {events.subtype};
        subtypes = subtypes(~cellfun(@isempty, subtypes));
        subtypes = unique(subtypes, 'stable');
        for i = 1:numel(subtypes)
            label = matlab.lang.makeValidName(subtypes{i});
            row.(['subtype_' label '_count']) = sum(strcmp({events.subtype}, subtypes{i}));
        end
    end
end

function row = add_diagnostic_summaries(row, diagnostic_signals)
    names = fieldnames(diagnostic_signals);
    for i = 1:numel(names)
        name = names{i};
        if strcmp(name, 'time_sec')
            continue;
        end

        x = diagnostic_signals.(name);
        if ~isnumeric(x)
            continue;
        end

        col = ['diagnostic_' matlab.lang.makeValidName(name)];
        if isscalar(x)
            row.(col) = x;
        else
            x = x(:);
            x = x(isfinite(x));
            if isempty(x)
                row.([col '_mean']) = nan;
                row.([col '_median']) = nan;
                row.([col '_p10']) = nan;
                row.([col '_p90']) = nan;
            else
                row.([col '_mean']) = mean(x, 'omitnan');
                row.([col '_median']) = median(x, 'omitnan');
                row.([col '_p10']) = prctile(x, 10);
                row.([col '_p90']) = prctile(x, 90);
            end
        end
    end
end

function rows = fill_missing_fields(rows, all_fields)
    for i = 1:numel(rows)
        for j = 1:numel(all_fields)
            name = all_fields{j};
            if ~isfield(rows{i}, name)
                rows{i}.(name) = missing_value_for_field(name);
            end
        end
        rows{i} = orderfields(rows{i}, all_fields);
    end
end

function value = missing_value_for_field(name)
    if strcmp(name, 'label_file')
        value = '';
    else
        value = nan;
    end
end
