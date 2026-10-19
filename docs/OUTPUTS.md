# Outputs

Each recording is written below:

```text
<config.path_results_out>/Sub<subject>_M<measurement>/
```

The main recording files are:

```text
Sub<subject>_M<measurement>_results.mat
Sub<subject>_M<measurement>_results.h5
```

The respiratory-feature cache remains:

```text
Sub<subject>_M<measurement>_features.mat
```

When `config.PhenotypeSummary.do_plot` is enabled, the final merged phenotype
bundle is also presented as:

```text
Sub<subject>_M<measurement>_phenotype_summary.png
```

This single figure is refreshed after each successful review. It displays
Automatic plus Review 1, Review 2, etc. using immutable review-round snapshots
in round order; the latest round is the last review column. No round-specific
phenotype image is created. Units are included in measure labels, literature
profiles retain compact group headings, and each label-based profile has one
burden row. It does not recompute, normalize, score, or impute phenotype values.
Unavailable values remain explicit; older rounds without snapshots show Not
computed. Forced abdominal expiration remains not assessable from current signals.

The authoritative MAT results and manual-review checkpoint retain these optional
fields on each `review_history` / `manual_label_review_history` entry:

```matlab
results.review_history(k).round_id
results.review_history(k).phenotypes_reviewed
results.review_history(k).phenotype_numeric_summary_reviewed
```

The first phenotype field stores that round's complete reviewed phenotype layer;
the second stores its fixed numeric summary. Snapshots are attached after the
reviewed phenotype layer is built. Existing snapshots are preserved, including
during selected-label reruns. Older histories without these fields still load;
only the active round can gain a newly computed snapshot. Cancelled reviews
leave the saved history and figure unchanged. Top-level `results.phenotypes`
continues to hold the current automatic/reviewed bundle. HDF5 preserves these immutable snapshots under each review round; existing
label-mask figure naming is unchanged.

The MAT file is the authoritative MATLAB result. The HDF5 file uses schema
`magma_ml_hdf5_v19` as a portable recording-level representation.

## Recording-level thoracic observation

Both manual editors share **Minimal or absent thoracic excursion**.
This recording observation is not a diagnosis, missing sensor, or new time-resolved
label. It supplies the clinician feature of the new recording-level phenotype.
The GUI offers **Not assessed**, **Not observed**, and **Observed**, with the
saved status selected. Accepting ordinary landmark or label review leaves an
unassessed observation unchanged. An explicit assessment stores `not_observed`
(0) or `observed` (1); `not_assessed` remains NaN. Cancel/X preserves the old
metadata. Selecting Not assessed also allows reversing a previous assessment. No valid thoracic peaks are needed to annotate it.

`results.mat` and the feature cache store top-level `recording_observations`:

| Field | Meaning |
| --- | --- |
| `code`, `scope` | `minimal_thoracic_excursion`, `recording` |
| `subject`, `measurement` | Recording identity, including measurement |
| `status` | `not_assessed`, `observed`, or `not_observed` |
| `timestamp`, `reviewer_role`, `annotation_source` | UTC change time, configured reviewer role, and editor source |
| `revision` | Increasing annotation revision; unchanged saves do not increment it |
| `pending_reanalysis`, `affected_labels`, `affected_outputs` | Explicit dependency invalidation after either establishing or clearing the observation |

A compact `Sub<subject>_M<measurement>_recording_observations.mat` sidecar retains
the shared state before results/cache creation. Keep it with the recording outputs.
Updates check recording identity and revision, synchronize existing MAT/HDF5
mirrors, and roll back failed writes. A `.pending.mat` journal blocks loading after
an interrupted update; close both editors, resolve file access, then recover with
`recording_observation('recover', config)` using that recording's resolved config.
Conflicting mirrors or stale open editors produce explicit errors.

`analysis_recording_observations` in results records the observation actually used
for automatic analysis. Cached cycles also retain their extraction snapshot.
Review rounds add `recording_observations` and, when changed,
`recording_observation_change.before/after`; previous rounds and event edits remain.
The optional HDF5 `/observations/recording_json` UTF-8 text column contains
`current`, `analysis`, and `derived_results_pending_reanalysis`. Existing HDF5
metadata is updated without rewriting signals, even if new HDF5 export is disabled;
older HDF5 computed outputs stay marked stale until exported again. Observation
snapshots/changes also accompany newly exported review rounds under `/review/history`.
Older MAT/HDF5 files without these fields remain readable.

When established before detection, thoracic cycles, references, raw apnea fallback,
periodic evidence, and cross-belt polarity/phase evidence are excluded. Abdominal
evidence remains usable, and the thoracic trace remains available for display.
Existing thoracic and abdominal landmarks remain intact while the observation
gates active evidence. Clearing it makes retained thoracic landmarks eligible
again; it never regenerates reviewed peaks/troughs. If a formerly suppressed cache
contains no thoracic landmarks, an explicit feature review/re-extraction is needed
to establish them. No deleted landmarks can be reconstructed from old empty caches.
Existing missing-lung-belt behavior and the 11-label schema are unchanged.

A late label-editor annotation changes metadata, not previously computed automatic
events/masks. Respiratory polarity/features/references, respiratory labels, dependent
summaries, and phenotypes are marked pending. Explicitly run a full analysis with
`config.execution.mode = 'analyze'`, `config.execution.selected_labels = {}`, and
`config.overwrite_results = true`. Existing saved manual edits/history are retained;
`overwrite_features` need not be enabled. Pending clears only after a successful
full result save using the current revision. Review-only and selected-label runs
cannot clear it; a pending recording rejects selected-label reruns. Export HDF5
again to refresh its computed arrays if its export was disabled during reanalysis.

Implementation file map (under `src/` unless stated otherwise):

| Area | Files |
| --- | --- |
| Editors | `gui/manual_edit_respiration_features.m`, `gui/manual_edit_label_events.m` |
| Shared state and analysis gate | `utils/recording_observation.m`, `utils/minimal_thoracic_excursion.m` |
| Cycle cache and evidence | `feature_extraction/apply_thoracic_observation.m`, `extract_respiration_features.m`, `load_or_extract_respiratory_cycles.m`, `compute_respiratory_features.m`, `compute_respiratory_reference.m` |
| Raw and two-belt detector gates | `label_detection/detect_apnea.m`, `compute_eami_periodic_breathing.m`, `compute_guyot_periodic_breathing.m`, `compute_respiratory_asynchrony_metrics.m`, `compute_respiratory_phase_offset_metrics.m` |
| Polarity evidence | `utils/correct_respiratory_belt_polarity.m`, `utils/determine_absolute_respiratory_polarity.m` |
| Execution and result/review persistence | `run_magma.m`, `utils/build_recording_results.m`, `utils/save_recording_results.m`, `utils/review_existing_results.m`, `utils/create_manual_review_round.m` |
| New spectral descriptor | `feature_extraction/compute_thoracic_respiratory_rhythmicity.m` |
| Phenotype schema and recording features | `utils/get_phenotype_feature_schema.m`, `build_compact_phenotype_features.m`, `build_db_phenotype_evidence.m`, `build_db_phenotype_evidence_bundle.m`, `build_thoracic_excursion_phenotype.m`, `attach_thoracic_excursion_phenotype.m`, `align_phenotype_numeric_summary.m` |
| Cache protection and backup | `utils/has_reviewed_respiration_landmarks.m`, `utils/backup_recording_mat_files.m`, `utils/build_sigh_breath_candidates.m` |
| Figure and group export | `plotting/plot_phenotype_summary.m`, `group/build_group_label_table.m`, `group/build_group_phenotype_tables.m`, `group/collect_group_workbook_tables.m` |
| HDF5 | `export/write_recording_observation_hdf5.m`, `export/export_results_hdf5.m` |
| Documentation and focused tests | `docs/CONFIGURATION.md`, `docs/OUTPUTS.md`, `tests/unit/test_thoracic_observation.m`, `tests/unit/test_thoracic_phenotype_features.m`, `tests/unit/test_stage6_freeze.m` and the existing phenotype/group regression fixtures (repository-relative) |

The new phenotype lives at
`phenotypes.{automatic,reviewed}.recording_level.minimal_thoracic_excursion`.
Its numeric-summary positions are **23** `thoracic_respiratory_rhythmicity`
and **24** `minimal_thoracic_excursion_clinician`; positions 1-22 are unchanged.
Signal QC/provenance is stored at `results.respiratory_signal_qc.thoracic`,
and HDF5 exports it under `/diagnostics/respiratory_signal_qc/thoracic`.
The compact QC contains no waveform or PSD arrays. HDF5 also preserves each saved
review numeric snapshot, including legacy 22-value snapshots, under
`/review/history/round_NNNNNN/phenotype_numeric_summary_reviewed`.
Read-side alignment pads a copy of an old 22-value summary with unavailable NaNs;
old files and immutable history entries are not rewritten.

Group `Phenotypes`, `Phenotype_QC`, matrices and the feature dictionary include
all 24 features. `Recordings` additionally exposes
`minimal_thoracic_excursion_status`, `minimal_thoracic_excursion_clinician`,
`thoracic_respiratory_rhythmicity`,
`thoracic_respiratory_rhythmicity_available`,
`thoracic_respiratory_rhythmicity_missing_reason` and
`recording_observation_pending_reanalysis`. Those observation columns describe
current metadata; automatic matrix feature 24 describes the analysis snapshot.
Technical missingness is explicit, never a numeric zero.

See [the scientific definition and safe rerun procedure](PHENOTYPES.md#thoracic-excursion-phenotype-and-rhythmicity).

## Two output levels

Level 1 contains time-resolved physiological labels, accepted and candidate
events, assessability, burden, overlap, supporting evidence, and detector
diagnostics. Level 2 contains recording-level phenotypes and patterns. The two
annotation layers remain separate throughout: `automatic` and `reviewed`.

The MATLAB phenotype bundle is available at:

```matlab
results.phenotypes.automatic.literature_based
results.phenotypes.automatic.label_based
results.phenotypes.automatic.numeric_summary

results.phenotypes.reviewed.literature_based
results.phenotypes.reviewed.label_based
results.phenotypes.reviewed.numeric_summary
```

`literature_based` contains exactly five profiles:

```text
hyperventilation_like
periodic_deep_sighing
thoracic_dominant_breathing
forced_abdominal_expiration
thoracoabdominal_asynchrony
```

`label_based` contains exactly six profiles:

```text
apneic_breathing
periodic_breathing
shallow_breathing
slow_breathing
irregular_breathing
desaturation
```

These profiles are descriptive, may coexist, and are not binary diagnoses.

Every detailed phenotype or pattern contains exactly:

```text
name
available
signal_derived_measures
limitations
source_provenance
```

`available` means sufficient MAGMA signal support exists to compute the
profile for this recording. It does not mean that the phenotype is present or
that a clinical diagnosis has been established.

```text
available != phenotype present
available != clinical diagnosis
```

Each `numeric_summary` has the same fixed 24 values in the same schema order
and contains:

```text
version
schema_version
n_features
feature_names
values
available
coverage_fraction
missing_reason
phenotype_group
feature_role
units
```

Values are not scaled or imputed. A finite zero is distinct from unavailable
evidence; unavailable values remain `NaN` with `available=false`.

## HDF5 structure

The public hierarchy is:

```text
/signals
    /preprocessed
    /raw                  optional
    /ml
        /data
        /time
        /fs
        /source_fs
        /channel_names
        /channel_roles
        /source_channel_indices
        /source
        /resampling_method
        /resampling_filter_half_support_sec
        /source_valid_mask
        /channel_valid_mask
        /respiratory_artifact_valid_mask
/time

/breaths
/respiration
/diagnostics

/labels
    /names
    /automatic
        /mask
        /available
        /availability_reason
        /assessable_mask
        /ml_training_valid_mask
        /burden
        /overlap
        /evidence
    /reviewed
        /mask
        /available
        /availability_reason
        /assessable_mask
        /coverage_mask
        /ml_training_valid_mask
        /status
        /burden
        /overlap
        /evidence

/events
    /automatic
    /reviewed
    /candidate

/phenotypes
    /automatic
        /literature_based
        /label_based
        /numeric_summary
    /reviewed
        /literature_based
        /label_based
        /numeric_summary

/references
    /session
    /respiration
        /lungs
        /diaphragm
    /spo2

/review
/config
/meta
/qc/respiratory_artifacts
```

Schema v17 provides two signal levels. `/signals/preprocessed` remains the
authoritative processed signal on the native recording timeline in `/time`;
optional `/signals/raw` is unchanged. `/signals/ml/data` is an additional,
export-only, anti-aliased lower-rate copy with its own exactly aligned timeline
in `/signals/ml/time`. Its default rate is 10 Hz and can be changed with
`config.HDF5.ml_sampling_hz` without changing any MATLAB analysis rate or
scientific calculation.

The ML bundle contains resolved channels in the stable role order `diaph`,
`lungs`, `spo2`. A missing channel is omitted, never replaced by a zero-valued
channel. Channels with fewer than two finite source samples are also omitted.
For otherwise usable channels, internal non-finite gaps are linearly
interpolated and leading/trailing gaps use the nearest finite value on a
temporary export copy. MATLAB's anti-aliased polyphase FIR `resample` operation
then uses endpoint-value padding so non-zero baselines such as SpO2 do not
acquire zero-extension boundary excursions.

Schema v19 adds validity on the same ML time grid. Respiratory artifact
exclusion includes the full FIR half-support on either side of each marked
interval (1 second for the default 200-to-10-Hz resampling). Contaminated ML
values are NaN; native waveforms remain unchanged. `source_valid_mask` records
finite-source/filter support before artifact exclusion, while
`channel_valid_mask` also excludes respiratory artifacts from both belts.
SpO2 validity does not depend on respiratory artifacts. The shared
`respiratory_artifact_valid_mask` describes artifact-free filter support.

Use `/labels/<automatic|reviewed>/ml_training_valid_mask` when constructing
training examples: it conservatively projects native assessability, intersects
reviewed coverage where relevant, and excludes stale respiratory revisions.
Physiological label masks remain native-grid, 11-column arrays. A false label
bit with false validity is unknown, not an assessed negative. Current shared
ranges are at `/breaths/artifact_intervals_idx`; annotation provenance and
current versus analysis revisions are described below.

ML values retain the preprocessed signal units and scale: respiratory belts
remain in their existing belt units and SpO2 remains a percentage. No
normalization, centering, z-scoring, or per-recording scaling is applied. The
ML representation is never fed back into respiratory processing, detectors,
events, labels, reviews, burden, evidence, references, or phenotypes, and it
does not alter MAT results.

The MATLAB configuration may retain `config.times`, but the full native vector
is omitted from `/config` to avoid duplicate storage. `/time` remains the
authoritative native recording time axis; `/signals/ml/time` applies only to
`/signals/ml/data`.

Numeric-summary datasets can be read directly below
`/phenotypes/<layer>/numeric_summary`. Text arrays are zero-padded UTF-8 byte
columns. Logical arrays are stored as `uint8` with a logical attribute.
Numeric arrays and label masks use HDF5 compression where appropriate. By
default, raw signals are omitted, preprocessed and ML signals are included, and
only exported signals are cast to compressed single precision; this does not
alter the in-memory analysis or MAT output. Set
`config.HDF5.include_ml_signals=false` to omit the complete `/signals/ml`
group while retaining the native export.

## Automatic and reviewed annotations

Automatic and reviewed annotations are not mixed. Review coverage is explicit:

```text
unreviewed != negative
unavailable physiological evidence != negative
```

Automatic summaries use the full physiologically assessable scope. Reviewed
summaries use only explicitly reviewed and physiologically assessable regions.

## Group-level outputs

Run `run('src/main_group.m')` to summarize saved `*_results.mat` files.
The output directory now contains two workbooks and the retained plots:

```text
<config.path_results_out>/group_analysis/
    group_summary.xlsx
    group_details.xlsx
    descriptive_overview/
        group_label_burden_histograms_automatic.png
        group_label_burden_histograms_automatic_Control.png
        group_label_burden_histograms_automatic_Patient.png
        group_label_burden_histograms_automatic_Control_Patient.png
    _cache/
        group_analysis_data.mat
```

Group-specific plots require matching Control or Patient metadata; the
combined plot requires both. Histogram bars show the percentage of assessable
subjects within each cohort and measurement; the workbook retains raw counts.
The layout and 5-percentage-point bins are unchanged. All other group plot
generation, including the complete diagnostic overview, has been removed. The plot extension follows
`config.plot_format`.

Each workbook starts with an Index sheet describing its tables and row counts.

| Workbook | Worksheets | Meaning |
|---|---|---|
| `group_summary.xlsx` | Label_burden | One recording and label per row, automatic and reviewed burdens, availability, review coverage, and event counts. Fractions remain 0ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Å“1. |
| | Phenotypes | The 24 schema-ordered raw features per recording, with an explicit automatic/reviewed layer column. |
| | Descriptive | Labels and features together, with variable type, annotation layer, units, measurement, sample count, median, IQR, and quantiles. |
| | Paired_summary | Labels and features together, with both measurement IDs and valid-pair counts. Label changes use percentage points; feature changes retain their units. |
| `group_details.xlsx` | Recordings, Cohort_label_QC | Full recording summaries and cohort label QC. |
| | Event_durations, Candidate_events | Accepted event durations and candidate acceptance/rejection details. |
| | Phenotype_QC, Feature_dictionary, Measure_comparability | Values, availability, coverage, missing reasons, definitions, and interpretation. |
| | Paired_changes, Subject_groups | Subject-matched values, availability flags, changes, valid-pair flags, and metadata provenance. |
| | Label_counts, Label_bins | Exact counts and bins for each generated histogram, combined with an All/Control/Patient cohort column. |
| | Manifest | Current output paths, cohort counts, selected layer, metadata source, and paired measurements. |

`build_group_label_table` alone exports the recording-level sheets; the
descriptive, paired, histogram, and manifest sheets are added by `main_group`.
Workbooks are rebuilt on rerun so old sheets and rows do not persist. No
separate group CSVs are generated. `_cache/group_analysis_data.mat` preserves
the complete MATLAB tables, including the wide availability and coverage
matrices, for code use.

`config.group.plot_layer` selects the descriptive and paired table layer.
Reviewed summaries use only explicitly reviewed, physiologically assessable
regions. They never fill uncovered regions from automatic annotations. A
finite zero indicates assessed absence; NaN in MATLAB and blank numerical
cells in Excel indicate missing or unavailable evidence. Plotting is retained
only for the automatic layer.

Histogram zeros remain in the first bin; unavailable observations are omitted.
Subjects with unknown group remain in the all-subject histogram and are
omitted from the Control/Patient splits. Group membership comes from
Questionnaire `grp` (0=Control, 1=Patient) or explicit group lists.

Labels can overlap, so burdens should not be summed to 100%. The 24 phenotype
features are signal-derived numerical descriptions, not diagnoses. Respiratory
belt magnitudes are not calibrated tidal volumes. Pair differences are
exploratory descriptions; M1 to M2 compares pre-exercise and post-exercise
recordings before rehabilitation. No hypothesis tests or clustering are run.

## Respiratory artifact annotations

The additive version-9 feature-cache fields, artifact revision/provenance,
analysis revision, and HDF5 v19 QC/observation datasets are documented in
[Rechecking respiratory features](RESPIRATORY_ARTIFACTS.md). Raw waveforms and
reviewed landmark positions remain intact. Artifact-contaminated samples are
excluded through `label_assessable_mask`; a false label bit there is not an
assessed physiological negative.

The group recording table and `/qc/respiratory_artifacts` expose
`respiratory_artifact_duration_sec`, `respiratory_artifact_fraction`,
`respiratory_artifact_n_intervals`, `respiratory_artifact_revision`,
`analysis_respiratory_artifact_revision`, and
`respiratory_artifact_pending_reanalysis`. Duration counts the inclusive union
once. Explicitly empty annotations have zero coverage; missing legacy metadata
has NaN coverage/count/revision and `respiratory_artifact_annotation_known=false`.
These are recording QC fields, outside the fixed 24 phenotype features.
`automatic_respiratory_training_eligible` requires known annotation metadata
and a current analysis revision. Pending recordings warn and retain QC rows,
but their respiratory cohort values/events are excluded until reanalysis;
SpO2 and the clinician observation remain independent.
