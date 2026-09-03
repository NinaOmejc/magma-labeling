function canonical = canonicalize_label_names(names)
% canonicalize_label_names
% Map historical canonical label identities to the frozen v3 names without
% relying on historical column position. Unknown names are retained so the
% caller can reject or report them explicitly.

    canonical = cellstr(string(names));
    for i = 1:numel(canonical)
        key = char(string(canonical{i}));
        switch key
            case {'shallowB', 'shallow'}
                canonical{i} = 'shallow';
            case {'deepB', 'deep'}
                canonical{i} = 'deep';
            case {'slowB', 'slow'}
                canonical{i} = 'slow';
            case {'rapidB', 'rapid'}
                canonical{i} = 'rapid';
            case {'irregB', 'irregular'}
                canonical{i} = 'irregular';
            case 'apnea'
                canonical{i} = 'apnea';
            case 'sigh'
                canonical{i} = 'sigh';
            case {'CSR', 'csr'}
                canonical{i} = 'csr';
            case {'thorDomB', 'thoracic'}
                canonical{i} = 'thoracic';
            case {'asyncB', 'async'}
                canonical{i} = 'async';
            case 'desat'
                canonical{i} = 'desat';
        end
    end
end
