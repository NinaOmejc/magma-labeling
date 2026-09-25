# MAGMA dysfunctional-breathing phenotypes

MAGMA separates two analysis levels:

1. **Level 1 — time-resolved physiological labels and evidence.** Labels,
   events, assessability masks, breath evidence, and detector diagnostics.
2. **Level 2 — recording-level phenotype and respiratory-pattern evidence.**
   Detailed profiles and a fixed 21-value numeric summary are provided for
   automatic and reviewed annotation layers.

Level 2 contains two groups:

- **Literature-based prespecified dysfunctional-breathing phenotypes:**
  hyperventilation-like respiratory pattern, periodic deep sighing,
  thoracic-dominant breathing, forced abdominal expiration, and
  thoraco-abdominal asynchrony.
- **Additional MAGMA label-derived respiratory patterns:** apneic breathing,
  periodic breathing, shallow breathing, slow breathing, and desaturation.

A phenotype is **not one number**, no binary clinical diagnosis is produced,
and the ten recording-level profiles are not mutually exclusive. The detailed
Level-2 evidence contains more information than the fixed numeric summary.

## Five prespecified DB phenotypes

| Prespecified phenotype | Selected summary measures | Signal assessment status |
|---|---:|---|
| Hyperventilation-like respiratory pattern | 5 | `partial` |
| Periodic deep sighing | 5 | `assessable` when the required evidence is available |
| Thoracic-dominant breathing | 3 | `assessable` when both belts support the analysis |
| Forced abdominal expiration | 0 | `not_assessable` |
| Thoraco-abdominal asynchrony | 3 | `assessable` when both belts and phase evidence support the analysis |

`signal_assessment_status` describes what the signal modality can establish.
The separate `evidence_available` field states whether the required evidence
exists in the current recording. A `partial` status is not the same as
unavailable.

### Hyperventilation-like respiratory pattern

MAGMA intentionally does not use the term *hyperventilation syndrome*.
Respiratory belts can show rapid/deep breathing but cannot establish that
ventilation is excessive relative to metabolic demand.

The five compact features are:

1. rapid-breathing fraction of rapid-assessable time;
2. deep-breathing fraction of deep-assessable time;
3. rapid/deep overlap duration divided by time where both labels are jointly
   assessable;
4. the median of available per-belt recording-scope respiratory-rate medians;
5. the median of available per-belt recording-scope normalized breath-excursion
   medians.

Rate and excursion medians use the full relevant layer-specific assessable
scope, not only samples already labeled rapid or deep. The detailed Level-2 evidence
also retains directional overlap fractions, overlap event summaries,
event-conditioned medians, and belt-specific values.

### Periodic deep sighing

Periodic deep sighing describes the recurrence and organization of sighs. It
is distinct from the Level-1 `periodic` label, which describes waxing/waning
respiratory effort.

The five compact features are:

1. coverage-aware sigh frequency per 15 minutes;
2. maximum sigh count in a continuously assessable 15-minute interval;
3. irregular-breathing fraction of irregular-assessable time;
4. fraction of assessable canonical sigh events whose midpoint occurs in an
   irregular-positive state;
5. median of available per-belt recording-scope ordinary IBI CoV medians.

The 15-minute maximum is unavailable when no continuous assessable 15-minute
interval exists. For reviewed evidence, unreviewed gaps are never counted as
reviewed negatives. The event-level sigh/irregular feature is distinct from
the sample-duration overlap metric, which remains in the detailed Level-2 evidence.

### Thoracic-dominant breathing

Each uncalibrated respiratory belt is normalized to its own session reference.
The result describes relative thoracic-versus-abdominal change, not an absolute
rib-cage contribution to tidal volume.

The three compact features are thoracic-dominant fraction, the recording-scope
median normalized thoracic-to-abdominal excursion ratio, and median event
duration. If the detector is assessable and has zero events, the compact event
duration is 0 seconds. If the detector is unavailable, it remains `NaN`.

### Forced abdominal expiration

Forced abdominal expiration remains one of the five prespecified phenotypes,
but the current signals cannot establish active abdominal-muscle recruitment.
It contributes no compact feature. Thoracic dominance or belt excursion is not
used as a surrogate. Future assessment would require clinical annotation or
more direct muscular/mechanical evidence.

### Thoraco-abdominal asynchrony

The three compact features are asynchrony fraction, recording-scope median
absolute phase offset over reliable finite phase evidence, and median event
duration. As for thoracic dominance, an assessable detector with zero events
has a compact event duration of 0 seconds; unavailable evidence remains `NaN`.

The detailed Level-2 evidence retains event counts, maximum durations, phase consistency,
frequency-selection evidence, method comparison, reference quality, polarity
metadata, coherence diagnostics, skip codes, and other QC fields. These fields
are not part of the fixed numeric summary.

## Fixed recording-level numeric summary

`get_phenotype_feature_schema.m` is the sole authority for names, order, units,
roles, display names, and source descriptions. `build_compact_phenotype_features.m`
is the sole recording-level builder. The public `compact_features` structure
contains 21 selected numeric measures derived from the Level-2 phenotype and
respiratory-pattern evidence.

| # | Feature name | Units |
|---:|---|---|
| 1 | `db_hyperventilation_rapid_fraction` | fraction |
| 2 | `db_hyperventilation_deep_fraction` | fraction |
| 3 | `db_hyperventilation_rapid_deep_overlap_fraction` | fraction |
| 4 | `db_hyperventilation_median_rr_bpm` | breaths_per_min |
| 5 | `db_hyperventilation_median_relative_excursion` | ratio |
| 6 | `db_periodic_deep_sighing_sighs_per_15_min` | events_per_15_min |
| 7 | `db_periodic_deep_sighing_max_sighs_15_min` | events_per_15_min |
| 8 | `db_periodic_deep_sighing_irregular_fraction` | fraction |
| 9 | `db_periodic_deep_sighing_sigh_irregular_overlap_fraction` | fraction |
| 10 | `db_periodic_deep_sighing_median_ibi_cov` | dimensionless |
| 11 | `db_thoracic_dominant_fraction` | fraction |
| 12 | `db_thoracic_dominant_median_ta_ratio` | ratio |
| 13 | `db_thoracic_dominant_median_event_duration_sec` | seconds |
| 14 | `db_asynchrony_fraction` | fraction |
| 15 | `db_asynchrony_median_abs_phase_deg` | degrees |
| 16 | `db_asynchrony_median_event_duration_sec` | seconds |
| 17 | `pattern_apnea_fraction` | fraction |
| 18 | `pattern_periodic_fraction` | fraction |
| 19 | `pattern_shallow_fraction` | fraction |
| 20 | `pattern_slow_fraction` | fraction |
| 21 | `pattern_desaturation_fraction` | fraction |

The first 16 variables represent the prespecified DB phenotypes. The final five
are non-duplicated additional respiratory-pattern burdens. Forced abdominal
expiration contributes zero variables.

Deep breathing, rapid breathing, irregular breathing, and sighing remain fully
available at Level 1 and contribute to the prespecified phenotypes; they are not
duplicated as additional Level-2 respiratory-pattern profiles. The only
additional Level-2 profiles are apneic breathing, periodic breathing, shallow
breathing, slow breathing, and desaturation.

## Availability, zero, and coverage

All fractions use assessable time as their denominator. For each compact
feature MAGMA stores the value, an availability flag, coverage fraction, and a
missing reason.

```text
unavailable != negative
```

A finite zero is a valid available negative. Missing or unusable signal
evidence remains `NaN` with `available=false`; it is never silently converted
to zero. The compact summaries are raw and unscaled. MAGMA performs no
cross-subject normalization, imputation, or transformation of these outputs.

## Automatic and reviewed summaries

The automatic and reviewed layers are always separate:

- **automatic** uses the full physiologically assessable recording;
- **reviewed** uses only explicitly reviewed *and* physiologically assessable
  regions.

Recording-scope rate, excursion, CoV, balance, and phase medians obey the same
layer scope. A reviewed median therefore never incorporates an unreviewed
region, and automatic/reviewed values are never silently mixed in one row.

## Detailed Level-2 evidence and Level-1 crosswalk

The full archive preserves useful burden, event, overlap, belt-specific,
method-comparison, availability, QC, and provenance evidence. It also preserves
event-conditioned continuous summaries alongside the recording-scope summaries
selected for the fixed numeric summary.

| Level-1 evidence | Level-2 use |
|---|---|
| `rapid`, `deep`, rapid/deep overlap | Hyperventilation-like pattern |
| `sigh`, `irregular`, sigh/irregular overlap | Periodic deep sighing |
| `thoracic` and normalized belt balance | Thoracic-dominant breathing |
| `async` and reliable phase evidence | Thoraco-abdominal asynchrony |
| `apnea`, `periodic`, `shallow`, `slow`, `desat` | Additional compact burdens |

## External clinical data

Nijmegen Questionnaire, ETCO2/capnography, CPET/ergospirometry, clinical
observations, and other clinical variables remain external to the signal-derived
21-value summary. They may be combined with MAGMA outputs in other repositories
for interpretation, validation, or association analysis, but are not used to
create MAGMA Level-2 evidence.
