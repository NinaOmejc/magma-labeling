function [t, y] = load_group_diagnostic_trace(label_file, spec)
% LOAD_GROUP_DIAGNOSTIC_TRACE Read one authoritative saved trace and its time.
% spec supplies source/field_path and time_source/time_path. Empty or missing
% values return empty outputs. Nonempty length mismatches are visible warnings,
% never silently truncated.

    t = [];
    y = [];
    requested = unique({spec.source, spec.time_source}, 'stable');
    loaded = load(label_file, requested{:});
    if ~isfield(loaded, spec.source) || ~isfield(loaded, spec.time_source)
        return;
    end

    t = nested_value(loaded.(spec.time_source), spec.time_path);
    y = nested_value(loaded.(spec.source), spec.field_path);
    if ~(isnumeric(t) || islogical(t)) || ~(isnumeric(y) || islogical(y))
        t = [];
        y = [];
        return;
    end
    t = double(t(:));
    y = double(y(:));
    if isempty(t) || isempty(y)
        t = [];
        y = [];
        return;
    end
    if numel(t) ~= numel(y)
        warning('MAGMA:Group:TraceLengthMismatch', ...
            ['Skipping trace %s from %s: authoritative time path %s has %d ' ...
             'values but the trace has %d.'], ...
            spec.field_path, label_file, spec.time_path, numel(t), numel(y));
        t = [];
        y = [];
        return;
    end

    valid = isfinite(t) & isfinite(y);
    t = t(valid);
    y = y(valid);
    [t, idx] = unique(t, 'stable');
    y = y(idx);
end

function value = nested_value(source, path)
% NESTED_VALUE Resolve a dot-separated path through scalar structs.

    value = [];
    parts = strsplit(path, '.');
    for i = 1:numel(parts)
        if ~isstruct(source) || ~isscalar(source) || ~isfield(source, parts{i})
            return;
        end
        source = source.(parts{i});
    end
    value = source;
end
