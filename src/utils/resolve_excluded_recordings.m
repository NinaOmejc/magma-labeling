function excluded = resolve_excluded_recordings(config)
% RESOLVE_EXCLUDED_RECORDINGS Validate the shared [subject, measurement] list.
% Missing/empty lists exclude nothing. Subject 0 supports synthetic recordings.

    excluded = zeros(0, 2);
    if ~isfield(config, 'exclude_recordings'), return; end
    value = config.exclude_recordings;
    if ~isnumeric(value) || ~isreal(value) || ~ismatrix(value)
        invalid_list();
    end
    if isempty(value), return; end
    if size(value, 2) ~= 2 || any(~isfinite(value(:))) || ...
            any(value(:) ~= fix(value(:))) || any(value(:, 1) < 0) || ...
            any(~ismember(value(:, 2), 1:4))
        invalid_list();
    end
    excluded = double(value);
end

function invalid_list()
    error('MAGMA:Config:InvalidExcludedRecordings', ...
        ['config.exclude_recordings must be empty or a numeric N-by-2 matrix ' ...
         'of finite integer [subject, measurement] IDs (subject >= 0, measurement in 1:4).']);
end
