# MAGMA Physiological Event Labeling Pipeline

MATLAB-based pipeline for detecting and reviewing respiratory and oxygenation events in single-subject physiological recordings.

Canonical label names, metadata, and fixed order are defined by `get_labels.m`.

The labels are independent and may overlap in time. They represent signal-derived physiological patterns rather than mutually exclusive clinical dysfunctional-breathing diagnoses. Original label definitions are available in `Labels.docx`.

Historical names are mapped by explicit name identity, never by column position.

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
- `config.periodic` — periodic-breathing settings
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

Breath amplitude, raw respiratory-belt excursion, SpO2, and respiratory-asynchrony coherence each calculate their own statistic from this same interval. Sharing the time interval does not share a numerical normalization scale across modalities, and an unavailable statistic for one modality does not invalidate the others. Reference-quality warnings retain the data by default and do not trigger automatic correction, interval movement, or threshold tuning.

For each usable belt, the fixed breath-amplitude reference is the median of finite positive respiratory-cycle amplitudes in the interval, with at least 10 qualifying cycles required. The fixed raw-excursion reference is calculated independently as the P95-P5 excursion of finite raw belt samples in the same interval, subject to the configured finite-coverage requirement. There is no whole-record fallback. The whole-record stability comparison remains descriptive respiratory QC and is not a second reference interval.

## Conditions for Detecting Individual Physiological Events

The thresholds below are operational research criteria and should not be interpreted as universal clinical diagnostic cutoffs.

- **`shallow`** — all eligible breaths in a trailing 30-s candidate window have session-normalized excursion between 0.10 and 0.80. Final boundaries are localized from qualifying respiratory cycles, and the localized state must last at least 30 s.

- **`deep`** — all eligible breaths in a trailing 30-s candidate window have session-normalized excursion `>= 1.20`. Final boundaries are localized from qualifying respiratory cycles, and the localized state must last at least 30 s.

- **`slow`** — a full trailing 60-s window estimates respiratory rate as `RR = 60 / mean(IBI)` and confirms a candidate when `RR <= 10 bpm`. Final boundaries are localized from consecutive respiratory-cycle intervals with breathwise `RR_i <= 10 bpm`; only localized runs lasting at least 30 s become final events.

- **`rapid`** — a full trailing 60-s window estimates respiratory rate as `RR = 60 / mean(IBI)` and confirms a candidate when `RR >= 20 bpm`. Final boundaries are localized from consecutive respiratory-cycle intervals with breathwise `RR_i >= 20 bpm`; only localized runs lasting at least 30 s become final events.

- **`irregular`** — respiratory-rhythm variability is assessed over 60-s windows using complete IBIs contained within each window. The detection criterion is `CV_IBI >= 0.30`; robust CoV is retained only as a descriptive trace. The merged window support directly defines final events, so no scientifically distinct candidate stage is stored.

- **`apnea`** — apnea uses a 10-s defining duration (`config.apnea.min_dur_sec`). For each belt and complete 10-s window, breath evidence is preferred: when at least one valid breath amplitude is available, every valid amplitude must be `<= 10%` of that belt's fixed session breath-amplitude reference. Only when breath evidence is not evaluable is the raw excursion fallback used, requiring the window's raw P95-P5 excursion to be `<= 10%` of the fixed session raw-excursion reference. If both belts are evaluable, both must support apnea; if only one is evaluable, that belt is used. Final combined support must persist for at least 10 s. This label represents respiratory pause/low-motion evidence, not confirmed airflow cessation or central/obstructive apnea.

- **`sigh`** — isolated unusually large inspirations are detected breath by breath. The default `rolling_median_2x` method uses the inspiratory excursion from the preceding trough to the peak and flags amplitudes at least twice a centered 15-breath rolling median, with shortened edge windows and at least three valid amplitudes. The previous `global_ratio_outlier` and `legacy_60s` methods remain selectable. Set `config.sigh.compare_methods = true` to report and plot rolling/global agreement. Sighs are discrete breath events.

- **`periodic`** — periodic breathing / Cheyne-Stokes-like respiratory-effort evidence is computed with both eAMI and a MAGMA adaptation of the Guyot demodulation / Matrix Pencil method. `config.periodic.primary_method` explicitly selects which method supplies the automatic `periodic` event set; both method results remain in detector diagnostics.

- **`thoracic`** — thoracic dominance is assessed from independently normalized thoracic and abdominal excursion. The operational condition is a 30-s thoracic-to-abdominal ratio `T/A >= 1.5`. Both belts are required. Pre-duration candidates retain the analysis-window uncertainty.

- **`async`** — thoracoabdominal asynchrony is assessed from time-localized wavelet phase coherence between the two belts. Respiratory signals are temporarily downsampled to 20 Hz for this analysis only. Sustained session-reference-relative low-coherence evidence must persist for at least 30 s.

- **`desat`** — SpO2 is `< 90%` or decreases by at least 3 percentage points from the valid session reference for at least 10 s.

### Periodic-Breathing Literature Methods

MAGMA computes two literature-based methods independently for every supported recording. The first is **eAMI**, following Fernandez Tellez et al. 2015 ([DOI 10.5665/sleep.4494](https://doi.org/10.5665/sleep.4494)). Each usable raw respiratory belt is band-pass filtered to isolate the respiratory carrier, resampled at `config.periodic.eami.resample_hz` (1 Hz by default), rectified, and low-pass filtered to obtain its amplitude envelope. Locally mean-removed carrier and envelope energies are compared with `eAMI = 1 - 0.5*log(E_resp/E_am)`. Evidence at or above 0.65 must persist after dynamic belt combination for twice `config.periodic.eami.energy_win_sec`; the 60-s default therefore yields a 120-s event requirement. The 60-s window is a MAGMA comparison choice, not a published optimum; the paper reports relatively stable behavior for windows above approximately 40 s.

The second method estimates modulation depth and frequency following Guyot et al. 2020 ([DOI 10.1371/journal.pone.0221191](https://doi.org/10.1371/journal.pone.0221191)). This is explicitly a **MAGMA adaptation**: reviewed `resp_cycles.<belt>.peak_t` and canonical `resp_cycles.<belt>.amp` replace the publication's change-point breath detector. Canonical breath amplitudes are linearly reconstructed on a 1-Hz ventilation envelope; interruptions longer than three median inter-breath intervals are set to zero, with no extrapolation outside the first and final valid breaths. An order-three Matrix Pencil model estimates DC plus a conjugate modulation pair in 120-s windows with 80% overlap. A window is pathological when `h > 0.12` and modulation frequency is within 8–30 mHz; combined evidence must persist for at least 60 s.

For each method, both evaluable belts must agree at a given time; a single evaluable belt is used when the other is unavailable. This dynamic belt rule is a MAGMA design choice rather than part of either publication. `config.periodic.primary_method` accepts `eami` or `guyot` and never unions, votes, or automatically switches methods. These outputs describe a periodic breathing / Cheyne-Stokes-like respiratory-effort pattern; without direct airflow they do not establish central sleep apnea or confirmed Cheyne-Stokes respiration.

Amplitude-dependent sustained labels use participant/session-relative respiratory excursion rather than absolute tidal volume. Respiratory belts are uncalibrated, so raw amplitudes should not be compared directly across subjects.

For `shallow`, `deep`, `slow`, and `rapid`, rolling evidence confirms a candidate but does not define its final onset and offset. Respiratory-cycle evidence localizes every contiguous qualifying run inside that candidate. The configured `min_dur_sec` is then applied once to each localized run. Passing runs become final automatic events; meaningful shorter runs remain in `results.candidate_events` with `accepted = false` and `rejection_reason = 'too_short'`. Diagnostic plots show rolling/candidate support, all localized qualifying support, and the final retained state even when no final event remains.

`irregular` remains an aggregate-window final event and therefore has no separate candidate stage. `thoracic` preserves pre-duration state runs as candidates with window-scale uncertainty. `apnea` retains its detector-specific breath-amplitude and raw-excursion fallback localization paths.

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
- **Periodic deep sighing** — characterized using sigh frequency together with respiratory irregularity and other respiratory features; it is distinct from the `periodic` label.
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
- review coverage: `results.review_coverage_mask`
- review history and active provenance: `results.review_history`, `results.review_provenance`
- label names and availability: `results.label_names`, `results.label_available`, `results.label_assessable_mask`
- reviewed availability: `results.label_reviewed_available`, `results.label_reviewed_assessable_mask`
- common temporal reference: `results.session_reference`
- modality-specific references: `results.resp_ref`, `results.spo2_ref`, plus ReA and raw-apnea reference provenance in `results.detector_diagnostics`
- respiratory cycles: `results.resp_cycles`
- respiratory features and their common analysis time: `results.resp_features`, including `results.resp_features.time_sec`
- genuine localized/pre-final intervals: `results.candidate_events`, including meaningful rejected `too_short` candidates
- unique detector-specific scientific evidence: `results.detector_diagnostics`
- automatic/reviewed burden, overlap, and evidence summaries: `results.label_burden_automatic`, `results.label_burden_reviewed`, `results.label_overlap_summary_automatic`, `results.label_overlap_summary_reviewed`, `results.label_evidence_summary_automatic`, `results.label_evidence_summary_reviewed`
- DB phenotype evidence
- full resolved per-recording configuration: `results.config`, with input-channel provenance nested at `results.config.input_config` rather than duplicated at the result top level

`results.events_automatic` contains final accepted automatic events. `results.candidate_events` is not a copy of those events: it stores a distinct pre-final stage only where the detector has one. `results.detector_diagnostics` retains compact, recording-specific evidence that is not already present in respiratory features, raw signals, configuration, or final events. A separate `diagnostic_signals` copy is not persisted; time-resolved evidence remains available from `results.resp_features` and compact detector diagnostics, while recording-level evidence summaries remain available for group analysis and ML. Raw and preprocessed physiological matrices remain in their authoritative HDF5 locations `/signals/raw` and `/signals/preprocessed`, not inside detector diagnostics.

The HDF5 export schema is `magma_ml_hdf5_v7`. Automatic annotations are stored under `/labels/automatic_mask`, `/events/automatic`, `/burden/automatic`, and `/overlap/automatic`; reviewed annotations retain their corresponding `/reviewed` paths, with coverage under `/labels/review_coverage_mask`. Candidate intervals are under `/events/candidate`, while `/review/provenance`, `/review/history`, and `/review/scope` preserve review metadata. Reviewed breath cycles, derived respiratory evidence, and unique detector evidence have one authoritative copy each under `/resp_cycles`, `/resp_features`, and `/detector_diagnostics`; periodic-breathing evidence is stored below `/detector_diagnostics/periodic`, with the eAMI grid and lung index at `/detector_diagnostics/periodic/eami/time_sec` and `/detector_diagnostics/periodic/eami/lungs/index`. References remain under `/session_reference`, `/resp_reference`, and `/spo2_reference`. Evidence summaries are under `/evidence_summary`, and the resolved recording configuration is under `/config`.

The immutable base analysis configuration is saved once as `analysis_configuration.mat` in `config.path_results_out` before recording-specific channel resolution or subject/measurement mutation. Each recording still carries its fully resolved `results.config`.

Group-level summaries are written under the `group_analysis/` output directory. `cohort_candidate_events.csv` preserves one row per compact candidate, including acceptance, stable rejection reason, and temporal uncertainty. `cohort_label_qc_summary.csv` aggregates rejected-candidate counts and duration distributions by label. Scalar evidence summaries and `trace_...` distribution columns are derived from the authoritative evidence owners without flattening full time-series samples into the group table. These outputs are descriptive QC and never change thresholds automatically.

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
