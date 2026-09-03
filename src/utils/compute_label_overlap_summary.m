function summary = compute_label_overlap_summary( ...
    mask, label_names, label_available, fs, assessable_mask)
% compute_label_overlap_summary
% Prespecified directional overlaps between elementary labels. This helper
% creates derived recording statistics, never new labels or mask columns.

    if ~(isnumeric(mask) || islogical(mask)) || ~ismatrix(mask) || ~isreal(mask)
        error('MAGMA:Overlap:InvalidMaskType', ...
            'mask must be a real numeric or logical two-dimensional array.');
    end
    if any(~isfinite(double(mask(:)))) || any(~ismember(double(mask(:)), [0 1]))
        error('MAGMA:Overlap:InvalidMaskValues', ...
            'mask values must be finite and binary.');
    end
    if ~(iscellstr(label_names) || isstring(label_names) || ischar(label_names))
        error('MAGMA:Overlap:InvalidLabelNames', ...
            'label_names must be text labels.');
    end
    label_names = cellstr(string(label_names));
    if size(mask, 2) ~= numel(label_names)
        error('MAGMA:Overlap:LabelAlignment', ...
            'size(mask,2) must equal numel(label_names).');
    end
    if numel(unique(label_names)) ~= numel(label_names)
        error('MAGMA:Overlap:DuplicateLabelNames', ...
            'label_names must not contain duplicates.');
    end
    if ~(isnumeric(label_available) || islogical(label_available)) || ...
            ~isvector(label_available) || ...
            any(~isfinite(double(label_available(:)))) || ...
            any(~ismember(double(label_available(:)), [0 1]))
        error('MAGMA:Overlap:InvalidAvailability', ...
            'label_available must be a finite binary vector.');
    end
    if numel(label_available) ~= numel(label_names)
        error('MAGMA:Overlap:AvailabilityAlignment', ...
            'numel(label_available) must equal numel(label_names).');
    end
    if ~isnumeric(fs) || ~isscalar(fs) || ~isfinite(fs) || fs <= 0
        error('MAGMA:Overlap:InvalidSamplingRate', ...
            'fs must be a finite positive numeric scalar.');
    end
    required = {'rapid', 'deep', 'sigh', 'irregular', ...
        'apnea', 'desat', 'thoracic', 'async'};
    missing = required(~ismember(required, label_names));
    if ~isempty(missing)
        error('MAGMA:Overlap:MissingRequiredLabel', ...
            'Required overlap label(s) missing: %s.', strjoin(missing, ', '));
    end

    mask = logical(mask);
    label_available = logical(label_available(:)');
    if nargin < 5 || isempty(assessable_mask)
        assessable_mask = repmat(label_available, size(mask, 1), 1);
    end
    if ~(isnumeric(assessable_mask) || islogical(assessable_mask)) || ...
            ~isreal(assessable_mask)
        error('MAGMA:Overlap:InvalidAssessableMaskType', ...
            'assessable_mask must be a real numeric or logical array.');
    end
    if ~isequal(size(assessable_mask), size(mask))
        error('MAGMA:Overlap:AssessableMaskSize', ...
            'assessable_mask must have the same dimensions as mask.');
    end
    if any(~isfinite(double(assessable_mask(:)))) || ...
            any(~ismember(double(assessable_mask(:)), [0 1]))
        error('MAGMA:Overlap:InvalidAssessableMaskValues', ...
            'assessable_mask values must be finite and binary.');
    end
    assessable_mask = logical(assessable_mask);

    summary = struct();
    summary.version = 'prespecified_elementary_label_overlaps_v1';
    summary.rapid_deep = pair_summary('rapid', 'deep');
    summary.sigh_irregular = pair_summary('sigh', 'irregular');
    summary.apnea_desaturation = pair_summary('apnea', 'desat');
    summary.thoracic_dominance_asynchrony = pair_summary('thoracic', 'async');

    function out = pair_summary(a_name, b_name)
        ia = find(strcmp(label_names, a_name), 1);
        ib = find(strcmp(label_names, b_name), 1);
        out = struct('label_a', a_name, 'label_b', b_name, ...
            'available', false, 'overlap_duration_sec', NaN, ...
            'fraction_of_a_overlapped_by_b', NaN, ...
            'fraction_of_b_overlapped_by_a', NaN);
        if isempty(ia) || isempty(ib) || ~label_available(ia) || ...
                ~label_available(ib)
            return;
        end
        valid = assessable_mask(:, ia) & assessable_mask(:, ib);
        if ~any(valid)
            return;
        end
        a = logical(mask(:, ia)) & valid;
        b = logical(mask(:, ib)) & valid;
        overlap = a & b;
        out.available = true;
        out.overlap_duration_sec = nnz(overlap) / fs;
        out.fraction_of_a_overlapped_by_b = directional_fraction(overlap, a);
        out.fraction_of_b_overlapped_by_a = directional_fraction(overlap, b);
    end
end

function value = directional_fraction(overlap, reference)
    denominator = nnz(reference);
    if denominator == 0
        value = 0;
    else
        value = nnz(overlap) / denominator;
    end
end
