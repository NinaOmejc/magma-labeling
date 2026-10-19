# Current MATLAB recording results

`*_results.mat` contains exactly one variable, `results`, saved atomically in
MAT v7.3 format. Its schema identifier is
`results.metadata.result_schema_version = 'magma_recording_results_v1'`.
There are nine top-level branches:

| Branch | Contents |
| --- | --- |
| `metadata` | Recording identity, native sampling rate/count, analysis ID, external preprocessing description, result version, and the fixed phenotype column schema |
| `respiration` | Reviewed/extracted cycles and derived respiratory evidence |
| `references` | Session interval, respiratory references, and SpO2 reference |
| `labels` | Canonical names, automatic/reviewed layers, assessability metadata, and candidates |
| `phenotypes` | Current automatic/reviewed descriptive profiles and 24-value summaries |
| `review` | Immutable round history, active provenance, and compact editor outcome |
| `qc` | Respiratory signal QC, current artifact annotation metadata/coverage, current/analysis observations, analysis artifact revision, and pending status |
| `diagnostics` | Detector evidence |
| `config` | Analysis parameters, selected methods, channel metadata and preprocessing provenance |

The physiological mask schema remains exactly 11 columns. Every numeric
phenotype summary remains exactly 24 features. Native masks, assessability,
review coverage, detector evidence, missing reasons, review provenance,
observation revisions and scientific numeric values are preserved.

```matlab
S = load('Sub999_M1_results.mat');
R = S.results;
R.labels.automatic.mask
R.labels.reviewed.coverage_mask
R.phenotypes.automatic.numeric_summary.values
R.metadata.phenotype_schema.feature_names
R.references.respiration.lungs.reference_quality
R.review.history
```

## Field mapping

These names on the left remain the internal analysis API. They are no longer
independent variables in recording MAT files. `recording_results.m` is the
single pack/unpack/read/write boundary for all consumers.

| Internal/former top-level name | Saved path under `results` |
| --- | --- |
| `subject`, `measure` | `metadata.subject`, `metadata.measurement` |
| `config.fs`, sample count | `metadata.fs`, `metadata.n_samples` |
| `analysis_id` | `metadata.analysis_id` |
| `upstream_input_preprocessing` | `metadata.input_preprocessing` |
| `resp_cycles`, `resp_features` | `respiration.cycles`, `respiration.features` |
| `session_reference`, `resp_ref`, `spo2_ref` | `references.session`, `references.respiration`, `references.spo2` |
| `label_names`, `label_assessability_info` | `labels.names`, `labels.assessability` |
| `events_automatic`, `mask_automatic` | `labels.automatic.events`, `labels.automatic.mask` |
| `label_available`, `label_availability_reason` | `labels.automatic.available`, `labels.automatic.availability_reason` |
| `label_assessable_mask` | `labels.automatic.assessable_mask` |
| `label_burden_automatic`, `label_overlap_summary_automatic`, `label_evidence_summary_automatic` | `labels.automatic.burden`, `labels.automatic.overlap`, `labels.automatic.evidence` |
| `events_reviewed`, `mask_reviewed` | `labels.reviewed.events`, `labels.reviewed.mask` |
| `label_reviewed_available`, `label_reviewed_availability_reason` | `labels.reviewed.available`, `labels.reviewed.availability_reason` |
| `label_reviewed_assessable_mask`, `review_coverage_mask` | `labels.reviewed.assessable_mask`, `labels.reviewed.coverage_mask` |
| `review_status`, `review_scope` | `labels.reviewed.status`, `labels.reviewed.scope` |
| `label_burden_reviewed`, `label_overlap_summary_reviewed`, `label_evidence_summary_reviewed` | `labels.reviewed.burden`, `labels.reviewed.overlap`, `labels.reviewed.evidence` |
| `candidate_events` | `labels.candidates` |
| `phenotypes` | `phenotypes` |
| `review_history`, `review_provenance`, `manual_label_edit` | `review.history`, `review.provenance`, `review.manual_label_edit` |
| `respiratory_signal_qc` | `qc.respiratory_signal` |
| `respiratory_artifact_state`, `respiratory_artifact_qc` | `qc.respiratory_artifacts`, `qc.artifact_coverage` |
| `recording_observations`, `analysis_recording_observations` | `qc.recording_observations`, `qc.analysis_recording_observations` |
| `analysis_respiratory_artifact_revision` | `qc.analysis_artifact_revision` |
| `detector_diagnostics` | `diagnostics.detectors` |
| `config` | `config` with redundant fields removed as described below |

The shared authoritative ranges are
`results.respiration.cycles.artifact_intervals_idx`. Current artifact revision,
reviewer, timestamp, source and pending status live in `qc.respiratory_artifacts`.
Raw intervals and identical per-belt aliases are not copied into that branch;
the internal API derives its aliases on read. Analysis-time artifact support in
respiratory evidence is retained because it may differ from current annotations
while reanalysis is pending.

## Metadata consolidation

- The phenotype column names, groups, roles and units are saved once in
  `metadata.phenotype_schema`. Numeric summaries retain values, availability,
  coverage, missing reasons and version identifiers. Internal consumers and
  HDF5 export receive the fully expanded current summaries on read.
- `review.manual_label_edit` omits duplicate history, provenance, coverage,
  scope, status and current observation data. The internal API reconstructs
  these views from their authoritative paths.
- Each history entry retains its complete `phenotypes_reviewed` snapshot.
  Its identical `phenotype_numeric_summary_reviewed` alias is omitted in MAT
  storage and reconstructed for the existing internal/HDF5 API. Conflicting
  snapshots are rejected rather than silently discarded.
- `config.times` is omitted; native times are `(0:n_samples-1)/fs`. Identity,
  sampling rate and analysis ID are consolidated under metadata. Exact
  configuration copies of annotation/analysis snapshots use compact
  `metadata.configuration_views` references and are reconstructed from the
  matching source. Distinct analysis-time configuration snapshots remain
  intact; they are never replaced by a newer current annotation.
- Fixed assessability rule paragraphs are documented here instead of saved
  per recording. Compact metadata retains `label_assessability_v3`, the actual
  asynchrony projection (`selected_method`, `coherence`, or `unavailable`),
  affected partial labels and shared artifact-model identifier.
- Recording-specific reasons, QC status, selected methods, thresholds,
  parameters and provenance remain. Conditional scientific limitation codes
  and existing public HDF5 profile descriptions remain intact.

Assessability rules are unchanged: SpO2 uses finite native samples; asynchrony
uses nearest-sample projection of valid selected-method/coherence evidence;
other labels start from recording availability. Shared respiratory artifacts
exclude breath/IBI support and estimator windows for both belts. Artifacts are
unassessable evidence, not physiological negatives. Estimator startup latency
alone does not imply physiological unassessability.

Scientific arrays deliberately retained include both physiological masks,
assessability and review coverage, every immutable round's masks/snapshots,
reviewed belt signals/landmarks, detector evidence and its analysis time grids.
Some arrays can be numerically identical while representing different review
rounds or automatic versus current annotation evidence; they are not removed.

## Persistence and compatibility

The analysis APIs stay flat internally. Use
`recording_results('load', filename)` for that API and ordinary `load` for
direct exploration of the hierarchy. All pipeline, group and annotation-mirror
code uses the centralized boundary; annotation updates cannot append scattered
top-level variables. New unmapped internal fields cause an explicit error.

Atomic writes stage beside the destination and replace it only after saving
succeeds. Unchanged metadata patches do not rewrite the file. MATLAB's public
MAT-file interface does not support safe partial writes to nested struct fields;
genuine changes therefore require atomic replacement of the single results
variable. This avoids private HDF5/MAT object-reference edits. Observation
journals, locking, rollback and temporary cache transaction files are retained;
successful transactions remove temporary files. Persistent automatic
`feature_review_backups` are not created, and existing backups are not deleted.

Old flat results and 22-feature summaries are rejected. To regenerate from
reviewed feature caches, use `execution.mode='analyze'`,
`execution.selected_labels={}`, `overwrite_results=true`, and
`overwrite_features=false`. Obsolete result fields are not imported during
regeneration. Current schema-6 manual-label checkpoints and current immutable
history remain supported; obsolete manual-review sidecars receive an explicit
error and must be archived before starting a new review.

Feature-cache compatibility is separate: version-9 caches, optional historic
override/absolute-polarity fields and union migration of per-belt artifacts
remain supported. Reviewed incompatible caches fail safely without regeneration.
No real recording/cache files are rewritten by this source cleanup.

HDF5 remains `magma_ml_hdf5_v19`, with the existing public scientific paths,
fully expanded phenotype schema, immutable review snapshots and current
annotation/analysis provenance. MAT and HDF5 contain equivalent scientific
information despite their different layout.
