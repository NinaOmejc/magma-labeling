# MAGMA dysfunctional-breathing phenotypes

## Continuous prespecified MAGMA DB phenotype evidence

The current implementation defines five prespecified clinically motivated DB phenotype profiles in `src/utils/build_db_phenotype_evidence.m`.

| Prespecified DB phenotype | Core features for the primary analysis representation | Number of core features | Additional stored/supporting evidence |
|---|---|---:|---|
| **Hyperventilation-like respiratory pattern** | Rapid-breathing fraction; deep-breathing fraction; rapid-deep overlap fraction; median respiratory rate during rapid breathing; median relative excursion during deep breathing | **5** | Rapid-deep overlap duration, event count and event duration; belt-specific summaries; external ETCO2/capnography, CPET/ergospirometry, Nijmegen Questionnaire and clinical assessment |
| **Periodic deep sighing** | Sighs per 15 min; maximum sigh count in any 15-min window; irregular-breathing fraction; fraction of sighs overlapping irregular breathing; median inter-sigh interval | **5** | Raw sigh count; minimum inter-sigh interval; deep-breathing fraction; detailed sigh-amplitude descriptors |
| **Thoracic-dominant breathing** | Thoracic-dominance fraction; median normalized thoracic-to-abdominal excursion ratio; median thoracic-dominant episode duration | **3** | Event count; maximum duration; median log-ratio; median relative thoracic fraction |
| **Forced abdominal expiration** | No adequate current signal-derived feature | **0** | Future candidates require clinical annotation or more direct abdominal-muscle/mechanical evidence |
| **Thoraco-abdominal asynchrony** | Asynchrony fraction; median absolute thoracoabdominal phase offset; median asynchrony episode duration | **3** | Maximum phase offset; event count; resultant length; frequency-selection metrics; coherence comparison; QC and availability fields |

The compact representation therefore contains:

- 5 hyperventilation-like features;
- 5 periodic-deep-sighing features;
- 3 thoracic-dominance features;
- 0 forced-abdominal-expiration features;
- 3 thoracoabdominal-asynchrony features.

**Total: 16 primary Level-2 DB phenotype features per recording**, subject to physiological availability.

These 16 features are the proposed primary representation for phenotype-space clustering. The larger evidence objects remain available for quality control, interpretation, sensitivity analyses, and secondary modelling.
---

## Hyperventilation-like respiratory pattern

MAGMA intentionally uses the term **hyperventilation-like respiratory pattern**, rather than hyperventilation syndrome.

Hyperventilation is physiologically defined by ventilation being excessive relative to metabolic demand and is therefore not established by respiratory belts alone. Rapid and deep breathing provide compatible respiratory-pattern evidence but do not by themselves demonstrate hyperventilation syndrome.

### Core analysis features

1. **Rapid-breathing fraction**  
   Fraction of assessable recording time classified as rapid breathing.

2. **Deep-breathing fraction**  
   Fraction of assessable recording time classified as deep breathing.

3. **Rapid-deep overlap fraction**  
   Degree to which rapid and deep breathing occur simultaneously.

4. **Median respiratory rate during rapid breathing**  
   Summary of rate severity when rapid breathing is present.

5. **Median relative excursion during deep breathing**  
   Summary of breathing-depth increase relative to the recording-specific reference.

### Additional evidence retained by MAGMA

The full phenotype evidence object additionally stores:

- rapid-deep overlap duration;
- rapid-deep overlap fractions relative to each component;
- rapid-deep overlap event count;
- median and maximum rapid-deep event duration;
- belt-specific respiratory-rate summaries;
- belt-specific relative deep-excursion summaries.

### External clinical information

Clinical interpretation may additionally use:

- ETCO2 / capnography;
- ventilation relative to metabolic demand;
- cardiopulmonary exercise testing / ergospirometry;
- clinical assessment;
- Nijmegen Questionnaire.

These external clinical variables are not currently combined into the signal-derived phenotype score and should remain distinguishable from the physiological evidence.

---

## Periodic deep sighing

Periodic deep sighing is represented as a recurrent sighing pattern rather than by the occurrence of an isolated sigh.

It is deliberately distinct from the Level-1 `periodic` label:

- **periodic deep sighing** describes repeated sighs and their temporal organization within irregular breathing;
- **periodic breathing** describes cyclic waxing-waning modulation of respiratory effort.

### Core analysis features

1. **Sighs per 15 minutes**  
   Recording-normalized sigh frequency.

2. **Maximum sigh count in any 15-minute window**  
   Captures local clustering of sighs even when whole-recording frequency is moderate.

3. **Irregular-breathing fraction**  
   Fraction of assessable recording time showing respiratory timing irregularity.

4. **Fraction of sighs overlapping irregular breathing**  
   Measures the degree to which sighs occur within irregular respiratory periods.

5. **Median inter-sigh interval**  
   Describes the typical temporal spacing of recurrent sighs.

### Additional evidence retained by MAGMA

The complete phenotype profile may additionally contain:

- total sigh count;
- minimum inter-sigh interval;
- deep-breathing fraction;
- detailed sigh-amplitude summaries.

Deep-breathing fraction is retained in the full evidence object because sighs are augmented breaths and sustained deep breathing may provide additional context. It is not included in the compact primary representation to avoid unnecessary overlap with the hyperventilation-like phenotype.

---

## Thoracic-dominant breathing

Thoracic-dominant breathing is derived from relative thoracic and abdominal excursion.

Because the two respiratory belts are uncalibrated, each is normalized independently to its own recording-specific reference. The resulting measures therefore describe **relative change in thoracic versus abdominal motion**, not absolute rib-cage contribution to tidal volume.

### Core analysis features

1. **Thoracic-dominance fraction**  
   Fraction of assessable recording time classified as thoracic dominant.

2. **Median normalized thoracic-to-abdominal excursion ratio**  
   Typical magnitude of relative thoracic dominance.

3. **Median thoracic-dominant episode duration**  
   Persistence of the thoracic-dominant pattern.

### Additional evidence retained by MAGMA

The full evidence profile additionally stores:

- event count;
- maximum event duration;
- median log thoracic-to-abdominal ratio;
- median relative thoracic fraction.

The ratio, log-ratio, and relative-fraction measures are alternative descriptions of largely the same thoracoabdominal balance. They are retained for interpretation and methodological comparison but are not all included in the compact analysis representation.

---

## Forced abdominal expiration

Forced abdominal expiration is retained as one of the five prespecified clinically motivated DB phenotypes but is currently marked as **not assessable from the available signals**.

The respiratory belts measure thoracic and abdominal movement but do not directly establish active abdominal-muscle contraction or expiratory recruitment.

MAGMA therefore does not use thoracic dominance, abdominal excursion, or another indirect belt-derived measure as a surrogate for forced abdominal expiration.

Potential future evidence could include:

- clinical annotation;
- direct abdominal muscle activity;
- calibrated respiratory mechanics;
- expiratory abdominal excursion;
- expiratory slope;
- expiratory duration;
- abdominal-to-thoracic expiratory ratio;
- persistence or event burden.

These remain future candidates and are not part of the current Level-2 feature vector.

---

## Thoraco-abdominal asynchrony

Thoraco-abdominal asynchrony is derived from the phase relationship between the thoracic and abdominal respiratory belts.

The primary detector estimates the respiratory phase difference at a shared respiratory frequency and summarizes the local phase relationship using circular statistics.

### Core analysis features

1. **Asynchrony fraction**  
   Fraction of assessable recording time classified as asynchronous.

2. **Median absolute thoracoabdominal phase offset**  
   Typical magnitude of temporal displacement between thoracic and abdominal motion.

3. **Median asynchrony episode duration**  
   Persistence of asynchronous breathing when present.


### Additional evidence retained by MAGMA

The full evidence structure stores substantially more information, including:

- event count;
- maximum event duration;
- maximum absolute phase offset;
- resultant length / phase consistency;
- selected respiratory frequency;
- expected respiratory frequency;
- selected-to-expected frequency ratio;
- reference availability and quality;
- phase-offset quality-control information;
- complementary wavelet-coherence evidence;
- method-comparison information;
- polarity metadata;
- skip codes and availability information.

These additional fields are useful for quality control and methodological interpretation but should **not** be treated as equally weighted phenotype features.

The HDF5 export may therefore contain many nested asynchrony datasets even though the compact phenotype representation contains only three primary asynchrony features.



---

## Labels and phenotypes crosswalk

| Level-1 evidence | Level-2 phenotype(s) it directly informs |
|---|---|
| `rapid` | Hyperventilation-like respiratory pattern |
| `deep` | Hyperventilation-like respiratory pattern; retained as supporting context for periodic deep sighing |
| rapid-deep overlap | Hyperventilation-like respiratory pattern |
| `sigh` | Periodic deep sighing |
| `irregular` | Periodic deep sighing |
| sigh-irregular overlap | Periodic deep sighing |
| `thoracic` | Thoracic-dominant breathing |
| `async` | Thoraco-abdominal asynchrony |
| `shallow` | Additional descriptive respiratory-pattern profile |
| `slow` | Additional descriptive respiratory-pattern profile |
| `apnea` | Additional apneic-breathing profile; not equivalent to a sleep-apnea diagnosis |
| `periodic` | Additional periodic-breathing profile; distinct from periodic deep sighing |
| `desat` | Additional oxygenation profile; not itself a DB phenotype |

---

## Additional respiratory-pattern profiles

In addition to the five prespecified DB phenotype profiles, MAGMA retains recording-level summaries for physiological patterns that are **not currently incorporated into the primary compact representation of the five prespecified DB phenotypes**:

- apneic breathing;
- periodic breathing;
- shallow breathing;
- slow breathing;
- desaturation.

Rapid breathing, deep breathing, irregular breathing, sighing, thoracic dominance, and respiratory asynchrony remain available as Level-1 physiological evidence but are already incorporated into the prespecified Level-2 phenotype framework and are therefore not duplicated here as separate additional phenotype profiles.

These additional patterns are descriptive physiological characteristics, not additional prespecified DB phenotypes.

### Compact additional-pattern features

For the primary phenotype-space analysis, one principal burden feature can be retained for each additional pattern:

| Additional respiratory pattern | Primary compact feature | Optional severity descriptor |
|---|---|---|
| **Apneic breathing** | Apnea fraction | Median event duration or suppression severity |
| **Periodic breathing** | Periodic-breathing fraction | eAMI / modulation strength |
| **Shallow breathing** | Shallow-breathing fraction | Median relative excursion |
| **Slow breathing** | Slow-breathing fraction | Median respiratory rate |
| **Desaturation** | Desaturation fraction | Minimum SpO2 or maximum SpO2 decrease |

If all five primary burden measures are used together with the 16 compact prespecified-phenotype features, the resulting primary recording-level phenotype-space representation contains approximately **21 variables**.

This 21-variable representation is a proposed analysis representation rather than a replacement for the full stored evidence.

---

## How a phenotype profile is created

A Level-2 MAGMA phenotype is **not one final number** and is not currently converted into a binary phenotype-present / phenotype-absent assignment.

Instead, Level 2 aggregates the time-resolved Level-1 evidence across a recording into a small set of continuous summary measures.

Examples include:

- fraction of assessable recording time occupied by a pattern;
- number of detected episodes;
- median and maximum episode duration;
- temporal overlap between relevant Level-1 labels;
- event frequency;
- inter-event timing;
- median respiratory rate;
- relative respiratory excursion;
- thoracoabdominal phase offset;
- physiological severity measures.

The general transformation is therefore:

`time-resolved Level-1 evidence -> recording-level summary measures -> multivariate Level-2 phenotype profile`

and not:

`time-resolved Level-1 evidence -> one phenotype score`

No weighted combination of the Level-2 measures into one scalar phenotype score is currently defined.

---

## Recording-level aggregation

The Level-2 phenotype profiles summarize an **entire recording**.

Level-1 labels remain time resolved, while Level-2 variables describe the burden, intensity, co-occurrence, and temporal organization of those labels over the assessable recording.

For example:

- rapid-breathing fraction represents the proportion of assessable recording time classified as rapid;
- sighs per 15 min summarizes discrete sigh occurrence over the recording;
- thoracic-dominance fraction summarizes the burden of thoracic-dominant breathing;
- median phase offset summarizes the typical magnitude of thoracoabdominal displacement during assessable asynchrony evidence.

Unavailable physiological evidence is distinguished from a negative phenotype result. Missing or unusable signals should therefore produce unavailable / `NaN` evidence where appropriate rather than being interpreted as phenotype absence.

### Automatic and reviewed representations

MAGMA stores phenotype evidence separately for the automatic and reviewed annotation layers.

For the automatic layer:

- annotation scope: `full_assessable_recording`;
- phenotype summaries use all recording regions for which the relevant physiological evidence is assessable.

For the reviewed layer:

- annotation scope: `explicitly_reviewed_and_assessable_regions`;
- summaries are based on the reviewed annotation layer and should not imply that unreviewed regions were clinically confirmed negative.

The automatic and reviewed profiles should remain distinguishable throughout validation and downstream modelling.

---

## Full evidence archive versus compact analysis representation

Two Level-2 representations should be distinguished.

### Level 2A: full phenotype evidence archive

The complete HDF5/MAT output retains:

- all available recording-level summaries;
- event counts and durations;
- alternative evidence measures;
- detector-specific summaries;
- quality-control information;
- availability flags;
- method comparisons;
- provenance.

This representation is intended for reproducibility, quality control, detailed interpretation, sensitivity analyses, and secondary modelling.

### Level 2B: compact phenotype representation

The compact analysis representation contains:

- **16 core features** representing the four currently signal-assessable prespecified DB phenotypes;
- optionally **5 additional respiratory-pattern burden features**.

The resulting approximately **21-variable recording-level vector** is the preferred starting point for unsupervised phenotype-space analyses.

Before clustering, numerical features should be appropriately transformed and scaled, and redundancy should be checked empirically. Feature reduction should preserve the conceptual balance between phenotypes rather than being driven only by the number of detector outputs available for each phenotype.

---