function ensure_output_directory(folder)
% ENSURE_OUTPUT_DIRECTORY Create an output directory and verify file writes.
% Uses a fresh temporary file; never opens or replaces an analysis output.

    if ~(ischar(folder) && isrow(folder) || isstring(folder) && isscalar(folder)) || ...
            strlength(string(folder)) == 0
        error('MAGMA:Output:InvalidDirectory', ...
            'Output directory must be a nonempty character vector or string scalar.');
    end
    folder = char(folder);
    if ~isfolder(folder)
        [ok, message, message_id] = mkdir(folder);
        if ~ok
            error('MAGMA:Output:CreateDirectoryFailed', ...
                'Cannot create output directory "%s": %s (%s)', ...
                folder, message, message_id);
        end
    end
    probe = tempname(folder);
    [fid, message] = fopen(probe, 'w');
    if fid < 0
        error('MAGMA:Output:DirectoryNotWritable', ...
            'Cannot create a file in output directory "%s": %s', folder, message);
    end
    cleanup = onCleanup(@() cleanup_probe(fid, probe));
    count = fwrite(fid, uint8(1), 'uint8');
    status = fclose(fid);
    if count ~= 1 || status ~= 0
        error('MAGMA:Output:DirectoryNotWritable', ...
            'Cannot write/close a file in output directory "%s".', folder);
    end
end

function cleanup_probe(fid, probe)
    if strcmp(fopen(fid), probe), fclose(fid); end
    if isfile(probe), delete(probe); end
end
