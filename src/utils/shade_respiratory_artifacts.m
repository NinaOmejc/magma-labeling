function handles = shade_respiratory_artifacts(ax,ranges,fs,callback)
% SHADE_RESPIRATORY_ARTIFACTS Draw technical exclusions, separate from labels.
    if nargin < 4, callback = []; end
    handles = gobjects(0); limits = ylim(ax);
    for i = 1:size(ranges,1)
        t0 = (ranges(i,1)-1)/fs; t1 = ranges(i,2)/fs;
        h = patch(ax,[t0 t1 t1 t0],limits([1 1 2 2]),[0.85 0.35 0.12], ...
            'FaceAlpha',0.18,'EdgeColor','none','HandleVisibility','off', ...
            'Tag','respiratory_artifact','HitTest','off','PickableParts','none');
        if ~isempty(callback)
            set(h,'HitTest','on','PickableParts','all','ButtonDownFcn', ...
                @(~,event) callback(i,event));
        end
        handles(end+1,1) = h; %#ok<AGROW>
    end
    if ~isempty(handles), uistack(handles,'bottom'); end
end
