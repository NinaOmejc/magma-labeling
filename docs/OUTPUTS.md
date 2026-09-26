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

The MAT file is the authoritative MATLAB result. The HDF5 file uses schema
`magma_ml_hdf5_v15` as a portable recording-level representation.

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

Each `numeric_summary` has the same fixed 22 values in the same schema order
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
        /burden
        /overlap
        /evidence
    /reviewed
        /mask
        /available
        /availability_reason
        /assessable_mask
        /coverage_mask
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
```

`/time` is the single authoritative recording time axis in HDF5. The MATLAB
configuration may retain `config.times`, but the full vector is omitted from
`/config` to avoid duplicate storage.

Numeric-summary datasets can be read directly below
`/phenotypes/<layer>/numeric_summary`. Text arrays are zero-padded UTF-8 byte
columns. Logical arrays are stored as `uint8` with a logical attribute.
Numeric arrays and label masks use HDF5 compression where appropriate. By
default, raw signals are omitted, preprocessed signals are included, and only
exported signals are cast to compressed single precision; this does not alter
the in-memory analysis or MAT output.

## Automatic and reviewed annotations

Automatic and reviewed annotations are not mixed. Review coverage is explicit:

```text
unreviewed != negative
unavailable physiological evidence != negative
```

Automatic summaries use the full physiologically assessable scope. Reviewed
summaries use only explicitly reviewed and physiologically assessable regions.

## Group-level outputs

Group outputs are written to:

```text
<config.path_results_out>/group_analysis/
```

The broad label and QC outputs remain:

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
phenotype_summary_automatic.csv
phenotype_summary_reviewed.csv
phenotype_availability_automatic.csv
phenotype_availability_reviewed.csv
phenotype_coverage_automatic.csv
phenotype_coverage_reviewed.csv
phenotype_dictionary.csv
phenotype_summary_long.csv
phenotype_summary.mat
```

The wide summary, availability, and coverage files begin with:

```text
recording_id, subject, measure, subject_group, analysis_id
```

and then contain the 21 schema-ordered fields. `recording_id` uses
`Sub<subject>_M<measure>`. `phenotype_dictionary.csv` documents every field;
`phenotype_summary_long.csv` contains one row per recording, annotation layer,
and numeric-summary field.
