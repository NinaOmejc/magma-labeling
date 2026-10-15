function manifest = master_input_manifest(files)
% MASTER_INPUT_MANIFEST Hash original workbooks for reproducibility and immutability.
    files=sort(string(files(:))); hashes=strings(size(files)); bytes=zeros(size(files));
    for i=1:numel(files)
        fid=fopen(files(i),'rb');
        if fid<0, error('MAGMA:Metadata:MissingInput','Cannot read %s.',files(i)); end
        cleanup=onCleanup(@() fclose(fid));
        data=fread(fid,Inf,'*uint8'); bytes(i)=numel(data);
        digest=java.security.MessageDigest.getInstance('SHA-256');
        digest.update(typecast(data,'int8'));
        hash=typecast(digest.digest(),'uint8');
        hashes(i)=lower(string(reshape(dec2hex(hash,2)',1,[])));
        clear cleanup;
    end
    manifest=table(files,bytes,hashes,'VariableNames',{'source_file','bytes','sha256'});
end
