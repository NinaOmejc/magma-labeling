function timings = benchmark_one_recording(data, cycles, config, repetitions)
% BENCHMARK_ONE_RECORDING Time respiratory calculations without running MAGMA.
% Inputs are one recording's PREPROCESSED samples, saved cycles, and analysis
% config. No extraction, review GUI, cache/result writes, or export is called.
% First call includes MATLAB/JIT warm-up; use repetitions=3 for a warm median.
% Example: timings = benchmark_one_recording(data,saved.resp_cycles,saved.config,3);

    if nargin < 4, repetitions = 1; end
    validateattributes(repetitions,{'numeric'},{'scalar','integer','positive','finite'});
    validateattributes(data,{'numeric'},{'2d','nonempty'});
    if ~isfield(config,'recording_observations')
        config.recording_observations = recording_observation('default',config);
    end
    config.respiratory_artifact_state = respiratory_artifact_state(cycles,config,size(data,1));
    config.make_figs_visible = 'off'; % Suppress internal wavelet-library figures.
    session = get_session_reference_interval(size(data,1),config);
    names = ["Q23";"Guyot";"eAMI";"Phase offset";"Legacy coherence"];
    jobs = {@() compute_thoracic_respiratory_rhythmicity(data,cycles,config), ...
        @() compute_guyot_periodic_breathing(data,cycles,config), ...
        @() compute_eami_periodic_breathing(data,config), ...
        @() compute_respiratory_phase_offset_metrics(data,cycles,config), ...
        @() compute_respiratory_asynchrony_metrics(data,cycles,session,config)};
    seconds = nan(numel(jobs),repetitions);
    available = false(numel(jobs),1);
    for repeat = 1:repetitions
        for j = 1:numel(jobs)
            started = tic;
            result = jobs{j}();
            seconds(j,repeat) = toc(started);
            if isfield(result,'available'), available(j) = result.available;
            else, available(j) = result.valid_analysis; end
        end
    end
    timings = table(names,seconds(:,1),median(seconds,2),min(seconds,[],2),available, ...
        'VariableNames',{'stage','first_seconds','median_seconds','min_seconds','available'});
    fprintf('MATLAB %s | %s | %d samples at %g Hz | %d repetition(s)\n', ...
        version,computer,size(data,1),config.fs,repetitions);
    disp(timings);
    fprintf('Compute only: excludes loading, GUI interaction, figures, and MAT/HDF5 export.\n');
end
