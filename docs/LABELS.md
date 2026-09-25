# MAGMA labels and phenotype evidence

MAGMA separates **elementary physiological labels** from **prespecified dysfunctional-breathing (DB) phenotype evidence**.

- **Level 1 — elementary physiological labels/evidence:** time-resolved signal-derived respiratory or physiological patterns.
- **Level 2A — full prespecified MAGMA DB phenotype evidence:** recording-level evidence profiles, detector summaries, QC, and provenance.
- **Level 2B — fixed compact phenotype representation:** exactly 21 raw recording-level variables in an authoritative order.
- **Level 3 — future data-driven phenotype discovery:** downstream unsupervised discovery from the fixed Level-2B representation.

Neither Level 1 nor Level 2 should be interpreted as a clinical diagnosis. Labels may overlap, and several phenotype patterns may coexist in the same recording or participant.

## Level 1 — elementary physiological labels/evidence

The canonical label set is defined in `src/get_labels.m`.

| Label | Long name | Primary evidence | Primary operational condition |
|---|---|---|---|
| `shallow` | Shallow breathing | Belt excursion | `0.10 < A/A_ref <= 0.80`, sustained >= 30 s |
| `deep` | Deep breathing | Belt excursion | `A/A_ref >= 1.20`, sustained >= 30 s |
| `slow` | Slow breathing | Respiratory rate | `RR <= 10 breaths/min`, 60-s estimate, localized state >= 30 s |
| `rapid` | Rapid breathing | Respiratory rate | `RR >= 20 breaths/min`, 60-s estimate, localized state >= 30 s |
| `irregular` | Irregular breathing | Inter-breath-interval variability | 60-s `CV_IBI >= 0.40` |
| `apnea` | Apnea-like respiratory pause | Very-low respiratory movement | <= 10% of reference excursion for >= 10 s |
| `sigh` | Sigh | Local breath excursion | Breath amplitude >= 2 x centered 15-breath median |
| `periodic` | Periodic breathing / Cheyne-Stokes-like pattern | eAMI by default | eAMI >= 0.60 with sustained periodic modulation |
| `thoracic` | Thoracic-dominant breathing | Relative thoracic/abdominal excursion | Normalized thoracic-to-abdominal ratio >= 1.5 for >= 30 s |
| `async` | Respiratory asynchrony | Thoracoabdominal phase offset | Reliable absolute phase offset >= 30 degrees for a sustained period |
| `desat` | Oxygen desaturation | SpO2 | SpO2 < 90% or >= 3 percentage-point drop from reference for >= 10 s |

Unless explicitly literature-derived, thresholds above are **operational MAGMA research criteria** rather than validated clinical diagnostic cutoffs.

### Shallow and deep breathing

Amplitude is measured relative to the belt-specific session reference. The thoracic and abdominal belts are evaluated independently because their absolute amplitudes are not directly comparable.

The selected canonical breath-amplitude definition is controlled by `config.resp.amp_method` and is shared by downstream amplitude-based analyses.

### Slow and rapid breathing

Respiratory rate is estimated over 60-s windows and then localized using the reviewed respiratory cycles.

These labels describe respiratory-rate states. By themselves they do not establish a clinical diagnosis such as hyperventilation syndrome.

### Irregular breathing

The primary measure is the coefficient of variation of inter-breath intervals:

`CV_IBI = SD(IBI) / mean(IBI)`

The current operational threshold is `CV_IBI >= 0.40` over the configured 60-s analysis window. Other nonlinear variability measures are not part of the current binary label.

### Apnea-like respiratory pauses

The label represents prolonged very-low respiratory movement.

Breath-amplitude evidence is preferred. Raw respiratory-belt excursion is used as a fallback when breath amplitudes cannot be evaluated. When both belts are evaluable, both must support the event.

Because airflow is not measured directly, this label should be interpreted as an **apnea-like respiratory pause**, not as confirmed obstructive or central sleep apnea.

### Sigh

The primary method uses a local rolling-median criterion:

`A_i >= 2 x median(A_(i-7), ..., A_(i+7))`

The same canonical breath amplitude selected by `config.resp.amp_method` is used by all sigh methods.

### Periodic breathing

The default primary detector is the estimated amplitude modulation index (eAMI). The Guyot demodulation/Matrix-Pencil implementation is retained as complementary evidence and can be selected as the primary method with `config.periodic.primary_method = 'guyot'`.

MAGMA currently uses an adapted eAMI threshold of `0.60` and a configured Guyot modulation-frequency band of `0.008-0.050 Hz`. These are MAGMA settings rather than exact published diagnostic thresholds.

The output represents **periodic or Cheyne-Stokes-like respiratory-effort modulation**, not a clinical diagnosis of Cheyne-Stokes respiration.

Periodic breathing is distinct from the Level-2 phenotype **periodic deep sighing**.

### Thoracic-dominant breathing

Thoracic and abdominal excursions are first normalized to their own session references. The operational label is based on:

`normalized thoracic excursion / normalized abdominal excursion >= 1.5`

This describes relative thoracic dominance within the recording, not the absolute thoracic contribution to tidal volume. The current threshold is an operational automatic-label rule rather than a validated clinical cutoff.

### Respiratory asynchrony

The primary method is thoracoabdominal phase offset. Thoracic and abdominal signals are evaluated at one shared respiratory frequency, with reviewed breath timing guiding the respiratory fundamental where available.

For local phase differences `delta_phi_j`, the circular summary is:

`Z = (1/N) * sum(exp(i * delta_phi_j))`

with:

- circular mean phase: `phi_bar = arg(Z)`
- phase consistency: `R = |Z|`

Primary evidence requires:

- `|phi_bar| >= 30 degrees`;
- `R >= 0.80`;
- at least 80% valid phase evidence;
- a summary over five respiratory cycles;
- sustained support for the configured minimum duration.

A stable 180-degree relationship therefore represents a large phase offset even when phase consistency is high. The older wavelet-coherence detector remains available as complementary evidence.

### Oxygen desaturation

A desaturation event is detected when either:

- `SpO2 < 90%`, or
- `SpO2_ref - SpO2 >= 3` percentage points,

for at least 10 s.

The absolute criterion does not require an available session reference. Event diagnostics also store nadir, event depth, criterion support, and recovery information.

## Level 2A and Level 2B — recording-level phenotype evidence

Level 2A combines Level-1 labels and detector summaries into full continuous
phenotype-evidence profiles. Level 2B selects a fixed 16-feature prespecified
DB representation plus five non-duplicated additional-pattern burdens. Both are
descriptive and do **not** create binary clinical phenotype-present/absent
diagnoses.

| Prespecified MAGMA DB phenotype evidence | Main Level-1 inputs | Assessable from current signals? | Main limitation / missing clinical information |
|---|---|---|---|
| Hyperventilation-like respiratory pattern | `rapid`, `deep`, rapid-deep overlap, RR, relative excursion | Partially | ETCO2/capnography, ventilation relative to metabolic demand, CPET/ergospirometry, clinical assessment, Nijmegen questionnaire are needed for clinical interpretation |
| Periodic deep sighing | `sigh`, `irregular`, `deep`, sigh-irregular overlap | Yes | Continuous pattern evidence; no clinical cutoff is imposed |
| Thoracic-dominant breathing | `thoracic` and thoracic/abdominal balance metrics | Yes | Belts are independently normalized and uncalibrated; clinical/ergospirometric validation is desirable |
| Forced abdominal expiration | none sufficient at present | No | Belt movement alone cannot establish active abdominal-muscle recruitment |
| Thoraco-abdominal asynchrony | `async` and phase-offset/coherence summaries | Yes | Algorithmic evidence is not a clinical diagnosis |

The current implementation is in `src/utils/build_db_phenotype_evidence.m`.

### Relationship between Level 1 and Level 2

Level 1 answers **"what respiratory/physiological pattern is present and when?"**

Level 2 answers **"how much evidence does this recording contain for a prespecified clinically motivated DB pattern?"** Level 2A retains the full answer; Level 2B provides the fixed raw 21-variable cohort representation.

Examples:

- `rapid` and `deep` are Level-1 states; their burden and overlap contribute to the Level-2 **hyperventilation-like** profile.
- individual `sigh` events and `irregular` breathing contribute to **periodic deep sighing**.
- `thoracic` directly contributes to **thoracic-dominant breathing** evidence.
- `async` directly contributes to **thoraco-abdominal asynchrony** evidence.
- no current Level-1 label is sufficient to establish **forced abdominal expiration**.

Automatic and manually reviewed annotation layers can generate parallel Level-2 evidence profiles. External clinical data are intentionally kept separate from the signal-derived phenotype evidence so they can be used for later clinical interpretation and validation.

See `PHENOTYPES.md` for the detailed phenotype-level interpretation and recommended clinical-validation structure.
