function atomic_save_mat(filename, payload)
% ATOMIC_SAVE_MAT Stage a MAT payload beside its destination before replacement.
    folder = fileparts(filename);
    ensure_output_directory(folder);
    staged = [tempname(folder) '.mat'];
    cleanup = onCleanup(@() remove_staged(staged));
    save(staged,'-struct','payload');
    [ok,message] = movefile(staged,filename,'f');
    if ~ok, error('MAGMA:Persistence:ReplaceFailed','Cannot replace %s: %s',filename,message); end
end

function remove_staged(filename)
    if isfile(filename), delete(filename); end
end
