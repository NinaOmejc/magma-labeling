function tests = test_thoracic_rhythmicity_plot
% Synthetic plotting evidence only; no recordings or feature caches are edited.
    tests = functiontests(localfunctions);
end

function testDiagnosticOutputKeepsQ23AndReviewedLandmarksUnchanged(testCase)
    [config,data,cycles,cleanup] = fixture(); %#ok<ASGLU>
    before_data = data; before_cycles = cycles;
    expected = compute_thoracic_respiratory_rhythmicity(data,cycles,config);
    [actual,diagnostic] = compute_thoracic_respiratory_rhythmicity(data,cycles,config);
    verifyEqual(testCase,actual,expected);
    verifyEqual(testCase,data,before_data); verifyEqual(testCase,cycles,before_cycles);
    valid = isfinite(diagnostic.thoracic_values);
    candidates = find(valid);
    [~,i] = min(abs(diagnostic.thoracic_values(valid)-actual.thoracic_respiratory_rhythmicity));
    verifyEqual(testCase,diagnostic.representative_window,candidates(i));
    verifyEqual(testCase,median(diagnostic.thoracic_values(valid)),actual.thoracic_respiratory_rhythmicity);
    verifyEqual(testCase,diagnostic.representative.reference_frequency_hz,0.25,'AbsTol',1e-12);
    verifyEqual(testCase,diagnostic.representative.integration_band_hz,[0.20 0.30],'AbsTol',1e-12);
    verifyFalse(testCase,isfield(actual,'abdominal_values'));
    schema = get_phenotype_feature_schema(); verifyEqual(testCase,schema.n_features,24);
    verifyFalse(testCase,any(contains(schema.feature_names,'abdominal_concentration')));
end

function testSignalsShareWindowAndKeepOriginalUnitsAndColors(testCase)
    [config,data,cycles,cleanup] = fixture(); %#ok<ASGLU>
    [qc,diagnostic] = compute_thoracic_respiratory_rhythmicity(data,cycles,config);
    cache = fullfile(config.sub_results_path,config.sub_features_filename);
    save(cache,'cycles'); before = read_bytes(cache);
    fig = render(config,data,qc,diagnostic);
    cleanup_fig = onCleanup(@() delete(fig)); %#ok<NASGU>
    first = diagnostic.window_start_idx(diagnostic.representative_window);
    idx = first:first+round(qc.parameters.window_sec*config.fs)-1;
    thoracic = findall(fig,'Tag','ThoracicPreprocessedSignal');
    abdominal = findall(fig,'Tag','AbdominalPreprocessedSignal');
    verifyEqual(testCase,thoracic.XData,abdominal.XData);
    verifyEqual(testCase,thoracic.XData,(idx-1)/config.fs);
    verifyEqual(testCase,thoracic.YData,data(idx,4)');
    verifyEqual(testCase,abdominal.YData,data(idx,6)');
    verifyEqual(testCase,thoracic.Color,[0 0.447 0.741]);
    verifyEqual(testCase,abdominal.Color,[0.85 0.325 0.098]);
    verifyEqual(testCase,thoracic.Parent.XLim,abdominal.Parent.XLim);
    verifyNotEmpty(testCase,thoracic.Parent.YTick); verifyNotEmpty(testCase,abdominal.Parent.YTick);
    verifyEqual(testCase,read_bytes(cache),before);
end

function testSpectraUseOwnBandNormalizationAndSameAbdominalReference(testCase)
    [config,data,cycles,cleanup] = fixture(); %#ok<ASGLU>
    [qc,diagnostic] = compute_thoracic_respiratory_rhythmicity(data,cycles,config);
    fig = render(config,data,qc,diagnostic);
    cleanup_fig = onCleanup(@() delete(fig)); %#ok<NASGU>
    thoracic = findall(fig,'Tag','ThoracicNormalizedPSD');
    abdominal = findall(fig,'Tag','AbdominalNormalizedPSD');
    verifyEqual(testCase,thoracic.XData,abdominal.XData);
    verifyEqual(testCase,thoracic.Parent.XLim,[0.05 2]);
    verifyEqual(testCase,trapz(thoracic.XData,thoracic.YData),1,'AbsTol',1e-12);
    verifyEqual(testCase,trapz(abdominal.XData,abdominal.YData),1,'AbsTol',1e-12);
    marker = findall(fig,'Tag','AbdominalReferenceFrequency');
    verifyEqual(testCase,marker.Value,diagnostic.representative.reference_frequency_hz);
    band = findall(fig,'Tag','Q23IntegrationBand');
    verifyEqual(testCase,[min(band.XData) max(band.XData)],diagnostic.representative.integration_band_hz);
    legend_handle = findall(fig,'Type','legend');
    legend_labels = string([legend_handle.String]);
    verifyTrue(testCase,any(legend_labels=="Thoracic",'all'));
    verifyTrue(testCase,any(legend_labels=="Abdominal",'all'));
    verifyTrue(testCase,contains(join(string(thoracic.Parent.Title.String)), ...
        'normalization removes absolute power information'));
end

function testSummaryShowsWindowsMediansCoverageAndIndependentObservation(testCase)
    [config,data,cycles,cleanup] = fixture(); %#ok<ASGLU>
    config.recording_observations = recording_observation('default',config);
    config.recording_observations.status = 'observed';
    [qc,diagnostic] = compute_thoracic_respiratory_rhythmicity(data,cycles,config);
    fig = render(config,data,qc,diagnostic);
    cleanup_fig = onCleanup(@() delete(fig)); %#ok<NASGU>
    summary = findall(fig,'Tag','RhythmicitySummary');
    verifyEqual(testCase,summary.YLim,[0 1]);
    thoracic = findall(fig,'Tag','ThoracicWindowConcentration');
    abdominal = findall(fig,'Tag','AbdominalWindowConcentration');
    verifyEqual(testCase,thoracic.YData,diagnostic.thoracic_values');
    verifyEqual(testCase,abdominal.YData,diagnostic.abdominal_values');
    verifyEqual(testCase,findall(fig,'Tag','ThoracicMedian').Value,qc.thoracic_respiratory_rhythmicity);
    verifyEqual(testCase,findall(fig,'Tag','AbdominalMedian').Value,median(diagnostic.abdominal_values));
    verifyTrue(testCase,contains(join(string(summary.Title.String)), ...
        sprintf('%d/%d valid windows',qc.n_valid_windows,qc.n_windows)));
    verifyTrue(testCase,contains(join(string(summary.XLabel.String)),'(independent): observed'));
    verifyTrue(testCase,contains(join(string(summary.XLabel.String)),'no classification cutoff'));
end

function testArtifactExclusionsAndNoValidWindowDoNotInventScores(testCase)
    [config,data,cycles,cleanup] = fixture(); %#ok<ASGLU>
    cycles.artifact_intervals_idx = [1 400];
    [partial,evidence] = compute_thoracic_respiratory_rhythmicity(data,cycles,config);
    verifyEqual(testCase,partial.n_valid_windows,partial.n_windows-1);
    verifyTrue(testCase,isnan(evidence.thoracic_values(1)));
    verifyTrue(testCase,isnan(evidence.abdominal_values(1)));
    verifyTrue(testCase,isfinite(evidence.thoracic_values(evidence.representative_window)));
    cycles.artifact_intervals_idx = [1 size(data,1)];
    [qc,diagnostic] = compute_thoracic_respiratory_rhythmicity(data,cycles,config);
    verifyFalse(testCase,qc.available);
    verifyTrue(testCase,all(isnan(diagnostic.thoracic_values)));
    verifyTrue(testCase,all(isnan(diagnostic.abdominal_values)));
    fig = render(config,data,qc,diagnostic);
    cleanup_fig = onCleanup(@() delete(fig)); %#ok<NASGU>
    verifyNotEmpty(testCase,findall(fig,'Tag','AbdominalPreprocessedSignal'));
    verifyEmpty(testCase,findall(fig,'Tag','ThoracicNormalizedPSD'));
    verifyEmpty(testCase,findall(fig,'Tag','AbdominalNormalizedPSD'));
    verifyEmpty(testCase,findall(fig,'Tag','ThoracicMedian'));
    verifyEmpty(testCase,findall(fig,'Tag','AbdominalMedian'));
    spectra = findall(fig,'Tag','RhythmicitySpectra');
    strings = all_text(spectra);
    verifyTrue(testCase,any(contains(strings,'manually marked respiratory artifact')));
    summary = findall(fig,'Tag','RhythmicitySummary');
    verifyTrue(testCase,contains(join(string(summary.Title.String)),'Unavailable'));
end

function testUnavailableAbdominalSpectrumDoesNotChangeValidQ23(testCase)
    [config,data,cycles,cleanup] = fixture(); %#ok<ASGLU>
    data(:,6) = 5+(0:size(data,1)-1)'/config.fs;
    expected = compute_thoracic_respiratory_rhythmicity(data,cycles,config);
    [qc,diagnostic] = compute_thoracic_respiratory_rhythmicity(data,cycles,config);
    verifyEqual(testCase,qc,expected);
    verifyTrue(testCase,qc.available);
    % Roundoff after detrending can differ by window; an unavailable abdominal
    % spectrum must never remove an otherwise valid thoracic Q23 window.
    verifyTrue(testCase,any(isnan(diagnostic.abdominal_values)));
    verifyEqual(testCase,diagnostic.representative.abdominal_missing_reason, ...
        'abdominal_flatline_after_detrending');
end

function testMissingThoraxStillDisplaysAvailableAbdominalEvidence(testCase)
    [config,data,cycles,cleanup] = fixture(); %#ok<ASGLU>
    config.problems.missing_lung_belt = [config.subject config.measure];
    [qc,diagnostic] = compute_thoracic_respiratory_rhythmicity(data,cycles,config);
    fig = render(config,data,qc,diagnostic);
    cleanup_fig = onCleanup(@() delete(fig)); %#ok<NASGU>
    verifyFalse(testCase,qc.available);
    verifyEmpty(testCase,findall(fig,'Tag','ThoracicPreprocessedSignal'));
    verifyNotEmpty(testCase,findall(fig,'Tag','AbdominalPreprocessedSignal'));
    verifyEmpty(testCase,findall(fig,'Tag','ThoracicMedian'));
end

function fig = render(config,data,qc,diagnostic)
    plot_thoracic_rhythmicity_diagnostic(data,qc,diagnostic,config);
    fig = openfig(fullfile(config.sub_results_path,'Sub999_M1_thoracic_rhythmicity_diagnostic.fig'),'invisible');
    fig.Visible = 'off';
end

function [config,data,cycles,cleanup] = fixture()
    folder = tempname; mkdir(folder);
    cleanup = onCleanup(@() rmdir(folder,'s'));
    config = make_test_config(folder); config.fs = 20;
    config.PhenotypeSummary.do_plot = true; config.plot_format = 'fig';
    config.fig_width = 1400; config.fig_height = 1100;
    t = (0:7199)'/config.fs;
    data = zeros(numel(t),6);
    data(:,4) = 0.04+0.003*(sin(2*pi*0.25*t)+(t/360).^2.*sin(2*pi*0.7*t));
    data(:,6) = 5+8*sin(2*pi*0.25*t)+0.2*sin(2*pi*0.7*t);
    cycles = struct('diaph',struct('peak_idx',(21:80:numel(t))', ...
        'trough_overrides',[21 101 60]), ...
        'provenance',struct('review_status','manual_reviewed_edited'));
end

function bytes = read_bytes(filename)
    fid = fopen(filename,'rb'); cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    bytes = fread(fid,Inf,'*uint8');
end

function strings = all_text(parent)
    strings = string.empty(0,1);
    for item = findall(parent,'Type','text')'
        value = string(item.String);
        strings = [strings;value(:)]; %#ok<AGROW>
    end
end
