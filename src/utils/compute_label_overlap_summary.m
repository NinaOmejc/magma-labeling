function summary = compute_label_overlap_summary( ...
    mask, label_names, label_available, fs, assessable_mask)
% compute_label_overlap_summary
% Prespecified directional overlaps between elementary labels. This helper
% creates derived recording statistics, never new labels or mask columns.

    label_names = cellstr(string(label_names));
    label_available = logical(label_available(:)');
    if nargin < 5 || isempty(assessable_mask)
        assessable_mask = repmat(label_available, size(mask, 1), 1);
    end

    summary = struct();
    summary.version = 'prespecified_elementary_label_overlaps_v1';
    summary.rapid_deep = pair_summary('rapidB', 'deepB');
    summary.sigh_irregular = pair_summary('sigh', 'irregB');
    summary.apnea_desaturation = pair_summary('apnea', 'desat');
    summary.thoracic_dominance_asynchrony = pair_summary('thorDomB', 'asyncB');

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
