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

The figure displays the existing fixed 22-feature numeric summary grouped by
phenotype. It does not recompute, normalize, score, or impute phenotype values.
Unavailable values are shown explicitly, and forced abdominal expiration is
marked as not assessable from the current signals.

The MAT file is the authoritative MATLAB result. The HDF5 file uses schema
`magma_ml_hdf5_v16` as a portable recording-level representation.

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

Schema v16 provides two signal levels. `/signals/preprocessed` remains the
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
| `group_summary.xlsx` | Label_burden | One recording and label per row, automatic and reviewed burdens, availability, review coverage, and event counts. Fractions remain 0–1. |
| | Phenotypes | The 22 schema-ordered raw features per recording, with an explicit automatic/reviewed layer column. |
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

Labels can overlap, so burdens should not be summed to 100%. The 22 phenotype
features are signal-derived numerical descriptions, not diagnoses. Respiratory
belt magnitudes are not calibrated tidal volumes. Pair differences are
exploratory descriptions; M1 to M2 compares pre-exercise and post-exercise
recordings before rehabilitation. No hypothesis tests or clustering are run.
