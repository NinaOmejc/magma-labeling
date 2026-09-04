# MAGMA Physiological Event Labeling Pipeline

MATLAB-based pipeline for detecting and reviewing respiratory and oxygenation events in single-subject physiological recordings.

Canonical labels, in fixed order:

1. `shallow`
2. `deep`
3. `slow`
4. `rapid`
5. `irregular`
6. `apnea`
7. `sigh`
8. `csr`
9. `thoracic`
10. `async`
11. `desat`

The labels are independent and may overlap in time. They represent signal-derived physiological patterns rather than mutually exclusive clinical dysfunctional-breathing diagnoses. Original label definitions are available in `Labels.docx`.

The saved label schema is `independent_labels_v3_11class`. Historical v2 names are migrated by explicit name identity, never by column position: `shallowB→shallow`, `deepB→deep`, `slowB→slow`, `rapidB→rapid`, `irregB→irregular`, `CSR→csr`, `thorDomB→thoracic`, and `asyncB→async` (`apnea`, `sigh`, and `desat` are unchanged).

## Input Data

Each recording is a numeric `.dat` file with rows as time samples and columns defined by `config.data_columns`.

Default MAGMA order:

1. ECG1
2. ECG2
3. SpO2
4. Thoracic respiratory belt (`Resp-Lungs`)
5. Continuous blood pressure
6. Abdominal respiratory belt (`Resp-Diaphragm`)

The native/master sampling rate is 200 Hz. At least one respiratory belt is required. SpO2 is optional. If only one respiratory belt is usable, single-belt respiratory analyses still run, while dual-belt analyses such as `thoracic` and `async` are unavailable.

Default filename pattern:

```text
ECG1_ECG2_SpO2_RespL_BP_RespD_fs200_Sub<subject>_Pom<measure>_DeTr_Norm.dat
```

The `DeTr_Norm` component comes from upstream preprocessing that is not fully documented in this repository. The pipeline does not infer its meaning or apply an additional global normalization because of the filename.

## Download and Setup

```bash
git clone https://github.com/NinaOmejc/magma-labeling.git
cd magma-labeling
```

In MATLAB:

```matlab
addpath(genpath(fullfile(pwd, 'src')));
```

## Run Single-Subject Analysis

Edit `src/get_config.m`, then run:

```matlab
run('src/main_single.m')
```

`main_single.m` processes the selected subjects and measurements, extracts/reuses reviewed respiratory breaths, computes physiological features, detects automatic labels, optionally performs manual review, and saves subject-level outputs.

## Configuration

Key settings are defined in `src/get_config.m`:

- `config.path_data_in` — input `.dat` directory
- `config.path_results_out` — output directory
- `config.subjects` — subject IDs to process
- `config.measurements` — measurement IDs to process
- `config.fs` — native/master sampling rate
- `config.data_columns` — input channel names
- `config.input_filename_pattern` — input filename pattern
- `config.overwrite_results` — recompute existing label results
- `config.overwrite_features` — recompute existing respiratory features
- `config.make_figs_visible` — show/hide figures during batch processing
- `config.detrend.*` — respiratory-belt detrending settings
- `config.resp.*` — respiratory peak/trough extraction and breath-review settings
- `config.reference.*` — common session physiological-reference interval and modality-specific reference/QC settings
- `config.shallow` / `config.deep` — shallow/deep settings
- `config.slow` / `config.rapid` — slow/rapid settings
- `config.irregular` — irregularity settings
- `config.apnea` — apnea-like pause settings
- `config.sigh` — sigh settings
- `config.csr` — periodic-breathing settings
- `config.thoracic` — thoracic-dominance settings
- `config.async` — respiratory-asynchrony settings
- `config.desat` — SpO2/desaturation settings
- `config.LabelEdit.*` — final manual label-review settings

The same reviewed respiratory peaks, troughs, amplitudes, inter-breath intervals, and respiratory rates are reused across detectors; individual labels do not redetect breaths.

## Common Session Physiological Reference

Each recording has one fixed three-minute temporal reference interval:

- measurements M1 and M3: 3–6 min
- measurements M2 and M4: 19–22 min

The interval is resolved once on the native `config.fs` timeline. Its indices are inclusive and its times are half-open: `[reference_start_t, reference_end_t)`. If a recording ends within the requested interval, the available tail is explicitly marked as truncated; if it ends before the requested start, the reference interval is unavailable. The interval is never shifted to another part of the recording.

Respiratory excursion, SpO2, respiratory-asynchrony coherence, and raw respiratory motion/slope each calculate their own statistic from this same interval. Sharing the time interval does not share a numerical normalization scale across modalities, and an unavailable statistic for one modality does not invalidate the others. Reference-quality warnings retain the data by default and do not trigger automatic correction, interval movement, or threshold tuning.

Respiratory excursion is calculated independently for each usable belt as the median of finite positive respiratory-cycle excursions in the interval, with at least 10 qualifying cycles required. There is no whole-record fallback. The whole-record stability comparison remains descriptive respiratory QC and is not a second reference interval.

## Conditions for Detecting Individual Physiological Events

The thresholds below are operational research criteria and should not be interpreted as universal clinical diagnostic cutoffs.

- **`shallow`** — all eligible breaths in a trailing 30-s candidate window have session-normalized excursion between 0.65 and 0.80. Final boundaries are localized from qualifying respiratory cycles, and the localized state must last at least 30 s.

- **`deep`** — all eligible breaths in a trailing 30-s candidate window have session-normalized excursion `>= 1.20`. Final boundaries are localized from qualifying respiratory cycles, and the localized state must last at least 30 s.

- **`slow`** — a full trailing 60-s window estimates respiratory rate as `RR = 60 / mean(IBI)` and confirms a candidate when `RR <= 10 bpm`. Final boundaries are localized from consecutive respiratory-cycle intervals with breathwise `RR_i <= 10 bpm`; only localized runs lasting at least 30 s become final events.

- **`rapid`** — a full trailing 60-s window estimates respiratory rate as `RR = 60 / mean(IBI)` and confirms a candidate when `RR >= 20 bpm`. Final boundaries are localized from consecutive respiratory-cycle intervals with breathwise `RR_i >= 20 bpm`; only localized runs lasting at least 30 s become final events.

- **`irregular`** — respiratory-rhythm variability is assessed over 60-s IBI windows. The default criterion is `CV_IBI >= 0.30`, with long pauses excluded from irregularity estimation. Because irregularity is intrinsically window-based, event boundaries retain window-scale uncertainty.

- **`apnea`** — apnea-like low-motion evidence is detected either from very low normalized respiratory excursion (`<= 10%` of the session reference) or from sustained raw-belt flatness/low motion. Events must last at least 10 s. This label represents respiratory pause/low-motion evidence, not confirmed airflow cessation or central/obstructive apnea.

- **`sigh`** — isolated unusually large breaths are detected as whole-record amplitude outliers. The default rule combines the 98th percentile, an IQR-based outlier threshold, and a minimum amplitude ratio of 2.0. Sighs are discrete breath events.

- **`csr`** — Cheyne-Stokes-like / periodic breathing requires at least two adjacent waxing-waning respiratory cycles satisfying the configured cycle-duration, shape, breath-count, and modulation criteria.

- **`thoracic`** — thoracic dominance is assessed from independently normalized thoracic and abdominal excursion. The operational condition is a 30-s thoracic-to-abdominal ratio `T/A >= 1.5`. Both belts are required. Because the measure is window-based, boundaries retain explicit temporal uncertainty.

- **`async`** — thoracoabdominal asynchrony is assessed from time-localized wavelet phase coherence between the two belts. Respiratory signals are temporarily downsampled to 20 Hz for this analysis only. Sustained session-reference-relative low-coherence evidence must persist for at least 30 s.

- **`desat`** — SpO2 is `< 90%` or decreases by at least 3 percentage points from the valid session reference for at least 10 s.

Amplitude-dependent sustained labels use participant/session-relative respiratory excursion rather than absolute tidal volume. Respiratory belts are uncalibrated, so raw amplitudes should not be compared directly across subjects.

For `shallow`, `deep`, `slow`, and `rapid`, rolling evidence confirms a candidate but does not define its final onset and offset. Respiratory-cycle evidence localizes every contiguous qualifying run inside that candidate. The configured `min_dur_sec` is then applied once to each localized run. Passing runs become final automatic events; shorter runs remain in `results.event_boundary_info` as rejected QC evidence, including their duration, minimum duration, shortfall, evidence source, and temporal uncertainty. Diagnostic plots show rolling/candidate support, all localized qualifying support, and the final retained state even when no final event remains.

`irregular` and `thoracic` remain aggregate-window events with explicit boundary uncertainty because no finer localization is defensible from their current evidence. `apnea` retains its detector-specific breath-amplitude and raw-flat localization paths.

All canonical event times are half-open intervals `[start_t,end_t)`, while `start_idx:end_idx` are inclusive sample indices:

```text
start_t = (start_idx - 1) / fs
end_t   = end_idx / fs
duration = (end_idx - start_idx + 1) / fs
```

Saved indices are authoritative when legacy manual annotations are migrated. A one-sample event therefore has duration `1/fs`.

## DB Phenotypes

The 11 automatic labels are elementary physiological patterns, not 11 clinical DB phenotypes. The repository also stores evidence relevant to five prespecified candidate DB phenotypes:

- **Hyperventilation syndrome** — rapid/deep breathing can provide supportive respiratory-pattern evidence, but clinical assessment requires additional information such as ETCO2/capnography, ventilation relative to metabolic demand, exercise testing, symptoms, and questionnaire data.
- **Periodic deep sighing** — characterized using sigh frequency together with respiratory irregularity and other respiratory features; it is distinct from `csr`.
- **Thoracic-dominant breathing** — supported by the `thoracic` label and continuous thoracoabdominal-balance measures; the belt-derived measure is relative and uncalibrated.
- **Forced abdominal expiration** — not reliably identifiable from respiratory belts alone because belt motion does not establish active expiratory abdominal-muscle recruitment.
- **Thoracoabdominal asynchrony** — supported by the `async` label and continuous coherence-based evidence.

Level 1 is defined as “elementary physiological labels and evidence.” Automatic versus manually reviewed provenance is represented separately rather than embedded in that level name. These phenotype profiles are descriptive and non-diagnostic. External clinical data are integrated separately when available.

## Manual Controls

Manual review is optional and controlled in `src/get_config.m`:

- `config.resp.manual_control` — opens the respiratory peak editor before label detection. Added/removed breath peaks affect all downstream respiratory features and labels.
- `config.sigh.manual_control` — opens the sigh-specific breath editor for adding or removing sigh markers.
- `config.LabelEdit.manual_control` — opens the final interval editor for automatic labels other than sigh.
- `config.LabelEdit.apply_saved_edits` — reapplies previously saved manual label edits on rerun.
- `config.LabelEdit.save_edits` — saves manual event edits to a separate manual-label file.
- `config.LabelEdit.start_from` — uses either immutable `automatic` annotations or the `latest_reviewed` annotations as the GUI starting state.
- `config.LabelEdit.replace_reviewed` — makes the completed round the active latest reviewed layer while retaining all earlier rounds.
- `config.LabelEdit.reviewer_role` — stores a flexible, non-identifying role such as `researcher`, `clinician`, or `expert` with the round.
- `config.LabelEdit.rewrite_changed_figures` — regenerates only diagnostic figures for labels whose reviewed intervals changed.

Automatic annotations are always preserved separately from manually reviewed annotations. For a later expert review, set `start_from = 'latest_reviewed'`; the editor then opens the previous reviewed values instead of requiring relabeling from scratch. Edits replace values only inside the newly viewed regions, while prior reviewed values remain outside that scope. Each completed round has its own coverage mask, reviewer role, source, annotations, and status in `results.review_history`. The active round is summarized by `results.review_provenance`.

Review coverage is stored explicitly per round, so an unreviewed sample is not interpreted as a manually confirmed negative. Starting from earlier reviewed annotations never promotes the earlier reviewer’s coverage to the new reviewer’s coverage.

Reviewed availability requires at least one sample that is both reviewed and scientifically assessable. In particular, a desaturation review covering only non-finite SpO2 samples, or an asynchrony review covering only invalid wavelet-evidence samples, remains unavailable rather than becoming a reviewed negative.

## Outputs

Each subject/measurement is written under:

```text
<config.path_results_out>/Sub<subject>_M<measurement>/
```

Main outputs:

- `Sub<subject>_M<measurement>_labels.mat` — complete MATLAB result structure
- `Sub<subject>_M<measurement>_labels.h5` — ML-ready HDF5 export
- diagnostic figures — generated for modules with `do_plot = true`
- `*_manual_label_events.mat` — saved manual interval edits, when enabled

The most important result fields include:

- automatic annotations, frozen before manual review: `results.events_automatic`, `results.mask_automatic`
- manually reviewed annotations: `results.events_reviewed`, `results.mask_reviewed`
- review coverage: `results.gold_review_mask`
- review history and active provenance: `results.review_history`, `results.review_provenance`
- label names and availability: `results.label_names`, `results.label_available`, `results.label_assessable_mask`
- reviewed availability: `results.label_reviewed_available`, `results.label_reviewed_assessable_mask`
- common temporal reference: `results.session_reference`
- modality-specific references: `results.resp_ref`, `results.spo2_ref`, plus ReA and raw-apnea reference provenance in `results.detector_diagnostics`
- respiratory cycles: `results.resp_cycles`
- respiratory features: `results.resp_features`
- event-boundary information: `results.event_boundary_info`
- automatic/reviewed burden, overlap, and evidence summaries: `results.label_burden_automatic`, `results.label_burden_reviewed`, `results.label_overlap_summary_automatic`, `results.label_overlap_summary_reviewed`, `results.label_evidence_summary_automatic`, `results.label_evidence_summary_reviewed`
- DB phenotype evidence
- full run configuration and input-channel provenance

Additional detector diagnostics and intermediate evidence can be inspected directly in the saved `results` structure or in the HDF5 hierarchy.

The HDF5 export schema is `magma_ml_hdf5_v4`. Automatic annotations are stored under `/labels/automatic_mask`, `/events/automatic`, `/burden/automatic`, and `/overlap/automatic`; reviewed annotations retain their corresponding `/reviewed` paths. `/review/provenance` and `/review/history` expose round metadata, annotations, and exact per-round coverage. The export stores the common metadata once under `/session_reference`, independent respiratory-belt statistics under `/resp_reference`, and the SpO2 statistic under `/spo2_reference`.

Group-level summaries are written under the `group_analysis/` output directory. `cohort_localized_boundary_qc.csv` preserves every localized-run duration and duration shortfall; `cohort_label_qc_summary.csv` aggregates rejected-run counts, medians, upper tails, maxima, and the smallest shortfall per label. These outputs are descriptive QC and never change thresholds automatically.

Cross-subject interpretation is intentionally separated by scale: respiratory rate, event duration/fraction, SpO2, and timing are absolute/comparable; belt-amplitude ratios, shallow/deep excursion ratios, and global/session ratios are within-record normalized; raw belt amplitude is not safely comparable across subjects.

## Artificial Test Signals

Artificial recordings for detector testing can be generated with:

```matlab
config = get_config();
create_artificial_test_data(config);
```

The generated datasets target the 11 canonical labels in the fixed order listed at the top of this README. Other labels may legitimately overlap the intended target.

## License

MIT License
