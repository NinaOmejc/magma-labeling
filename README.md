# MAGMA Physiological Event Labeling Pipeline

MATLAB-based physiological signal processing pipeline for detecting respiratory dysfunction events in single-subject recordings.

Detected labels include:

- Shallow breathing
- Irregular breathing
- Slow breathing (bradypnea)
- Rapid breathing (tachypnea)
- Respiratory asynchrony
- Desaturation (SpO2)
- Apnea
- Sigh
- Cheyne-Stokes-like / periodic breathing
- Deep breathing (relative increased belt excursion)
- Thoracic-dominant breathing (relative thoracoabdominal excursion dominance)

The pipeline processes multi-channel physiological recordings and saves structured event annotations, label masks, diagnostic signals, features, and figures. Original label definitions are in `Labels.docx`.

## Download And Setup

Clone with Git:

```bash
git clone https://github.com/NinaOmejc/magma-labeling.git
cd magma-labeling
```

Or download the ZIP from GitHub with **Code > Download ZIP**, then extract it.

## Run Single-Subject Analysis

1. Open MATLAB.
2. Set the repository root as your working directory.
3. Add `src/` to the MATLAB path:

```matlab
addpath(genpath(fullfile(pwd, 'src')));
```

4. Edit `src/get_config.m` to choose the `subjects` and `measurements` to process.
5. Edit `src/get_config.m` if paths, detector settings, plotting, or manual review options need to change.
6. Run:

```matlab
run('src/main_single.m')
```

`main_single.m` loops over the selected subjects and measurements, loads each recording, preprocesses the data, extracts respiration and SpO2 features, computes the respiratory and SpO2 references, builds common physiological evidence, runs all label detectors, builds the label mask, and saves outputs.

## Configuration

All main settings are defined in `src/get_config.m`.

Key parameters:

- `config.fs` - native and master sampling rate for all aligned signals (200 Hz for MAGMA recordings)
- `config.path_data_in` - input `.dat` file directory
- `config.path_results_out` - output directory
- `config.subjects` - subject identifiers to process
- `config.measurements` - measurement identifiers to process
- `config.data_columns` - input column names; at least one respiratory belt is required and SpO2 is optional
- `config.input_filename_pattern` - raw input filename pattern, with `{subject}` and `{measure}` placeholders
- `config.make_figs_visible` - show or hide figures during batch runs
- `config.overwrite_results` - recompute labels when a saved label file already exists

Each detector has its own settings block, for example `config.ShB`, `config.DeB`, `config.TDB`, `config.IrB`, `config.SlB`, `config.RaB`, `config.ReA`, `config.Des`, `config.Apn`, `config.Sig`, and `config.CSR`.

Preprocessing preserves the native sample count and alignment of every channel. It detrends only the configured respiratory belts. Respiratory-asynchrony analysis alone creates a temporary, anti-aliased 20 Hz representation controlled by `config.ReA.analysis_fs`; its results are mapped back to the 200 Hz master timeline.

`config.resp_ref` defines one fixed protocol/session amplitude reference independently for each usable belt. Measurements M1/M3 use reviewed breaths from minutes 2–7; M2/M4 use minutes 18–23. The session median normalizes amplitude-dependent shallow/deep and breath-amplitude apnea logic. Sigh detection intentionally uses the whole-record median because it is a global outlier detector.

`results.resp_ref` also retains whole-record values and early/late stability diagnostics. A step candidate, edge disagreement, or gradual/complex pattern is a descriptive `reference_quality` warning. The default action for every warning is **retain data, no correction**; warnings neither request manual correction nor automatically drift-correct the reference. A session reference becomes unavailable only when its belt lacks enough reviewed, finite positive breaths.

Respiratory belts are uncalibrated. Their raw amplitudes do not represent absolute tidal volume and are not safely comparable between subjects. A globally low-excursion recording can also look normal after within-record normalization, so amplitude ratios must be interpreted as within-record measures.

### Common Physiological Evidence

`compute_physiological_features` deterministically builds `phys_feat` from reviewed `resp_feat`, `resp_ref`, and `spo2_feat`; it does not redetect breaths and has no separate cache. Its current provenance version is `independent_physiological_evidence_v2`. Version 2 records the independent 11-label evidence architecture, Deep evidence, thoracoabdominal-balance evidence, and explicit endpoint-versus-state temporal semantics. This version belongs to the derived `phys_feat` structure and does not invalidate reviewed `resp_feat` caches.

`phys_feat.resp.lungs` and `phys_feat.resp.diaph` preserve the reviewed `peak_idx`, `peak_t`, `amp`, `ibi`, and `rr_bpm` independently. Derived fields include session/global amplitude ratios, configured slow/rapid rate traces, shallow and deep amplitude masks, apnea amplitude-ratio evidence, and irregularity traces. Deep evidence is `amp_ratio_session >= config.DeB.amp_ratio_thr` with no upper cutoff.

`phys_feat.resp.thoracoabdominal_balance` stores cross-belt evidence only when both fixed session references are available and at least one common window contains sufficient evidence. It computes 30-second robust medians `T` and `A` from thoracic and abdominal `amp_ratio_session`, then stores `T/A`, `log(T/A)`, and `T/(T+A)`. `dominance_endpoint_mask` identifies qualifying trailing windows and `dominance_state_mask` contains the union of their preceding 30-second support intervals. `thorDomB` uses the provisional weak-label rule `T/A >= 1.5` and a 30-second minimum inferred state. It does not require a second 30-second run of qualifying endpoints. These are within-record relative excursion measures, not calibrated percent rib-cage contribution or absolute thoracic dominance; a recording that is already thoracic-dominant throughout its reference interval may not be detected.

The alignment convention is explicit: `amp(i)` belongs to peak `i` and the final amplitude may be `NaN` because no following peak closes that excursion. `ibi(i)` and `rr_bpm(i)` describe the interval from peak `i` to peak `i+1`, so they contain one fewer value than the peak arrays. Invalid, non-positive amplitudes remain present in the copied `amp` array but become `NaN` in normalized ratio fields. A missing session reference never falls back to the global reference.

SpO2/desaturation is an independent evidence stream at `phys_feat.spo2`. `phys_feat` contains no combined respiratory+SpO2 features. Respiratory labels do not inspect SpO2 to rename or suppress their events; simultaneous phenomena are represented by overlapping independent events and `true` values in multiple mask columns.

### Detector Temporal Semantics

For rolling detectors, an **evidence endpoint** means that the trailing analysis window ending at that time qualified. An **inferred state** is the union of complete support intervals for qualifying windows. `min_dur_sec` is applied once to the inferred state. Event boundaries are mapped from that retained state to the native `config.fs` sample timeline.

- Shallow: every eligible breath in a trailing 30-second window must have `0.65 <= amp_ratio_session <= 0.80`. Qualifying windows are backfilled; the inferred state must last at least 30 seconds. Rate and SpO2 are unused.
- Deep: every eligible breath in a trailing 30-second window must have `amp_ratio_session >= 1.20`, with no upper bound. Qualifying windows are backfilled; the inferred state must last at least 30 seconds.
- Slow: mean rate from a trailing 60-second window must be `<= 10 bpm`. The qualifying window supports the inferred state, whose minimum duration is 30 seconds. The first evidence endpoint can therefore occur after the reported inferred-state onset.
- Rapid: mean rate from a trailing 30-second window must be `>= 20 bpm`. `analysis_win_sec=30` and `min_dur_sec=30` are separate parameters; a qualifying window supports its preceding interval and does not start another hidden 30-second requirement.
- Irregular: CoV/robust-CoV/RMSSD are estimated from a trailing 60-second IBI window, with pause exclusion. A qualifying window is backfilled and the current minimum inferred-state duration remains 60 seconds. `detection_metric='cov'` remains the default.
- Apnea-like respiratory pause: normalized-amplitude endpoints summarize a trailing 10-second window and are backfilled. Raw-flat motion/slope/plateau evidence already marks its supporting windows. The pathways are unioned and the 10-second minimum state rule is applied once. This remains a low-motion/pause weak label, not a definitive obstructive or central apnea diagnosis.
- Thoracic dominance: a qualifying 30-second `T/A >= 1.5` window supports its complete preceding window; the 30-second minimum state is applied once.
- Respiratory asynchrony: signals are locally resampled to 20 Hz, time-localized wavelet coherence uses the configured cycle-based window, and baseline-relative low-coherence samples must persist for 30 seconds. No additional backfilled state window is imposed. Reported boundaries are retained low-coherence runs mapped to the native timeline.
- CSR-like periodic breathing: events span the first through last trough of at least two adjacent qualifying waxing--waning cycles. Cycle duration, shape, modulation, and breath-count requirements define the event; no additional generic duration filter is added.
- Desaturation: the sample-level condition is `SpO2 < 90%` or a drop of at least 3 percentage points from a valid baseline, retained for at least 10 seconds. No rolling respiratory state semantics are applied.
- Sigh: a selected breath is a discrete event bounded by midpoints to neighboring respiratory peaks. It uses the intentional whole-record amplitude reference and no sustained-state duration rule.

Endpoint masks, inferred-state masks, threshold margins, rate/amplitude traces, irregularity pause exclusions, thoracoabdominal ratios, apnea pathway support, ReA coherence diagnostics, sigh thresholds, and periodic-cycle diagnostics are retained in `phys_feat`, `diagnostic_signals`, or `detector_diagnostics`. They stay in their native interpretable scales; no generic confidence or probability is assigned.

### Evidence-Aware Availability

`results.input_config.running_labels` means only that the required channels were usable enough to attempt a detector. Final scientific assessability is computed centrally after evidence extraction and specialized analyses. `results.label_available` and the aligned controlled strings in `results.label_availability_reason` distinguish `available`, `no_respiratory_belt`, `no_session_reference`, `insufficient_resp_features`, `missing_spo2`, `invalid_spo2`, `one_belt_only`, `respiratory_asynchrony_analysis_invalid`, `insufficient_thoracoabdominal_evidence`, and `detector_analysis_failed`.

Thus, for example, two physical belt columns do not make `asyncB` available when the wavelet analysis fails, and a physically present SpO2 column does not make `desat` available when its samples or baseline are unusable. An available detector with no events remains a true zero; an unavailable detector has `NaN` burden.

### MAGMA DB Phenotype Evidence

The repository now distinguishes three levels:

1. The 11 elementary signal-derived weak physiological labels and their evidence.
2. Five prespecified MAGMA WP1 DB phenotype-evidence structures.
3. Later data-driven clusters or phenotype discovery.

The 11 elementary labels are not 11 clinical DB phenotypes, and the five WP1 phenotypes are not mutually exclusive sample-level classes. `results.db_phenotype_evidence` contains descriptive signal-derived measures, assessability, required external data, and limitations:

- Hyperventilation syndrome: rapid/deep burdens, overlap, rate, and normalized excursion are respiratory-pattern support only. Definitive assessment is not available from belts alone and requires later ETCO2/capnography, ventilation relative to metabolic demand, exercise testing, clinical assessment, and questionnaire information. It is never defined as `rapidB & deepB`.
- Periodic deep sighing: represented continuously by sigh count/rate, irregular burden, deep burden, and sigh--irregular association. It is explicitly distinct from CSR-like periodic breathing and has no invented clinical cutoff.
- Thoracic-dominant breathing: uses `thorDomB` burden and continuous normalized balance measures. It remains relative within-record evidence from uncalibrated belts.
- Forced abdominal expiration: explicitly not assessable from the current belt-only signal layer. Belt motion cannot establish active expiratory abdominal-muscle recruitment; clinical or direct muscle/mechanical evidence is required.
- Thoraco-abdominal asynchrony: uses `asyncB` burden and ReA coherence/deviation evidence. It remains algorithmic evidence rather than a clinical diagnosis and is not merged with thoracic dominance.

Plot behavior is controlled per module:

- `config.<module>.do_plot = true` generates and saves that module's diagnostic figure(s).
- `config.<module>.do_plot = false` skips generating/saving that module's diagnostic figure(s).

Manual review can be enabled at three levels:

- `config.resp.manual_control` - opens a breath peak editor before label detection. Edited peaks/troughs affect all downstream respiratory labels.
- `config.Sig.manual_control` - opens the sigh-specific breath-level editor for adding or removing sigh markers.
- `config.LabelEdit.manual_control` - opens the final event-interval editor after automatic detection and before the final label mask is saved. This editor handles `shallowB`, `deepB`, `thorDomB`, `irregB`, `slowB`, `rapidB`, `asyncB`, `desat`, `apnea`, and `CSR`; sigh is excluded because it has its own editor.

Final manual label edits are controlled by:

- `config.LabelEdit.apply_saved_edits` - reuse previously saved manual event edits on rerun, even if the GUI is disabled.
- `config.LabelEdit.save_edits` - save the edited per-label event intervals in a separate `*_manual_label_events.mat` file.
- `config.LabelEdit.rewrite_changed_figures` - after manual editing, overwrite only the label diagnostic images whose intervals changed; unchanged label images are left untouched.

## Input Data Format

Each recording is expected as a numeric `.dat` file whose columns match `config.data_columns`.
The default MAGMA configuration remains the original 6-column order:

1. ECG1
2. ECG2
3. SpO2
4. Resp-Lungs
5. Blood Pressure
6. Resp-Diaphragm

Rows are time samples and columns are signals. The raw sampling rate must match `config.fs`.

For external data, `config.data_columns` can also list only the available signals, for example:

```matlab
config.data_columns = {'SpO2', 'Resp-Lungs', 'Resp-Diaphragm'};
config.data_columns = {'Resp-Lungs', 'Resp-Diaphragm'};
config.data_columns = {'Resp', 'SpO2'};
config.data_columns = {'Resp'};
```

Accepted respiratory aliases include `Resp-Lungs`, `Lungs`, `Thorax`, `Chest`, `Resp-Diaphragm`, `Diaphragm`, `Abdomen`, `Resp`, `RespiratoryBelt`, and `Respiration`.
Accepted oxygen-saturation aliases include `SpO2`, `SpO₂`, `Spo2`, `SaO2`, and `OxygenSaturation`.
If only one belt is present, one-belt respiratory labels still run and respiratory asynchrony is skipped. If SpO2 is absent, only independent desaturation detection is skipped.

`results.input_config` distinguishes physical channels from effectively usable belts. The known lung-belt exclusion for subjects 1–20 in M1/M2 reduces the effective belt count to one, so `asyncB` and `thorDomB` are marked unavailable while diaphragm-based labels remain available.

The loader resolves available channels from `config.data_columns` and records the resolved channel configuration in `results.input_config`. This allows the same pipeline and plotting/manual-review interfaces to run on the full MAGMA signal set as well as smaller external files with only the available respiratory and/or SpO2 channels.

The expected filename pattern is:

```text
ECG1_ECG2_SpO2_RespL_BP_RespD_fs200_Sub<subject>_Pom<measure>_DeTr_Norm.dat
```

For example:

```text
ECG1_ECG2_SpO2_RespL_BP_RespD_fs200_Sub42_Pom1_DeTr_Norm.dat
```

## Outputs

For each subject and measurement, the pipeline creates one output folder:

```text
<config.path_results_out>/
  Sub42_M1/
    Sub42_M1_labels.mat
    Sub42_M1_raw_data.png
    Sub42_M1_label_mask.png
    Sub42_M1_rapid_breathing.png
    Sub42_M1_slow_breathing.png
    Sub42_M1_desaturation.png
    Sub42_M1_manual_label_events.mat
    ...
```

A saved label file contains fields like:

```matlab
results.subject            = config.subject;      % Subject identifier
results.measure            = config.measure;      % Measurement identifier
results.events             = sub_events;          % Detected event struct array
results.mask               = label_mask;          % Sample-level label mask [N x labels]
results.label_names        = label_names;         % Label names matching mask columns
results.label_available    = label_available;     % Assessed/available status matching mask columns
results.label_availability_reason = label_availability_reason; % Controlled reason matching label order
results.label_schema_version = config.label_schema_version; % Explicit canonical-label schema
results.resp_feat          = resp_feat;           % Respiratory features for lungs and diaphragm
results.resp_ref           = resp_ref;            % Fixed session/global respiratory references and descriptive QC
results.phys_feat          = phys_feat;           % Common derived physiological evidence used by detectors
results.spo2_feat          = spo2_feat;           % SpO2 features and desaturation candidates
results.diagnostic_signals = diagnostic_signals;  % Continuous detector-adjacent signals
results.detector_diagnostics = detector_diagnostics; % Specialized apnea/ReA/sigh/CSR evidence
results.label_burden       = label_burden;        % Per-label availability, duration, fraction, event count
results.label_overlap_summary = label_overlap_summary; % Prespecified directional overlaps
results.label_evidence_summary = label_evidence_summary; % Recording-level native-scale evidence
results.db_phenotype_evidence = db_phenotype_evidence; % Five non-diagnostic WP1 phenotype structures
results.manual_label_edit  = manual_label_edit;   % Manual edit metadata and changed label list
results.rewritten_manual_label_figures = rewritten_manual_label_figures; % Figures rewritten after manual interval edits
results.baseline           = baseline;            % Static SpO2 and label-specific baseline interval
results.input_config       = config.input_config; % Resolved channels and skipped/running labels
results.config             = config;              % Full configuration used for this run
```

`results.events` and `results.mask` already include accepted manual edits. The separate `Sub*_M*_manual_label_events.mat` file stores the edited per-label event sets before final merging/normalization, so the same human edits can be reused on rerun and compared against newly detected automatic events.

`results.measure` is the saved measurement identifier.

Saved manual interval edits use schema version 2 and record their editable label names. Version-1 files are migrated by event-set field identity: interval boundaries are preserved, historical compound types are reduced to that field's canonical label, and labels absent from the old file retain their current automatic events rather than being interpreted as manually reviewed negatives.

## Group-Level Measure Comparability

`build_group_label_table` writes `group_analysis/group_measure_comparability.csv` alongside the group summary. Interpret group outputs in three classes:

- Absolute/comparable across subjects: respiratory rate (bpm), event durations/fractions, SpO2, and timing measures.
- Within-record normalized: belt amplitude ratios, shallow/deep excursion measures, and the whole-record/session amplitude ratio.
- Within-record normalized: thoracic-to-abdominal normalized excursion ratio, its log ratio, and thoracic relative fraction.
- Not safely comparable across subjects: raw belt amplitude or raw session/global belt reference values.

Group label summaries include `label_<name>_available`. An unavailable or historically absent label has availability `0` and `NaN` duration/fraction; an assessed label with no events has availability `1` and zero duration/fraction.

Within each new result file, `label_burden.by_label.<name>` stores `available`, `duration_sec`, `fraction`, `event_count`, and `assessable_duration_sec`. The reusable burden helper accepts a per-sample assessability mask when partial availability is known; with the current recording-level availability architecture, an available label uses the recording as its assessable interval and a wholly unavailable label returns `NaN` burden. Sigh also stores `sigh_count` and `sighs_per_15_min`. Label fractions overlap and must not sum to one.

`label_overlap_summary` stores derived directional overlap for only four prespecified pairs: rapid--Deep, sigh--irregular, apnea--desaturation, and thoracic-dominance--asynchrony. It distinguishes the fraction of A overlapped by B from the fraction of B overlapped by A. These statistics do not create compound events or mask columns.

## Artificial Test Signals

To generate eleven artificial target-label datasets from source recording Sub1/M1, run:

```matlab
config = get_config();
create_artificial_test_data(config);
```

This creates ignored local files under `test_data/` named as `Sub0_Pom1` through `Sub0_Pom11`. Measurements map to labels in order: `shallowB`, `irregB`, `slowB`, `rapidB`, `asyncB`, `desat`, `apnea`, `sigh`, `CSR`, `deepB`, and `thorDomB`. The Deep example scales both respiratory-belt excursions to 1.60 times their template excursion during the default 8–10 minute test interval, without changing respiratory timing or SpO2; that interval is outside the standard M1/M3 session-reference window. The thoracic-dominance target increases thoracic and decreases abdominal excursion without intentionally changing rate or SpO2. Other independent labels may validly overlap a target label.

## Event Struct Format

Each event contains:

- `type` - one of the canonical labels: `shallowB`, `irregB`, `slowB`, `rapidB`, `asyncB`, `desat`, `apnea`, `sigh`, `CSR`, `deepB`, `thorDomB`
- `start_idx`, `end_idx` - sample indices
- `start_t`, `end_t` - event times in seconds
- `duration` - event duration in seconds
- `belt` - respiratory provenance: `lungs`, `diaph`, `both`, or empty when not belt-specific

Every event represents one phenomenon. For example, concurrent rapid and deep breathing are two overlapping events and two simultaneous `true` mask columns; no compound subtype is created. Older short event names such as `RaB`, `Apn`, or `Sig` remain accepted by the normalization helper, but unrecognized or compound event types are rejected before final mask construction.

## License

MIT License
