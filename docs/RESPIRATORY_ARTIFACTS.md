# Rechecking respiratory features and marking artifacts

Use this workflow for an existing recording whose breath landmarks have
already been reviewed. Compatible version-9 caches retain every saved
peak, trough, trough override, amplitude method and polarity alignment.
Missing artifact fields in older compatible caches mean empty intervals.
An incompatible cache raises an error during recheck without regenerating it.
Keep `config.resp.amp_method` equal to the saved cache method when reopening.

```matlab
% Keep your machine's existing input/output paths and recording selection.
config.execution.mode = 'analyze';
config.execution.selected_labels = {};
config.overwrite_results = true;
config.overwrite_features = false;
config.resp.manual_control = true;
config.resp.recheck_cached = true;
run_magma(config);
```

Before reviewing each existing cache, MAGMA saves and verifies a restorable
copy in that recording's `feature_review_backups/` folder and prints its
filename. Keep a separate backup of the recording's results and manual-label
checkpoint as well before a production rerun. For multiple recordings,
`backup_recording_mat_files(config, fresh_backup_directory)` copies and
verifies all selected recording MAT files. Do not use `overwrite_features=true`
for this workflow. Set `recheck_cached=false` again after finishing.

The feature GUI has **Edit peaks**, **Move trough**, and **Mark artifact**.
In Mark artifact, drag on one belt to mark its technically unreliable region.
Click the orange shading away from the trace to remove that interval. Lungs
and diaphragm are independent; overlapping or immediately adjacent ranges
merge and endpoints clamp to the recording. The original waveform and all
landmarks, including those inside marked artifacts, remain saved.

**Reviewed** validates and commits the feature edits. Closing X cancels the
whole session, leaves the original cache byte-for-byte unchanged, and skips
that recording's reanalysis. A confirmed edit is saved before downstream
analysis, so it survives a subsequent interruption. After acceptance MAGMA
recomputes respiratory reference/evidence, labels, availability, and phenotype
features from the saved cycles. No detector definitions or physiological
thresholds are changed. Original automatic results remain in place until the
new analysis is saved. Existing manual event edits, review history, and
previous phenotype snapshots are retained.

The manual label editor shows the same artifacts as noneditable orange
shading. Its label editing and review coverage remain separate. If an artifact
is discovered there, cancel/finish label review and use the feature recheck
workflow above. `review_only` does not recalculate automatic evidence.

## Stored schema and interrupted reruns

The feature cache version remains **9**. These optional fields are additive:

- `resp_cycles.lungs.artifact_intervals_idx` and
  `resp_cycles.diaph.artifact_intervals_idx`: N-by-2 inclusive, one-based
  integer `[start_idx end_idx]` sample ranges; empty means no marked artifacts.
- `resp_cycles.artifact_annotation`: `version`, `revision`, UTC `timestamp`,
  `reviewer_role`, `annotation_source`, `scope`, and `pending_reanalysis`.
- Top-level `respiratory_artifact_state`: compact annotation metadata,
  `subject` + `measurement`, raw per-belt ranges (`lungs`, `diaph`), and
  derived contaminated breath/IBI support (`lungs_evidence`, `diaph_evidence`).

The revision increments on a confirmed artifact **or landmark** change, so
late peak/trough corrections also invalidate derived outputs. Previously
recorded review provenance is retained. No-change acceptance does not bump
the revision. Cache updates are staged beside the destination and then
replaced, preserving other saved top-level variables. Simultaneous changes
to the thoracic observation use its existing transaction/checkpoint handling.

The feature cache is authoritative. Existing `results.mat` receives the
current compact `respiratory_artifact_state` immediately after a committed
feature review. Its `analysis_respiratory_artifact_revision` records the
revision used for automatic analysis (legacy files imply 0). Labels and
historical reviews are not rewritten by this metadata update. Pending state
or unequal current/analysis revisions indicates that a full rerun is needed.
A selective rerun is rejected while feature reanalysis is pending. Pending
state clears only after current-revision MAT and enabled HDF5 outputs save
successfully. If an output mirror cannot be written, the error propagates;
the saved cache revision remains authoritative and pending for a retry.

Sample assessability metadata uses `label_assessability_v3`.

HDF5 schema **v18** retains per-belt ranges and annotation metadata below
`/breaths`, and adds:

- `/observations/respiratory_artifacts_json`: current compact state.
- `/observations/analysis_respiratory_artifact_revision`: automatic-analysis
  revision. The former can change without rewriting previous automatic data.

Group recording summaries expose current revision, analysis revision, and
pending reanalysis. Phenotype summaries display a pending warning. Review-only
uses the previous automatic analysis masks and values until a full rerun.

## Evidence semantics

Analysis uses disposable signal/feature copies; stored signals are never
zeroed or permanently filled with NaNs. A breath's trough-to-trough support
and a peak-to-peak IBI must avoid marked artifacts. Invalid amplitudes/IBIs
are unavailable in the analysis view. Rate, variability, apnea-amplitude and
thoracoabdominal windows cannot bridge the contaminated support. Sigh local
baselines also reject crossing windows. Session/global respiratory reference
calculations exclude contaminated breaths and raw artifact samples.

Valid evidence from the other belt remains usable for single-belt labels;
two-belt metrics require simultaneous clean evidence. Raw apnea fallback
rejects any window crossing a marked artifact even when its finite-sample
fraction would otherwise pass. Periodic and phase methods process clean
signal regions independently; the Guyot envelope cannot interpolate a
technical artifact into a physiological pause. Thoracic rhythmicity (Q23)
rejects artifact-contaminated windows explicitly.

Sample-level label assessability includes the per-belt contaminated support
and guards based on the existing estimator windows. Marked artifacts mean
unavailable evidence, rather than assessed absence of a physiological event.
SpO2 assessability is unchanged. Artifacts are independent of the clinician's
minimal-thoracic-excursion observation and of the missing-lung-belt setting.
Physiological breath holding or small respiratory excursion is not
implicitly marked as artifact.

## Affected implementation files

- GUIs: `src/gui/manual_edit_respiration_features.m`,
  `src/gui/manual_edit_label_events.m`.
- Cache/workflow: `src/get_config_defaults.m`, `src/run_magma.m`,
  `src/feature_extraction/load_or_extract_respiratory_cycles.m`,
  `extract_respiration_features.m`, `extract_respiration_feature.m`,
  `src/utils/empty_respiration_feature.m`, `atomic_save_mat.m`,
  `respiratory_artifact_checkpoint.m`.
- Analysis: respiratory reference/features/rhythmicity and the new
  `respiratory_artifact_view.m`; periodic method dispatch/eAMI/Guyot, apnea, sigh, phase-offset
  and coherence calculations; `run_selected_label_detectors.m`,
  `build_sigh_breath_candidates.m`, `compute_label_assessable_mask.m`,
  `respiratory_artifact_label_mask.m`, both label finalizers.
- Shared helpers: `normalize_respiratory_artifacts.m`,
  `respiratory_artifact_masks.m`, `respiratory_artifact_state.m`,
  `respiratory_artifact_window_valid.m`, `shade_respiratory_artifacts.m`.
- Results/export: `build_recording_results.m`, `save_recording_results.m`,
  `review_existing_results.m`, `export_results_hdf5.m`,
  `write_respiratory_artifact_hdf5.m`, phenotype-summary
  plotting and group recording metadata.
- Tests: `tests/unit/test_respiratory_artifacts.m` plus existing focused
  cache, observation, detector and review regression suites.

Synthetic validation only:

```matlab
addpath(genpath('src')); addpath(genpath('tests'));
r = runtests('tests/unit/test_respiratory_artifacts.m');
assertSuccess(r);
```

## Validation notes

MATLAB R2025a validation uses synthetic 20-Hz respiratory traces and temporary
recording directories only. Checks cover range normalization, per-belt
independence, invalid crossing IBIs, references/window guards, sample
assessability, apnea fallback, periodic interpolation, wavelet gap boundaries,
legacy cache migration, GUI add/remove/reopen/Cancel, recording identity,
revision mirrors, and full synthetic MAT/HDF5 reanalysis. Source parsing and
`git diff --check` also pass. Sub33_M1's original cache and results remained
byte-identical to the verified backups; no real recordings or cohorts ran.

The broader affected-suite run found eight existing failures, reproduced in
an isolated archive of committed main. They are left unchanged:

- `test_sigh_detection_methods/testRatioPlotHandlesValidEvidenceWithZeroDetectedSighs`
- `test_periodic_breathing_methods/testCurrentPeriodicConfigurationContainsBothMethods`
- `test_periodic_breathing_methods/testEAMIEnergyUsesLocalMeanRemoval`
- `test_periodic_breathing_methods/testGuyotBeltCombinationRequiresAgreement`
- `test_periodic_breathing_methods/testGuyotSlidingWindowsDetectSyntheticPathologicalEnvelope`
- `test_respiratory_features/testRateWindowRequiresFullHistoryAndAtLeastTwoValidIbis`
- `test_respiratory_features/testSighDiagnosticPlotShowsRawAndRatioEvidencePerBelt`
- `test_respiratory_reference/testSuppliedBreathValuesAreUsedDirectly`

These concern existing plot-test setup/expectations, periodic-method
expectations, trough fixture alignment and reference-change expectations.
No physiology definitions or thresholds were changed to satisfy them.
