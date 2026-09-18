function analysis_id = create_analysis_id(config)
% CREATE_ANALYSIS_ID Build a compact recording/run identifier for provenance.

    timestamp = char(datetime('now', 'Format', 'yyyyMMdd''T''HHmmss'));
    commit = 'nogit';
    source_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    command = sprintf('git -C "%s" rev-parse --short HEAD', source_root);
    [status, output] = system(command);
    if status == 0 && ~isempty(strtrim(output))
        commit = regexprep(strtrim(output), '[^A-Za-z0-9._-]', '');
    end
    analysis_id = sprintf('Sub%d_M%d_%s_%s', ...
        config.subject, config.measure, timestamp, commit);
end
