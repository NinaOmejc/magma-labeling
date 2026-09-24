# MAGMA dysfunctional-breathing phenotype evidence

MAGMA uses a three-level representation:

1. **Level 1 — elementary physiological labels/evidence:** time-resolved signal-derived respiratory and physiological patterns.
2. **Level 2 — continuous prespecified MAGMA DB phenotype evidence:** recording-level profiles derived from Level-1 evidence and motivated by dysfunctional-breathing patterns described in the clinical literature.
3. **Level 3 — future data-driven phenotype discovery:** unsupervised discovery of respiratory profiles from the multivariate representation.

The key distinction is that **Level 1 and Level 2 are signal-derived descriptions, not clinical diagnoses**. Level 2 summarizes how strongly a recording expresses a prespecified DB-like pattern; it does not assign a binary clinical phenotype.

## Level 1 — elementary physiological labels/evidence

The current canonical Level-1 labels are:

| Domain | Level-1 labels | Interpretation |
|---|---|---|
| Breathing depth | `shallow`, `deep` | Relative belt excursion compared with the session reference |
| Breathing rate | `slow`, `rapid` | Sustained low or high respiratory-rate states |
| Rhythm regularity | `irregular` | Increased inter-breath-interval variability |
| Discrete respiratory events | `apnea`, `sigh` | Very-low respiratory movement or isolated unusually large breath |
| Patterned breathing | `periodic` | Periodic / Cheyne-Stokes-like modulation of respiratory effort |
| Breathing mechanics | `thoracic`, `async` | Thoracic dominance or thoracoabdominal phase mismatch |
| Physiological consequence | `desat` | Oxygen desaturation measured by SpO2 |

Labels are independent and may overlap in time. A recording can therefore simultaneously show, for example, rapid breathing, irregular breathing, thoracic dominance, and desaturation.

Level 1 is designed to answer:

> **What elementary respiratory or physiological patterns occur in the signal, and when?**

Detailed detector definitions are provided in `LABELS.md`.

## Level 2 — continuous prespecified MAGMA DB phenotype evidence

The current implementation defines five prespecified clinically motivated DB phenotype profiles in `src/utils/build_db_phenotype_evidence.m`.

| Level-2 phenotype evidence | Main evidence assembled by MAGMA | Current status | Clinical interpretation |
|---|---|---|---|
| **Hyperventilation-like respiratory pattern** | Rapid-breathing fraction, deep-breathing fraction, rapid-deep overlap duration/fractions/event counts, respiratory rate, relative deep excursion | **Partially assessable** | Respiratory pattern evidence only; rapid + deep breathing does not establish hyperventilation syndrome |
| **Periodic deep sighing** | Sigh count, sighs per 15 min, maximum sighs in any 15-min window, irregular-breathing fraction, deep-breathing fraction, sigh-irregular overlap, inter-sigh intervals | **Assessable** | Signal-derived evidence for a recurrent sighing/irregular pattern; no binary clinical cutoff is imposed |
| **Thoracic-dominant breathing** | Thoracic-dominance burden, event durations/counts, thoracic-to-abdominal ratio, log ratio, relative thoracic fraction | **Assessable** | Relative thoracic dominance from independently normalized belts; not an absolute rib-cage contribution measurement |
| **Forced abdominal expiration** | No adequate current signal-derived measure | **Not assessable** | Active abdominal-muscle recruitment cannot be established from the current belt signals alone |
| **Thoraco-abdominal asynchrony** | Asynchrony burden, phase-offset metrics, phase consistency/QC, selected respiratory frequency, complementary coherence summaries | **Assessable** | Algorithmic evidence of thoracoabdominal phase mismatch; not a clinical diagnosis |

### Hyperventilation-like respiratory pattern

MAGMA intentionally uses the name **hyperventilation-like respiratory pattern**, rather than hyperventilation syndrome.

Current signal-derived evidence includes:

- rapid-breathing fraction;
- deep-breathing fraction;
- duration and fraction of rapid-deep overlap;
- rapid-deep overlap event count and duration;
- median respiratory rate;
- median relative deep-breath excursion.

Clinical interpretation would benefit from external information such as:

- ETCO2/capnography;
- ventilation relative to metabolic demand;
- cardiopulmonary exercise testing / ergospirometry;
- clinical assessment;
- Nijmegen Questionnaire.

Therefore, **rapid plus deep breathing is evidence compatible with a hyperventilation-like pattern, but it does not establish hyperventilation syndrome**.

### Periodic deep sighing

The profile combines sighing and irregularity rather than equating a single sigh with the phenotype.

Current evidence includes:

- sigh count;
- sighs per 15 minutes;
- maximum number of sighs in any 15-minute window;
- irregular-breathing fraction;
- deep-breathing fraction;
- fraction of sighs overlapping irregular breathing;
- median and minimum inter-sigh interval.

This phenotype is deliberately distinct from the Level-1 `periodic` label. **Periodic deep sighing** refers to recurrent sighing in an irregular breathing pattern, whereas **periodic breathing** refers to cyclic modulation of respiratory effort.

### Thoracic-dominant breathing

The phenotype profile summarizes the Level-1 thoracic-dominance evidence over the recording.

Current evidence includes:

- thoracic-dominance fraction;
- number and duration of thoracic-dominant episodes;
- median normalized thoracic-to-abdominal excursion ratio;
- median log-ratio;
- median thoracic relative fraction.

Because the belts are uncalibrated and independently normalized to their session references, this profile should be interpreted as **relative thoracic dominance within a recording**, not as a calibrated measurement of the absolute rib-cage contribution to tidal volume.

### Forced abdominal expiration

This phenotype is currently retained in the prespecified clinical framework but is marked as **not assessable from the current signals**.

The respiratory belts measure movement. They do not directly establish active contraction or recruitment of the abdominal expiratory muscles. MAGMA therefore does not use thoracic dominance, abdominal excursion, or another indirect measure as a proxy for forced abdominal expiration.

Potential future evidence would require clinical annotation or a more direct mechanical/muscle measurement.

### Thoraco-abdominal asynchrony

This profile summarizes Level-1 respiratory-asynchrony evidence.

Current evidence includes:

- asynchrony fraction and episode summaries;
- median and maximum absolute thoracoabdominal phase offset;
- circular phase consistency;
- selected and expected respiratory frequencies;
- frequency-selection QC;
- complementary legacy wavelet-coherence summaries.

The primary evidence is based on thoracoabdominal phase offset. The output is **algorithmic asynchrony evidence**, not a clinical diagnosis of paradoxical breathing or another specific disorder.

## Level-1 to Level-2 crosswalk

| Level-1 evidence | Level-2 phenotype(s) it directly informs |
|---|---|
| `rapid` | Hyperventilation-like pattern |
| `deep` | Hyperventilation-like pattern; periodic deep sighing |
| rapid-deep overlap | Hyperventilation-like pattern |
| `sigh` | Periodic deep sighing |
| `irregular` | Periodic deep sighing |
| sigh-irregular overlap | Periodic deep sighing |
| `thoracic` | Thoracic-dominant breathing |
| `async` | Thoraco-abdominal asynchrony |
| `shallow` | Retained as a descriptive respiratory-pattern profile; not currently mapped to one of the five prespecified DB phenotypes |
| `slow` | Retained as a descriptive respiratory-pattern profile; not currently mapped to one of the five prespecified DB phenotypes |
| `apnea` | Retained as an apneic-breathing profile; not equivalent to sleep-apnea diagnosis |
| `periodic` | Retained as a periodic-breathing profile; distinct from periodic deep sighing |
| `desat` | Retained as physiological consequence/evidence; not itself a DB phenotype |

## Additional respiratory-pattern profiles

In addition to the five prespecified DB phenotype profiles, MAGMA stores continuous descriptive summaries for:

- apneic breathing;
- periodic breathing;
- shallow breathing;
- deep breathing;
- slow breathing;
- rapid breathing;
- irregular breathing;
- sighing;
- desaturation.

These are useful for clustering and clinical interpretation but should not be conflated with the five prespecified DB phenotype profiles.

## Automatic and reviewed evidence

MAGMA can build parallel phenotype-evidence bundles from:

- **automatic labels**, covering the full assessable recording; and
- **reviewed labels**, covering explicitly reviewed and assessable regions.

The same conceptual Level-2 profiles are produced for both annotation layers. This preserves provenance and allows the effect of manual review to be assessed without redefining the phenotype representation.

External clinical data are intentionally not merged into the signal-derived phenotype evidence at this stage.

## Clinical validation

A useful validation strategy is to keep clinician assessment **independent** of the MAGMA phenotype profiles.

Clinicians can assess the five prespecified DB patterns per recording or participant using a small multi-label form such as:

| Clinical DB pattern | Absent | Possible | Present | Not assessable |
|---|:---:|:---:|:---:|:---:|
| Hyperventilation / hyperventilation syndrome |  |  |  |  |
| Periodic deep sighing |  |  |  |  |
| Thoracic-dominant breathing |  |  |  |  |
| Forced abdominal expiration |  |  |  |  |
| Thoraco-abdominal asynchrony |  |  |  |  |

Multiple patterns should be allowed for the same person or recording.

The comparison is then conceptually clean:

`independent clinician assessment <-> Level-2 MAGMA phenotype evidence`

A separate expert review of raw time-series windows can be used to validate Level-1 event/state detectors. Keeping these two validation tasks separate avoids using algorithm-generated labels to define the clinical phenotype that is later used to validate the algorithm.

## Relationship to Level 3 — data-driven phenotype discovery

Level 3 is conceptually different from the five prespecified Level-2 profiles.

The planned clustering analyses use multivariate respiratory evidence to discover **data-driven respiratory profiles**. These clusters should initially be treated as empirical profiles rather than assumed clinical diagnoses.

Their clinical relevance can then be evaluated using independent information such as:

- clinician-assigned DB patterns;
- Nijmegen Questionnaire score;
- dyspnoea severity;
- obstructive airway disease;
- sleep-related breathing disorder;
- cardiovascular disease and other comorbidities;
- rehabilitation-related change between measurement sessions.

This gives a clear hierarchy:

`Level 1 elementary labels -> Level 2 prespecified DB evidence -> Level 3 data-driven phenotype discovery -> external clinical validation and interpretation`
