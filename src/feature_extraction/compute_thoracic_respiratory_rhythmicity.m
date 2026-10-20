function [qc, diagnostic] = compute_thoracic_respiratory_rhythmicity(data, cycles, config)
% COMPUTE_THORACIC_RESPIRATORY_RHYTHMICITY Exploratory RIP spectral concentration.
% Pure calculation: no cache access/writes, peak extraction, or signal changes.
% MAGMA adaptation, not Robles-Rubio et al.'s published NPP metric:
% https://doi.org/10.1371/journal.pone.0238402
% Optional diagnostic evidence is transient plotting data, not phenotype/cache state.
    diagnostic = struct('window_start_idx',[],'thoracic_values',[], ...
        'abdominal_values',[],'reference_frequency_hz',[],'window_reasons',{{}}, ...
        'representative_window',[],'representative',struct());
    collect_diagnostic = nargout > 1;
    p = struct('window_sec',120,'overlap_fraction',0.5,'analysis_fs',10, ...
        'power_band_hz',[0.05 2],'tolerance_min_hz',0.03,'tolerance_fraction',0.2, ...
        'welch_segment_sec',40,'welch_overlap_fraction',0.5, ...
        'min_finite_fraction',0.95,'max_gap_sec',1,'artifact_mad_multiplier',20, ...
        'min_reference_intervals',6,'min_reference_coverage',0.7, ...
        'min_valid_ibi_fraction',0.8,'max_reference_relative_iqr',0.5);
    qc = struct('method','MAGMA abdominal-referenced thoracic Welch concentration', ...
        'version','thoracic_respiratory_rhythmicity_v1', ...
        'thoracic_respiratory_rhythmicity',NaN,'available',false, ...
        'missing_reason','not_computed','n_windows',0,'n_valid_windows',0, ...
        'valid_window_fraction',0,'valid_coverage_fraction',0, ...
        'parameters',p,'reference_method','median reciprocal abdominal peak interval', ...
        'reference_landmark_provenance','unknown','analysis_observation_revision',NaN, ...
        'scope','recording','window_rejection_counts',struct());
    if isfield(config,'recording_observations')
        qc.analysis_observation_revision = config.recording_observations.revision;
    end
    if is_lung_belt_ignored(config)
        qc.missing_reason = 'thoracic_belt_technically_missing'; return;
    end
    resolved = resolve_signal_channels(config);
    il = resolved.channels.lungs_idx; ia = resolved.channels.diaph_idx;
    if isempty(il) || il > size(data,2)
        qc.missing_reason = 'thoracic_channel_missing'; return;
    end
    if isempty(ia) || ia > size(data,2)
        qc.missing_reason = 'abdominal_reference_channel_missing'; return;
    end
    fs = config.fs;
    if ~isscalar(fs) || ~isfinite(fs) || fs <= 4
        qc.missing_reason = 'sampling_rate_too_low'; return;
    end
    if ~isfield(cycles,'diaph') || ~isfield(cycles.diaph,'peak_idx')
        qc.missing_reason = 'insufficient_abdominal_reference'; return;
    end
    peaks = double(cycles.diaph.peak_idx(:));
    if numel(peaks) < p.min_reference_intervals+1 || ...
            any(~isfinite(peaks) | peaks ~= fix(peaks) | peaks < 1 | peaks > size(data,1)) || any(diff(peaks)<=0)
        qc.missing_reason = 'insufficient_abdominal_reference'; return;
    end
    if isfield(cycles,'provenance') && isfield(cycles.provenance,'review_status')
        qc.reference_landmark_provenance = cycles.provenance.review_status;
    end
    artifacts = respiratory_artifact_state(cycles,config,size(data,1));
    n = round(p.window_sec*fs); step = round(n*(1-p.overlap_fraction));
    starts = 1:step:(size(data,1)-n+1);
    qc.n_windows = numel(starts);
    if isempty(starts), qc.missing_reason = 'recording_shorter_than_window'; return; end
    % Recording-invariant setup; keep the original resample/Welch operations.
    reference.left = peaks(1:end-1); reference.right = peaks(2:end);
    reference.ibi = (reference.right-reference.left)/fs;
    reference.frequency = 1./reference.ibi;
    reference.valid = reference.ibi >= 1/p.power_band_hz(2) & ...
        reference.ibi <= 1/p.power_band_hz(1);
    spectral.fs = min(fs,p.analysis_fs);
    [spectral.up,spectral.down] = rat(spectral.fs/fs,1e-10);
    segment = min(n,round(p.welch_segment_sec*spectral.fs));
    spectral.window = hamming(segment);
    spectral.overlap = floor(segment*p.welch_overlap_fraction);
    spectral.nfft = max(512,2^nextpow2(4*segment));
    clean_windows = respiratory_artifact_window_valid( ...
        artifacts.evidence_intervals_idx, ...
        (starts+n-2)/fs,(n-1)/fs,fs);
    values = nan(size(starts)); reasons = cell(size(starts));
    if collect_diagnostic
        diagnostic.window_start_idx = starts(:);
        diagnostic.abdominal_values = nan(numel(starts),1);
        diagnostic.reference_frequency_hz = nan(numel(starts),1);
    end
    valid_time = false(size(data,1),1);
    for w = 1:numel(starts)
        idx = starts(w):starts(w)+n-1;
        if ~clean_windows(w)
            reasons{w} = 'manually_marked_respiratory_artifact';
        elseif collect_diagnostic
            [values(w),reasons{w},detail] = window_value( ...
                data(idx,il),data(idx,ia),reference,idx(1),n,fs,p,spectral);
            diagnostic.abdominal_values(w) = detail.abdominal_value;
            diagnostic.reference_frequency_hz(w) = detail.reference_frequency_hz;
        else
            [values(w),reasons{w}] = window_value( ...
                data(idx,il),data(idx,ia),reference,idx(1),n,fs,p,spectral);
        end
        if isfinite(values(w)), valid_time(idx) = true; end
        if ~isempty(reasons{w})
            key = reasons{w};
            if ~isfield(qc.window_rejection_counts,key), qc.window_rejection_counts.(key) = 0; end
            qc.window_rejection_counts.(key) = qc.window_rejection_counts.(key)+1;
        end
    end
    valid = isfinite(values);
    qc.n_valid_windows = nnz(valid);
    qc.valid_window_fraction = mean(valid);
    qc.valid_coverage_fraction = nnz(valid_time)/size(data,1);
    if any(valid)
        qc.thoracic_respiratory_rhythmicity = median(values(valid));
        qc.available = true; qc.missing_reason = '';
    else
        names = fieldnames(qc.window_rejection_counts);
        counts = cellfun(@(name) qc.window_rejection_counts.(name),names);
        [~,i] = max(counts); qc.missing_reason = names{i};
    end
    if collect_diagnostic
        diagnostic.thoracic_values = values(:);
        diagnostic.window_reasons = reasons(:);
        if any(valid)
            candidates = find(valid);
            [~,nearest] = min(abs(values(valid)-qc.thoracic_respiratory_rhythmicity));
            w = candidates(nearest);
            diagnostic.representative_window = w;
            idx = starts(w):starts(w)+n-1;
            [~,~,diagnostic.representative] = window_value( ...
                data(idx,il),data(idx,ia),reference,idx(1),n,fs,p,spectral);
        end
    end
end

function [q,reason,detail] = window_value(thoracic,abdominal,reference,start,n,fs,p,spectral)
    q = NaN;
    detail = struct('abdominal_value',NaN,'reference_frequency_hz',NaN, ...
        'integration_band_hz',[],'frequency_hz',[], ...
        'thoracic_normalized_psd',[],'abdominal_normalized_psd',[], ...
        'abdominal_missing_reason','no_valid_q23_window');
    [x,reason] = usable_trace(thoracic,fs,p,'thoracic');
    if ~isempty(reason), return; end
    [y,reason] = usable_trace(abdominal,fs,p,'abdominal');
    if ~isempty(reason), return; end
    overlap = max(0,min(reference.right,start+n)-max(reference.left,start));
    candidates = overlap > 0;
    good = candidates & reference.valid;
    if nnz(good) < p.min_reference_intervals || ...
            nnz(good)/max(1,nnz(candidates)) < p.min_valid_ibi_fraction || ...
            sum(overlap(good))/n < p.min_reference_coverage
        reason = 'insufficient_abdominal_reference'; return;
    end
    frequencies = reference.frequency(good);
    f0 = median(frequencies);
    if iqr(frequencies)/f0 > p.max_reference_relative_iqr
        reason = 'unstable_abdominal_reference'; return;
    end
    [q,reason,thoracic_psd,f,near] = spectral_concentration(x,f0,fs,p,spectral,'thoracic');
    if nargout < 3 || ~isempty(reason), return; end
    [detail.abdominal_value,detail.abdominal_missing_reason,abdominal_psd] = ...
        spectral_concentration(y,f0,fs,p,spectral,'abdominal');
    detail.reference_frequency_hz = f0;
    detail.integration_band_hz = near;
    detail.frequency_hz = f;
    detail.thoracic_normalized_psd = thoracic_psd;
    detail.abdominal_normalized_psd = abdominal_psd;
end

function [q,reason,normalized_psd,f,near] = spectral_concentration(x,f0,fs,p,spectral,belt)
% SPECTRAL_CONCENTRATION Same detrending, Welch and band integration for either belt.
    q = NaN; normalized_psd = []; f = []; near = [];
    magnitude = max(abs(x));
    x = detrend(x,'linear');
    if max(abs(x)) <= 10*eps(magnitude)
        reason = [belt '_flatline_after_detrending']; return;
    end
    if spectral.fs ~= fs
        x = resample(x,spectral.up,spectral.down); % Same FIR anti-alias filter, per window.
    end
    [psd,f] = pwelch(x,spectral.window,spectral.overlap,spectral.nfft,spectral.fs);
    total = band_power(psd,f,p.power_band_hz);
    tolerance = max(p.tolerance_min_hz,p.tolerance_fraction*f0);
    near = [max(p.power_band_hz(1),f0-tolerance),min(p.power_band_hz(2),f0+tolerance)];
    if ~isfinite(total) || total <= realmin
        reason = [belt '_zero_band_power']; return;
    end
    q = max(0,min(1,band_power(psd,f,near)/total));
    normalized_psd = psd/total;
    reason = '';
end

function [x,reason] = usable_trace(x,fs,p,belt)
    x = double(x(:)); reason = '';
    finite = isfinite(x);
    edges = diff([false; ~finite; false]);
    gaps = find(edges==-1)-find(edges==1);
    if mean(finite) < p.min_finite_fraction || any(gaps > p.max_gap_sec*fs)
        reason = [belt '_insufficient_finite_coverage']; return;
    end
    % Only short isolated gaps are interpolated; longer gaps reject the window.
    if any(~finite)
        x(~finite) = interp1(find(finite),x(finite),find(~finite),'linear','extrap');
    end
    centered = x-median(x);
    if max(abs(centered)) <= 10*eps(max(abs(x)))
        reason = [belt '_flatline']; return;
    end
    scale = 1.4826*median(abs(centered));
    if scale == 0 || max(abs(centered)) > p.artifact_mad_multiplier*scale
        reason = [belt '_transient_artifact']; return;
    end
end

function power = band_power(psd,f,band)
    inside = f > band(1) & f < band(2);
    query = [band(1); f(inside); band(2)];
    power = trapz(query,interp1(f,psd,query,'linear'));
end
