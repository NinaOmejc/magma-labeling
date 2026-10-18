function manifest = backup_recording_mat_files(config, destination)
% BACKUP_RECORDING_MAT_FILES Copy and verify selected recordings' MAT originals.
% Run before batch reanalysis. Destination must be fresh and outside all
% source recording folders. Restorable payloads include caches and review history.
    if isfolder(destination) || isfile(destination)
        error('MAGMA:Backup:DestinationExists','Choose a fresh backup directory: %s',destination);
    end
    destination = char(java.io.File(destination).getCanonicalPath());
    manifest = struct('subject',{},'measurement',{},'source',{},'backup',{},'verified',{});
    for subject = config.subjects(:)'
        for measurement = config.measurements(:)'
            source = fullfile(config.path_results_out,sprintf('Sub%d_M%d',subject,measurement));
            canonical = char(java.io.File(source).getCanonicalPath());
            if strcmpi(destination,canonical) || startsWith(lower(destination),[lower(canonical) filesep])
                error('MAGMA:Backup:NestedDestination','Backup must be outside recording folders.');
            end
            if ~isempty(dir(fullfile(source,'*_recording_observations.mat.pending.mat')))
                error('MAGMA:Backup:PendingObservationUpdate', ...
                    'Recover the interrupted observation update before backup: %s',source);
            end
            files = dir(fullfile(source,'*.mat'));
            for i = 1:numel(files)
                target_dir = fullfile(destination,sprintf('Sub%d_M%d',subject,measurement));
                ensure_output_directory(target_dir);
                original = fullfile(source,files(i).name);
                backup = fullfile(target_dir,files(i).name);
                [ok,message] = copyfile(original,backup);
                if ~ok, error('MAGMA:Backup:CopyFailed','%s',message); end
                if ~isequaln(load(original),load(backup))
                    error('MAGMA:Backup:VerificationFailed','Backup is not restorable: %s',original);
                end
                manifest(end+1) = struct('subject',subject,'measurement',measurement, ... %#ok<AGROW>
                    'source',original,'backup',backup,'verified',true);
            end
        end
    end
    if isempty(manifest)
        error('MAGMA:Backup:NoRecordingFiles','No recording MAT files were found; verify the output root.');
    end
    save(fullfile(destination,'backup_manifest.mat'),'manifest','config');
end
