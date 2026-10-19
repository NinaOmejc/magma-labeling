function save_result_fixture(filename, varargin)
% SAVE_RESULT_FIXTURE Write small synthetic results through the real boundary.
% Names refer to variables in the test caller, matching MATLAB save's syntax.
    if numel(varargin) == 1 && isstruct(varargin{1})
        internal = varargin{1};
    elseif numel(varargin) == 2 && strcmp(varargin{1},'-struct')
        internal = evalin('caller',varargin{2});
    else
        internal = struct();
        for k = 1:numel(varargin), internal.(varargin{k}) = evalin('caller',varargin{k}); end
    end
    if ~isfield(internal,'config'), internal.config = struct('fs',10); end
    if ~isfield(internal,'subject'), internal.subject = 999; end
    if ~isfield(internal,'measure'), internal.measure = 1; end
    if ~isfield(internal,'label_names'), internal.label_names = get_labels('short'); end
    if ~isfield(internal,'mask_automatic'), internal.mask_automatic = false(0,11); end
    recording_results('save',filename,internal);
end
