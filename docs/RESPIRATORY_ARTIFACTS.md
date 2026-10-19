# Rechecking respiratory features and marking artifacts

Use this workflow for an existing recording whose breath landmarks have
already been reviewed. Compatible version-9 caches retain every saved
peak, trough, trough override, amplitude method and polarity alignment.
Legacy per-belt artifact lists are unioned, merging overlaps and touching spans.
Missing artifact fields in older compatible caches open as empty intervals.
QC and ML metadata distinguish absent annotation information from a confirmed
empty annotation; obsolete MAT result layouts must be regenerated.
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

Rechecking opens the original cache without creating a persistent backup.
**Reviewed** validates the edited landmarks and atomically replaces the same
`*_features.mat` file, preserving its other metadata, provenance, and observation
fields. Existing `feature_review_backups/` folders are left untouched; inspect
and remove old copies manually when appropriate. Do not use
`overwrite_features=true` for this workflow. Set `recheck_cached=false` again
after finishing.

The feature GUI has **Edit peaks**, **Move trough**, and **Mark artifact**.
In Mark artifact, drag on either trace to exclude the interval from **both**
respiratory belts. The same orange shading appears on both traces; clicking
either shaded interval removes it from both. Overlapping or immediately adjacent
ranges merge and endpoints clamp to the recording. The original waveform and all
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

The feature cache version remains **9**; artifact annotations migrate to the shared model:

- `resp_cycles.artifact_intervals_idx`: authoritative N-by-2 inclusive, one-based
  integer `[start_idx end_idx]` sample ranges; empty means no marked artifacts.
  If present, this field takes precedence, including when empty. Otherwise,
  both legacy belt lists are unioned and normalized. New cache/result saves
  remove the legacy fields from the saved belt structs without moving landmarks.
- `resp_cycles.artifact_annotation`: `version`, `revision`, UTC `timestamp`,
  `reviewer_role`, `annotation_source`, `scope`, and `pending_reanalysis`.
- Top-level `respiratory_artifact_state`: version `respiratory_artifacts_v2`,
  scope `recording`, annotation metadata, `subject` + `measurement`, shared
  `artifact_intervals_idx`, and shared contaminated breath/IBI support
  `evidence_intervals_idx`. Compatibility aliases `lungs`/`diaph` and
  `lungs_evidence`/`diaph_evidence` are derived identical copies, not separate
  annotations. Disposable analysis belt structs also carry derived interval
  aliases for existing single-belt estimators; these are not stored in cycle caches.

The revision increments on a confirmed artifact **or landmark** change, so
late peak/trough corrections also invalidate derived outputs. Previously
recorded review provenance is retained. No-change acceptance does not bump
the revision. Cache updates are staged beside the destination and then
replaced, preserving other saved top-level variables. Simultaneous changes
to the thoracic observation use its existing transaction/checkpoint handling.
Temporary staging and rollback files are removed after successful completion.
An interrupted or failed transaction may retain the files needed for recovery;
these are not historical review backups.

Migrating nonempty legacy annotations changes their scientific scope to both
belts. Saving that migration increments the artifact revision and marks derived
outputs pending reanalysis. Cancel leaves the original legacy cache untouched.

The feature cache is authoritative. Current `results.mat` receives annotation
metadata under `results.qc.respiratory_artifacts` immediately after a committed
feature review, together with shared
`results.respiration.cycles.artifact_intervals_idx` and a
`results.qc.artifact_coverage` snapshot. `results.qc.analysis_artifact_revision` records the
revision used for automatic analysis. Obsolete result layouts must be regenerated
from the protected feature cache. Labels and
historical reviews are not rewritten by this metadata update. Pending state
or unequal current/analysis revisions indicates that a full rerun is needed.
A selective rerun is rejected while feature reanalysis is pending. Pending
state clears only after current-revision MAT and enabled HDF5 outputs save
successfully. If an output mirror cannot be written, the error propagates;
the saved cache revision remains authoritative and pending for a retry.

Sample assessability metadata uses `label_assessability_v3`.

HDF5 exports shared ranges at `/breaths/artifact_intervals_idx` and annotation
metadata below `/breaths`, with:

- `/observations/respiratory_artifacts_json`: current compact state.
- `/observations/analysis_respiratory_artifact_revision`: automatic-analysis
  revision. The former can change without rewriting previous automatic data.
- `/qc/respiratory_artifacts`: duration, fraction, interval count, annotation
  identity/revision status, and explicit respiratory training eligibility.

Group recording summaries expose `respiratory_artifact_duration_sec`,
`respiratory_artifact_fraction`, `respiratory_artifact_n_intervals`,
`respiratory_artifact_revision`, `analysis_respiratory_artifact_revision`, and
`respiratory_artifact_pending_reanalysis`. Duration is inclusive sample count
divided by native sampling rate, counting shared overlaps only once; fraction
uses recording sample count as denominator. Known empty annotations have zero
coverage; missing legacy metadata has NaN duration, fraction, count, and
revision, with `respiratory_artifact_annotation_known=false`.

Pending revisions warn and exclude respiratory cohort summaries, phenotype
values, and event aggregates until reanalysis. They retain recording QC,
SpO2, clinician observations, and saved review history. Phenotype figures keep
the orange pending warning. Review-only retains the previous automatic masks
and analysis revision; it does not silently make them current.

Automatic, reviewed, and comparison label plots show a thin purple
**Respiratory artifact** timeline below the 11 physiological rows, with legend
**Respiratory artifact (excluded)**. Only saved annotation intervals populate
this strip; assessability gaps do not imply artifacts. Empty annotations leave
it white; missing legacy metadata is identified explicitly. Unassessable label
cells have a separate amber state. No artifact label column is created.

HDF5 schema v19 exports `/signals/ml/respiratory_artifact_valid_mask` on the
exact ML time grid, excluding the complete resampling FIR half-support around
artifact boundaries (1 second at the default 200-to-10-Hz rates).
`source_valid_mask` and `channel_valid_mask` distinguish source gaps from
shared respiratory artifacts; contaminated ML values are NaN. Native signals
stay unchanged. `/labels/automatic/ml_training_valid_mask` and the equivalent
reviewed dataset project assessability conservatively onto ML bins, retain
explicit review coverage, and exclude stale respiratory analysis. SpO2 does
not inherit respiratory artifact/revision exclusions. Check
`/qc/respiratory_artifacts/automatic_respiratory_training_eligible` and these
validity masks before selecting training windows. Immediate annotation mirror
updates refresh QC/validity without rewriting physiological masks or original
waveforms; prior export gaps can remain conservatively invalid until a full
export is rebuilt.

## Evidence semantics

Analysis uses disposable signal/feature copies; stored signals are never
zeroed or permanently filled with NaNs. A breath's trough-to-trough support
and a peak-to-peak IBI must avoid marked artifacts. Invalid amplitudes/IBIs
are unavailable in the analysis view. Rate, variability, apnea-amplitude and
thoracoabdominal windows cannot bridge the contaminated support. Sigh local
baselines also reject crossing windows. Session/global respiratory reference
calculations exclude contaminated breaths and raw artifact samples.

Shared artifacts invalidate thoracic, abdominal, and two-belt evidence alike.
Raw apnea fallback
rejects any window crossing a marked artifact even when its finite-sample
fraction would otherwise pass. Periodic and phase methods process clean
signal regions independently; the Guyot envelope cannot interpolate a
technical artifact into a physiological pause. Thoracic rhythmicity (Q23)
rejects artifact-contaminated windows explicitly.

Sample-level label assessability includes the shared contaminated support
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
  `shared_respiratory_artifacts.m`, `migrate_respiratory_artifacts.m`,
  `respiratory_artifact_masks.m`, `respiratory_artifact_state.m`,
  `respiratory_artifact_window_valid.m`, `shade_respiratory_artifacts.m`.
- QC/ML projection: `respiratory_artifact_qc.m`,
  `respiratory_artifact_ml_validity.m`, `ml_label_assessability.m`.
- Results/export: `build_recording_results.m`, `save_recording_results.m`,
  `review_existing_results.m`, `export_results_hdf5.m`,
  `write_respiratory_artifact_hdf5.m`, phenotype-summary
  plotting and group recording metadata.
- Tests: `tests/unit/test_respiratory_artifacts.m`,
  `test_respiratory_artifact_qc.m`, `test_label_mask_plot.m`, and targeted
  HDF5/group checks alongside existing cache, observation and review suites.

Synthetic validation only:

```matlab
addpath(genpath('src')); addpath(genpath('tests'));
r = runtests('tests/unit/test_respiratory_artifacts.m');
assertSuccess(r);
```

## Validation notes

MATLAB R2025a validation uses synthetic 20-Hz respiratory traces and temporary
recording directories only. Tests cover range normalization, shared exclusion
of both belts, legacy union migration, invalid crossing IBIs, references/window guards, sample
assessability, apnea fallback, periodic interpolation, wavelet gap boundaries,
legacy cache migration, GUI add/remove/reopen/Cancel, recording identity,
revision mirrors, and full synthetic MAT/HDF5 reanalysis. The shared-artifact
updates have not been executed as part of this change. Earlier validation found
Sub33_M1's original cache and results remained
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
