function summary = compute_label_overlap_summary( ...
    mask, label_names, label_available, fs, assessable_mask, events)
% COMPUTE_LABEL_OVERLAP_SUMMARY Quantify four prespecified label-pair overlaps.
% mask and optional assessable_mask are aligned Nsample-by-Nlabel matrices;
% label_available aligns with label_names and fs is hertz. summary contains a
% version plus rapid_deep, sigh_irregular, apnea_desaturation, and
% thoracic_dominance_asynchrony entries. Each entry stores label names,
% availability, overlap duration (s), directional fractions, and contiguous
% overlap-event count/duration summaries. When canonical events are supplied,
% each pair also records the fraction of assessable label-a events whose
% midpoint is label-b positive.

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
    events_supplied = nargin >= 6;
    if nargin < 6 || isempty(events)
        events = empty_events();
    elseif ~isstruct(events)
        error('MAGMA:Overlap:InvalidEvents', ...
            'events must be a canonical struct array.');
    end

    summary = struct();
    summary.version = 'prespecified_elementary_label_overlaps_v3';
    summary.rapid_deep = pair_summary('rapid', 'deep');
    summary.sigh_irregular = pair_summary('sigh', 'irregular');
    summary.apnea_desaturation = pair_summary('apnea', 'desat');
    summary.thoracic_dominance_asynchrony = pair_summary('thoracic', 'async');

    function out = pair_summary(a_name, b_name)
    % PAIR_SUMMARY Compute overlap only where both labels are assessable.

        ia = find(strcmp(label_names, a_name), 1);
        ib = find(strcmp(label_names, b_name), 1);
        out = struct('label_a', a_name, 'label_b', b_name, ...
            'available', false, 'overlap_duration_sec', NaN, ...
            'joint_assessable_duration_sec', NaN, ...
            'overlap_fraction_of_joint_assessable', NaN, ...
            'fraction_of_a_overlapped_by_b', NaN, ...
            'fraction_of_b_overlapped_by_a', NaN, ...
            'assessable_a_event_count', NaN, ...
            'fraction_of_a_events_with_b_at_midpoint', NaN, ...
            'overlap_event_count', NaN, ...
            'median_overlap_event_duration_sec', NaN, ...
            'max_overlap_event_duration_sec', NaN);
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
        out.joint_assessable_duration_sec = nnz(valid) / fs;
        out.overlap_fraction_of_joint_assessable = nnz(overlap) / nnz(valid);
        out.fraction_of_a_overlapped_by_b = directional_fraction(overlap, a);
        out.fraction_of_b_overlapped_by_a = directional_fraction(overlap, b);
        if events_supplied
            [out.assessable_a_event_count, ...
                out.fraction_of_a_events_with_b_at_midpoint] = ...
                event_midpoint_fraction(events, a_name, b, valid, fs);
        end
        overlap_durations = run_durations_sec(overlap, fs);
        out.overlap_event_count = numel(overlap_durations);
        if ~isempty(overlap_durations)
            out.median_overlap_event_duration_sec = median(overlap_durations);
            out.max_overlap_event_duration_sec = max(overlap_durations);
        end
    end
end

function [count, fraction] = event_midpoint_fraction( ...
    events, label, b_positive, jointly_assessable, fs)
% EVENT_MIDPOINT_FRACTION Evaluate canonical label events at their midpoint.
% Only events with a midpoint in the jointly assessable scope enter the
% denominator. An assessable pair with no such events is a valid zero.

    count = 0;
    fraction = 0;
    if isempty(events) || ~isfield(events, 'type')
        return;
    end
    types = canonicalize_label_names({events.type});
    selected = events(strcmp(types, label));
    positive_count = 0;
    for i = 1:numel(selected)
        midpoint = event_midpoint_index(selected(i), fs, ...
            numel(jointly_assessable));
        if ~isfinite(midpoint) || ~jointly_assessable(midpoint)
            continue;
        end
        count = count + 1;
        positive_count = positive_count + double(b_positive(midpoint));
    end
    if count > 0
        fraction = positive_count / count;
    end
end

function index = event_midpoint_index(event, fs, N)
% EVENT_MIDPOINT_INDEX Convert canonical indices/times to one master sample.

    index = NaN;
    if isfield(event, 'start_idx') && isfield(event, 'end_idx') && ...
            isfinite(event.start_idx) && isfinite(event.end_idx)
        index = round((double(event.start_idx) + double(event.end_idx)) / 2);
    elseif isfield(event, 'start_t') && isfield(event, 'end_t') && ...
            isfinite(event.start_t) && isfinite(event.end_t)
        index = round(((double(event.start_t) + double(event.end_t)) / 2) * fs) + 1;
    end
    if ~isfinite(index) || index < 1 || index > N
        index = NaN;
    end
end

function value = directional_fraction(overlap, reference)
% DIRECTIONAL_FRACTION Divide overlap samples by samples in a reference mask.
% Returns zero when the reference contains no true samples.

    denominator = nnz(reference);
    if denominator == 0
        value = 0;
    else
        value = nnz(overlap) / denominator;
    end
end

function durations = run_durations_sec(mask, fs)
% RUN_DURATIONS_SEC Return durations of contiguous true runs.

    padded = [false; logical(mask(:)); false];
    transitions = diff(padded);
    starts = find(transitions == 1);
    stops = find(transitions == -1) - 1;
    durations = (stops - starts + 1) / fs;
end
