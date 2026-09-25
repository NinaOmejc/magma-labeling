# Outputs

Each recording is written below:

```text
<config.path_results_out>/Sub<subject>_M<measurement>/
```

The main files are:

```text
Sub<subject>_M<measurement>_labels.mat
Sub<subject>_M<measurement>_labels.h5
```

The MAT file is the authoritative MATLAB result. The HDF5 file uses schema
`magma_ml_hdf5_v11` and is intended for downstream Python/ML analysis.

## Recording-level MATLAB fields

Level-1 and full Level-2A evidence remains available in:

```matlab
results.resp_cycles
results.resp_features
results.events_automatic
results.events_reviewed
results.mask_automatic
results.mask_reviewed
results.label_assessable_mask
results.label_reviewed_assessable_mask
results.detector_diagnostics
results.label_burden_automatic
results.label_burden_reviewed
results.label_overlap_summary_automatic
results.label_overlap_summary_reviewed
results.label_evidence_summary_automatic
results.label_evidence_summary_reviewed
```

The phenotype bundle contains full evidence and compact features for each
annotation layer:

```matlab
results.db_phenotype_evidence.automatic.prespecified_db
results.db_phenotype_evidence.automatic.respiratory_patterns
results.db_phenotype_evidence.automatic.compact_features

results.db_phenotype_evidence.reviewed.prespecified_db
results.db_phenotype_evidence.reviewed.respiratory_patterns
results.db_phenotype_evidence.reviewed.compact_features
```

Each `compact_features` struct contains:

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

Every aligned vector has exactly 21 elements in the fixed schema order.
`values` and `coverage_fraction` are doubles; `available` is logical. Raw
values are not scaled or imputed.

Candidate events remain separate from final accepted events:

```matlab
results.candidate_events
```

They contain meaningful pre-final candidates where a detector has a distinct
candidate stage and are not duplicates of `events_automatic`.

## Automatic versus reviewed annotations

Automatic and manually reviewed annotations are stored separately. Review
coverage is explicit:

```text
unreviewed != negative
unavailable physiological evidence != negative
```

Automatic phenotype features use the full physiologically assessable scope.
Reviewed phenotype features use only explicitly reviewed and physiologically
assessable regions.

## HDF5 structure

Important high-level groups include:

```text
/signals/preprocessed
/signals/raw                 (optional)
/time

/resp_cycles
/resp_features
/detector_diagnostics

/labels/automatic_mask
/labels/reviewed_mask
/labels/assessable_mask
/labels/reviewed_assessable_mask
/labels/review_coverage_mask

/events/automatic
/events/reviewed
/events/candidate

/burden/automatic
/burden/reviewed
/overlap/automatic
/overlap/reviewed
/evidence_summary/automatic
/evidence_summary/reviewed

/phenotype_evidence
/session_reference
/resp_reference
/spo2_reference
/config
/meta
```

The full Level-2A archive is retained below `/phenotype_evidence`. Fixed
Level-2B datasets are directly readable at:

```text
/phenotype_evidence/automatic/compact_features/version
/phenotype_evidence/automatic/compact_features/schema_version
/phenotype_evidence/automatic/compact_features/n_features
/phenotype_evidence/automatic/compact_features/feature_names
/phenotype_evidence/automatic/compact_features/values
/phenotype_evidence/automatic/compact_features/available
/phenotype_evidence/automatic/compact_features/coverage_fraction
/phenotype_evidence/automatic/compact_features/missing_reason
/phenotype_evidence/automatic/compact_features/phenotype_group
/phenotype_evidence/automatic/compact_features/feature_role
/phenotype_evidence/automatic/compact_features/units
```

The identical structure exists under:

```text
/phenotype_evidence/reviewed/compact_features/
```

The main Python use case therefore reads the fixed datasets directly rather
than recursively discovering arbitrary evidence fields.

Text arrays are stored as zero-padded UTF-8 byte columns. Numeric arrays and
label masks use HDF5 compression where appropriate; logical arrays are stored
exactly as `uint8` with a logical attribute. By default the export omits raw
signals, includes preprocessed signals, and casts only exported signals to
compressed single precision. HDF5 storage settings do not modify the in-memory
analysis, MAT output, features, or labels.

## Group-level outputs

Group outputs are written to:

```text
<config.path_results_out>/group_analysis/
```

The existing broad QC outputs are retained, including:

```text
group_label_summary.csv
group_label_summary.mat
cohort_qc_summary.mat
cohort_label_qc_summary.csv
cohort_event_durations.csv
cohort_candidate_events.csv
group_measure_comparability.csv
```

Dedicated phenotype outputs are:

```text
group_phenotype_features_automatic.csv
group_phenotype_features_reviewed.csv
group_phenotype_availability_automatic.csv
group_phenotype_availability_reviewed.csv
group_phenotype_coverage_automatic.csv
group_phenotype_coverage_reviewed.csv
phenotype_feature_dictionary.csv
group_phenotype_features_long.csv
group_phenotype_features.mat
```

Each feature CSV has the five identifier columns:

```text
recording_id, subject, measure, subject_group, analysis_id
```

followed immediately by exactly the 21 fixed feature columns. Availability and
coverage are kept in separate aligned tables, so QC columns never interrupt the
ML matrix. Missing feature values remain `NaN`.

`recording_id` uses `Sub<subject>_M<measure>`, which permits a future clustering
result containing `recording_id`, `cluster`, `clustering_method`, and `run_id`
to merge directly with the phenotype table. Automatic values are the primary
whole-cohort clustering input. Reviewed values remain separate for validation
and sensitivity analyses.

`phenotype_feature_dictionary.csv` has one row per feature and the columns:

```text
feature_index
feature_name
display_name
phenotype_group
feature_role
units
source_description
```

`group_phenotype_features_long.csv` is a tidy QC representation containing one
row per recording, annotation layer, and feature. No group output is
pre-standardized, transformed, or imputed.
