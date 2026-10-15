# Rebuilding the longitudinal MAGMA metadata database

This independent MATLAB importer integrates source workbooks. It does not calculate
label burdens, phenotypes, paired summaries, changes, descriptive statistics or
other scientific results. Original inputs and recording-level HDF5 files stay
unchanged. Keep source workbooks and generated clinical datasets outside Git.

## Configure and run

From the repository root, configure the current files explicitly:

```matlab
addpath(genpath('src'));
config = get_master_database_config( ...
    'D:\Projects\MAGMA\data_analysis\statistical_labeling\group_analysis\group_summary.xlsx', ...
    'D:\Projects\MAGMA\ML_database_WORK_IN_PROGRESS_20Sep26_MG.xlsx', ...
    'D:\Projects\MAGMA\data_analysis\statistical_labeling\master_database', ...
    'D:\Projects\MAGMA\STRESS TEST _WORK IN PROGRESS_20Sep26.xlsx');
database = build_master_database(config);
```

Change these input arguments for new workbook versions; regenerate rather than
editing the master workbook. Source counts and additional columns are discovered
on each run. No September/October row counts are required. `Descriptive`,
`Paired_summary`, and unrelated group sheets are never imported.

For the current project layout, `run('src/main_master_database.m')` performs this
rebuild. Update its input paths when filenames change. The fourth configuration
argument selects the stress-test workbook; omitting it retains the original
five-table import for older callers. A configured missing file fails explicitly.

The output folder contains `MAGMA_master_database.xlsx`, one CSV per main table,
an optional native-table `MAGMA_master_database.mat`, and CSV/text audit reports.
The MAT includes source cells, source schemas and import provenance as well as
native tables; it also contains confidential data. `config.export_mat = false`
disables that export. CSV blanks/NaN, and literal source `N/A` / `not reported`
tokens are unavailable values, never numeric zero. Heterogeneous columns retain
their numeric/text/date cells; homogeneous columns use native numeric, datetime
or string types. Use `Import_mapping.matlab_type` and the source dictionaries
when loading mixed columns programmatically.

The default compact native MAT format is `-v7`; set `config.mat_version='-v7.3'`
if future snapshots require the larger-format capacity. This does not alter
recording-level HDF5 files or their schemas.

## Main tables and keys

| Table | Primary key | Meaning |
| --- | --- | --- |
| Subjects | `participant_id` | One canonical participant; baseline ID, verified group, date of birth, sex and selection provenance. |
| Questionnaire | `questionnaire_record_id` | One actual source row, identified by source ID, sheet and Excel row; no M1/M2 expansion. |
| Physiology | `recording_id` | Original within-visit recording; both measurement sheets are combined. |
| Label_burden | `recording_id`, `label` | Original supplied scientific burden/count/availability/review columns. |
| Phenotypes | `recording_id`, `annotation_layer` | Original automatic/reviewed variables and `analysis_id`. |
| StressTest | `stress_test_record_id` | One actual source stress-test row; original test number, date, workload, cardiovascular measurements and clinical notes. |

All non-Subjects tables have `participant_id` as a foreign key to Subjects.
`source_subject_id` links many rows to the unique `Identity_map` row for that
source visit. `visit_id` is `Visit_Sub<original ID>` and remains available even
when visit chronology is unresolved. Participant IDs are the original root
subject codes (`Sub87`, for example), following explicit repeat-ID links.
The collaborator spelling `Sub_87` is normalized for keys only; its original
Subject column remains intact. No identity is inferred from a previous output.

All main tables include numeric `participant_number` immediately after
`participant_id`. It is the number in the canonical participant ID, so repeat
source IDs linked to Sub130 all have `participant_number=130`. Each build sorts
by this number, then by `visit_number` and within-visit `measure` where present.
Unavailable numeric keys sort last. IDs and all original values stay unchanged;
this column controls presentation order, not identity or visit chronology.

## Stress-test observations and refresh

The optional stress source reads `Stress_tests`, with headers in row 1 and
`Sub_code` as its source subject key. All populated rows and all 36 currently
supplied columns are preserved, including rows describing an unrecorded test,
literal `not recorded` tokens, zeros, multiline Polish notes and source units.
Added subjects, tests and columns are read on every rebuild without a fixed range.
`StressTest.csv` and `database.tables.StressTest` in the MAT export use the same
rows as the new workbook tab.

`stress_test_record_id` follows the questionnaire source-row convention:
`<source_id>:<sheet>:<Excel row>`. It identifies a row in the configured snapshot;
inserting/reordering source rows changes these row-based IDs. Source filename,
sheet and Excel row are recorded alongside each observation, and the source hash
is included in `Input_manifest`. Identical source rows are retained and audited,
never silently discarded or merged. Rows link through `source_subject_id` to the
same canonical participant and source visit as other tables. New source-only IDs
also enter Subjects and Identity_map; missing questionnaire/physiology coverage
remains explicit.

`Test no.` is kept as the original `test_no` field, separate from respiratory
`measure` and longitudinal M1/M2 numbering. Stress tests are not expanded into
M1/M2 rows, and their dates do not determine visit chronology. No event date or
clinical interpretation is inferred. `StressTest_single_measurement` and
`StressTest_inconsistencies` preserve the source workbook's two reference lists;
reported inconsistencies do not cause measurements to be corrected or removed.

Save the updated source, then rerun `src/main_master_database.m`. The build
replaces generated sheets/CSVs/MAT from the current inputs, reuses the confirmed
visit and dropout override files, and removes stale rows from regenerated tables.

For recording tables, `measure` is the original within-visit number 1 or 2. For resolved visits:

```text
longitudinal_measure_number = 2*(visit_number - 1) + measure
longitudinal_measure = M<longitudinal_measure_number>
```

Thus Sub87_M1/M2 can be visit 1, longitudinal M1/M2, and Sub117_M1/M2 visit 2,
longitudinal M3/M4, under participant Sub87. Recording IDs are never renamed.
Use `recording_id` to join to existing per-recording HDF5 files; `/meta/subject`
and `/meta/measurement` continue to mean the original subject and measure.
There is no new HDF5 exporter.

## Questionnaire scope and verified characteristics

Subjects includes `Questionnaire`, `Physiology`, `Label_burden`, `Phenotypes`
and `StressTest` immediately after `grp`, in that order. Questionnaire is numeric
0/1 for any observed response. The three recording counts are text `n/4`, and
StressTest is `n/2`; these nominal denominators never cap additional visits.
`add_master_subject_availability` uses canonical participant IDs and distinct
recording IDs, excluding administrative fields and missing-value tokens. Numeric
zero and logical false remain valid observations. Label and feature availability
flags are respected; reviewed label fractions require positive review coverage.
Stress-test documentation fields (including `clininet_pl_txt`, which contains
zero placeholders for absent tests) do not establish measurement availability.
Stress tests use participant, test number and test date (or source visit when
the date is unavailable), deduplicating repeated source rows. Established test
record IDs provide a fallback when test numbers are absent. If StressTest is not
imported, its `0/2` column is accompanied by a diagnostic warning and does not
confirm absence. Original source tables, identities and groups remain intact.

Questionnaire original variables are retained once for each source row. Group
uses the dictionary definition `grp=1` Patient / `grp=0` Control. Repeated IDs
inherit verified participant group through Subjects; original questionnaire
and group-summary classifications remain in the source columns/provenance.
Contradictory nonmissing group values are audited and the Subjects group stays
Unknown rather than silently choosing one.

Only the explicitly configured `participant_fields` (initially `dob` and `sex`)
are selected as stable characteristics, and conflicts remain unselected.
Do not add age, weight, BMI, medication use, height or study date to that list.
Those source responses remain attached to their actual Questionnaire row/visit.
Join stable metadata from Subjects rather than filling later questionnaires.

Mapped follow-up rows whose general questionnaire block contains no substantive
response are tagged `followup_observations_only`, with
`baseline_information_scope=participant_baseline_not_repeated`. This preserves
their genuine study dates/stress-test/administrative data without asserting that
baseline information is missing. Their original N/A/blank/unknown tokens remain
intact. Future rows with collected general responses are retained as actual
follow-up content. A missing follow-up questionnaire creates an informational
audit entry, never an artificial row. Schemas without the explicitly configured
baseline-block boundaries are not assumed to be structurally uncollected.
Their follow-up scope is explicitly tagged `followup_scope_unverified`.

## Confirm visit chronology

The repeat mapping provides original-to-repeat identity and ordering constraints.
For a single repeat, the first/repeated columns establish visits 1/2. For multiple
repeats, confirmed complete study dates and explicit repeat chains establish
only unambiguous order. Numeric subject-ID order never establishes chronology.
Stress-test dates and diagnosis dates are not substituted for study dates.
Conflicting study dates are reported and not selected.

If dates/links cannot order visits, `visit_number` and longitudinal numbering
remain missing. `Identity_map` and `visit_order_overrides_needed.csv` list the
unresolved IDs. The first build creates a human-editable
`visit_order_overrides.csv` if none exists. Existing override files are never
rewritten. Edit confirmed assignments, for example:

```csv
source_subject_id,participant_id,visit_number,confirmed,notes
Sub140,Sub130,,false,Await confirmed visit order
```

Enter the verified positive integer and set `confirmed=true`; blanks and
unconfirmed rows do not supply order. Use the same override file on later builds
(`config.visit_order_overrides_file`). Participant identity comes exclusively
from the source mapping; the CSV participant column is contextual. A conflicting
number, duplicate number within a participant, cycle, or contradiction with
confirmed dates is a validation error. Sparse explicit numbers may be retained,
but unassigned intervening visits are not guessed.

## Confirmed study dropouts and current administrative status

`config.study_status_overrides_file` defaults to `study_status_overrides.csv`
in the output folder. This optional human-maintained input records a confirmed
current participant status with source ID, confirmation flag, confirmation date
and notes. It is hashed in `Input_manifest` and preserved as
`Study_status_overrides`. For example:

```csv
source_subject_id,study_status,confirmed,confirmed_on,notes
Sub3,dropped_out,true,2026-10-13,Study dropout confirmed by user
```

Confirmed source IDs are linked to canonical participants. Subjects gains
`study_status`, `study_status_confirmed_on`, `study_status_provenance`, and
`study_status_notes`; other participants remain `unknown` unless explicitly
confirmed. Supported current statuses are `dropped_out`, `withdrawn`, `active`,
and `completed`. Keep one consistent current assignment per participant.

The confirmation date records when the information was confirmed, not the date
of dropout. Current status is not applied retrospectively to individual visits.
No questionnaires, recordings, label values or phenotype values are removed or
filled because of dropout. Missing-source audit entries remain counted, with
informational severity for confirmed dropout participants. Missing data for
other participants retain their existing audit classification. The original
collaborator `Source_exclusions` sheet is preserved separately and never rewritten
or interpreted as a dropout list.

## Source schemas and added collaborator tables

`config.sources` explicitly maps source ID, filename, sheet, target table, header
and category rows, first data row, subject/recording/measure/group/study-date
columns and optional original-header-to-output `column_map`. The defaults parse
two-row physiology headers and category-prefix parameters such as
`respiration_diaphragm_trise_ms` versus `respiration_lungs_trise_ms`. Source units,
original names, categories and column numbers are retained in `Import_mapping`.
Unnamed populated columns remain `source_column_<number>` and are audited.
Do not assign them a physiological interpretation without documentation.

Additional Marcin/Marta sources can use another explicitly configured schema:

```matlab
extra = config.sources(1); % start from an appropriate source template
extra.source_id = 'marta_m1'; % stable, unique source identifier
extra.file = 'D:\path\updated_marta.xlsx';
extra.sheet = 'Confirmed_measurement_sheet';
extra.subject_column = 'Subject';
extra.header_row = 2;
extra.category_row = 1;
extra.first_data_row = 3;
extra.fixed_measure = 1;
extra.column_map = {'Documented original name', 'confirmed_output_name'};
config.sources(end+1) = extra;
```

Verify every schema field against that source before running. Missing configured
key headers fail explicitly. Added non-key columns are imported automatically.
For questionnaire schemas, map stable characteristic names explicitly (e.g.
`{'Date of birth','dob'}`); never guess unfamiliar clinical field meanings.

Questionnaire and StressTest source rows are appended, not merged. For recording tables, rows
from different sources may merge only on their complete validated primary key.
Complementary nonmissing fields fill unavailable fields; original source cells
remain in the MAT. Matching values do not cause row multiplication. Same-source
duplicate primary keys are errors. Conflicting nonmissing measurements prevent
master export unless **all contributing sources** have documented explicit ranks:

```matlab
config.source_precedence = ["marta_m1", "collaborator_m1"];
config.source_precedence_reason = 'Documented corrected source replaces prior export';
```

Rules apply per field using the highest-priority source with an actual value.
Each conflict/resolution is audited; absent high-priority values cannot erase
valid lower-priority observations. Avoid enabling precedence without source
documentation. Original source scientific values are not recalculated.

## Reference data, audit and reproducibility

Additional sheets preserve the Questionnaire dictionary, drug/job/ICD-10 keys,
and original exclusion list. `Repeat_ID_mapping` retains every original mapping
row with participant/visit identifiers. `Identity_map`, `Import_mapping`,
`Input_manifest` and `Audit` document relationships, field mappings, SHA-256 input
hashes, and unresolved identities/chronology, duplicate keys, unmatched recordings,
missing modalities and conflicting fields. These are integration records, not
statistical analysis tables. Physiological rows with no numeric data remain.
Visits known only from questionnaire/mapping are also flagged when physiology
has no source recording rows; their M1/M2 recordings are never invented.

Validation checks unique primary/foreign keys, every source row's one-to-one
output mapping, no accidental expansion, shared identities and preservation of
source values/missing tokens. Reviewed fractions and phenotype values are
imported as supplied, including fully unavailable reviewed layers; automatic
values never fill them. Additional measurements/columns need no count-specific
code. The same source content, schemas and confirmed overrides produce the same
substantive table values/order; generated ZIP timestamps are not identity keys.

Fatal errors write the audit and withhold master exports; a previous generated
master is not updated. Nonfatal unresolved chronology stays explicitly missing.
The import checks that workbooks did not change while being read, refuses input
path overwrite, and stages generated tables before replacing output files.

