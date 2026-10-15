function id = master_subject_id(value)
% MASTER_SUBJECT_ID Documented aliases: numeric ID, SubN, or collaborator Sub_N.
    text = master_cell_text(value);
    token = regexp(char(text), '^(?:Sub_?)?(\d+)$', 'tokens', 'once', 'ignorecase');
    id = "";
    if ~isempty(token), id = "Sub" + string(str2double(token{1})); end
end
