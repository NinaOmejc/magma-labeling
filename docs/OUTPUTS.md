# Outputs

Each recording is written to:

```text
<config.path_results_out>/Sub<subject>_M<measurement>/
```

## Main files

```text
Sub<subject>_M<measurement>_labels.mat
Sub<subject>_M<measurement>_labels.h5
```

Additional outputs can include:

- diagnostic figures;
- saved manual-review files;
- respiratory feature caches.

The HDF5 file is intended for downstream Python/ML analysis.

## Important MATLAB result fields

### Respiratory representation

```matlab
results.resp_cycles
results.resp_features
```

These contain reviewed respiratory landmarks and derived breath-level evidence.

### Final automatic events

```matlab
results.events_automatic
```

These are the final accepted automatic label intervals.

### Candidate events

```matlab
results.candidate_events
```

These contain meaningful pre-final candidates where the detector has a distinct candidate stage, including rejected short events.

They are not duplicates of `events_automatic`.

### Detector-specific evidence

```matlab
results.detector_diagnostics
```

Examples include:

- periodic-breathing method evidence;
- phase-offset and coherence asynchrony evidence;
- desaturation event descriptors.

### Burden and overlap

```matlab
results.label_burden_automatic
results.label_burden_reviewed

results.label_overlap_summary_automatic
results.label_overlap_summary_reviewed
```

### Evidence summaries

```matlab
results.label_evidence_summary_automatic
results.label_evidence_summary_reviewed
```

### Configuration

```matlab
results.config
```

The complete resolved configuration used for that recording is saved with the result.

## Automatic versus reviewed annotations

Automatic and manually reviewed annotations are stored separately.

Review coverage is explicit, so:

```text
unreviewed != negative
```

Likewise:

```text
unavailable physiological evidence != negative
```

## HDF5 structure

Important high-level groups include:

```text
/signals/preprocessed
/signals/raw                 (optional)

/resp_cycles
/resp_features

/labels/automatic_mask
/labels/reviewed_mask

/events/automatic
/events/candidate

/burden
/overlap
/evidence_summary

/detector_diagnostics

/session_reference
/resp_reference
/spo2_reference

/config
```

By default, HDF5 export omits `/signals/raw`, includes
`/signals/preprocessed`, and stores exported signal matrices as compressed
single-precision values. `config.HDF5.include_raw_signals`,
`include_preprocessed_signals`, `signal_datatype`, and `compression_level`
control these export-only storage choices. They do not modify the in-memory
signals, MAT output, features, or labels. Numeric arrays and label masks use
chunked HDF5 compression where appropriate; label masks remain exact `uint8`
datasets.

Asynchrony method evidence is stored below:

```text
/detector_diagnostics/async/methods
```

Desaturation diagnostics are stored below:

```text
/detector_diagnostics/desat
```

## Group-level outputs

Group summaries are written to:

```text
<config.path_results_out>/group_analysis/
```

These contain recording-level label burden, availability, candidate-event QC, and compact physiological evidence intended for cohort analysis and subsequent ML/clustering.

The group tables summarize the authoritative subject-level outputs; they do not alter detector thresholds or annotations.
