function name = master_source_column(source, original)
% MASTER_SOURCE_COLUMN Resolve an explicitly configured original header.
    index = find(source.mapping.original_name == string(original));
    if strlength(string(original))==0, name = ''; return; end
    if numel(index)~=1
        error('MAGMA:Metadata:Schema','Expected exactly one column "%s" in %s/%s.', ...
            original,source.spec.source_id,source.spec.sheet);
    end
    name = char(source.mapping.output_column(index));
end
