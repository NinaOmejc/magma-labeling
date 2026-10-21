# Main-branch cleanup audit

Audited base: `fc39d88`. The keep/remove decisions below were presented before
deleting files. Inspection covered tracked MATLAB definitions/call sites,
tests, function handles, GUI callbacks, `feval`/`str2func`/dynamic-dispatch sites,
scripts, examples and documented entrypoints. No real recording files were
opened for writing. An isolated archive of committed main was used for baseline
tests; candidate testing also excludes unrelated local configuration edits.

## Decisions

| File/function | Caller(s) | Why legacy or unused | Decision | Risk | Tests affected |
| --- | --- | --- | --- | --- | --- |
| `utils/check_normalities.m`, `check_normality.m` | Only the former calls the latter | Unreachable normality workflow | Delete both; remove unused fixture setting and plot-name exception | Low | No function callers/tests |
| `feature_extraction/get_desaturation_mask.m` | None | Unused raster helper | Delete | Low | None |
| `utils/makeKey.m` | None | Unused key helper | Delete | Low | None |
| `utils/events_overlap_any.m`, `events_to_sample_mask.m`, `expand_events_for_delayed_overlap.m`, `expand_events_time.m` | None | Unused event utilities; current raster/overlap paths use other functions | Delete | Low | None |
| `utils/hasData.m`, `cellHasData.m` | Only each other | Unreachable metadata helper pair; current metadata has its own typed readers | Delete both | Low | None |
| `~$Labels.docx` | None | Tracked Word lock file | Delete only this file | Low | None |
| `align_phenotype_numeric_summary`, `validate_compact_phenotype_features` | Phenotype attachment, plotting, group and HDF5 validation | 22-feature padding/validation alternatives | Keep useful functions; remove obsolete branches and require 24 | Low | Phenotype, stage-6, group |
| `manual_edit_label_events/load_manual_event_sets` | Current manual label workflow | Pre-schema-6 field remapping, invented first rounds and missing-history migration | Keep current loader/validation; reject obsolete checkpoints | Low | Multi-round, observation, stage-6 |
| `assemble_annotation_layers/generic_review_coverage` | Annotation finalization | Former full-record review expansion without explicit sample mask | Remove expansion; retain explicit coverage | Low | Review/annotation |
| `review_existing_results` | `review` | Rebuilding old automatic summaries and synthesizing missing analysis identity | Remove historical repair; retain saved automatic evidence/profile | Low | New workflow check |
| Flat result loads and annotation appends | Runner, group readers, observation/artifact mirrors | Superseded by requested hierarchical storage | Centralize with `recording_results`; reject obsolete results | Moderate; isolated by one boundary | Storage, workflow, group, HDF5 |
| Artifact checkpoint result fallback | Cache-missing metadata lookup | Baseline exposed importing another recording's result via a copied config | Ignore mismatched result identity; retain cache identity errors | Low | Artifact identity regression |
| Version/identity/cache compatibility, optional trough overrides and polarity flags | Cache loader and preprocessing | Protect existing reviewed feature caches | Keep unchanged | High if removed | Cache/polarity/amplitude/artifact |
| Legacy per-belt artifact union | Cache loader, shared artifact helpers | Required migration of protected feature annotations | Keep | High if removed | Artifact/cancellation |
| `legacy_60s`, coherence/phase and periodic methods, `wtI`, `tlphcoh`, `wphcoh` | Method dispatch, scientific helpers; `wphcoh` has no current static caller | Published/alternative scientific implementations, possible external scientific use | Keep; absence of one static caller is insufficient for deletion | High if removed | Detector suites unchanged |
| `backup_recording_mat_files` | Explicit documented backup workflow and test | User-requested backup utility, separate from automatic review copies | Keep | Medium if removed | Thoracic preservation |
| Automatic `feature_review_backups` copies | No active creation path on audited main | Already removed in prior change | Keep absent; do not delete existing directories | Low | Artifact backup regression |
| `atomic_save_mat`, observation lock/journal and temporary rollback copies | Review transactions | Active recovery protection | Keep; add optional MAT version for result writes only | High if removed | Cancel/rollback/storage |

Ten unused MATLAB files removed **431 lines**. Additional obsolete loader,
padding and fallback branches were removed. The new result boundary, schema
documentation and synthetic tests are additive; final source line totals are
810 removed and 441 added, for **369 fewer source lines overall**. Documentation
and regression tests account for the additional non-source lines.

## Feature-cache assumptions retained

- Current cache version remains **9**. Identity, native rate, length, channel
  layout, amplitude method and relative/absolute polarity convention are checked.
- Version 5/old 20-Hz and version 8/pre-polarity automatic caches remain
  incompatible. Reviewed incompatible caches raise a clear error rather than
  silently regenerating their peaks/troughs. This policy was not broadened or
  weakened by result-format cleanup.
- Version-9 caches without optional `trough_overrides` remain readable. Missing
  historic absolute-polarity flags retain their existing false interpretation.
  Cache alignment preserves the orientation in which landmarks were reviewed.
- All saved amplitude definitions remain. A supported amplitude-method change
  can reselect a saved definition without moving landmarks; cached recheck
  requires the saved amplitude method.
- Shared artifacts take precedence, including a known empty list. Otherwise
  legacy lung/diaphragm interval lists are unioned and overlapping/touching
  intervals merge. Manually reviewed peaks/troughs, overrides and provenance
  remain intact. A schema-6 manual-label checkpoint is distinct from a protected
  respiratory feature cache.
- Cancel/X never saves a feature cache. Confirmed reviews retain the existing
  atomic cache write and observation transaction. Temporary rollback files are
  removed after success; old persistent backup directories are not removed.

## Text and duplication audit

Scientific recording-specific content remains: numeric values, missing and
availability reasons, QC codes, selected detector methods, thresholds,
parameters, observation revisions, analysis identities and review provenance.
Conditional profile limitations and the current public HDF5 descriptive fields
remain because they describe scientific interpretation and/or the export contract.

Fixed assessability rule paragraphs moved to [the schema documentation](RESULTS_SCHEMA.md).
The MAT layout stores phenotype column metadata once; duplicate editor history,
coverage, status, provenance and observation views are reconstructed internally.
Identical review numeric-summary aliases and current per-belt artifact aliases
are also reconstructed. `config.times` is omitted, with metadata supplying the
native grid. Exact configuration copies use references to their matching
analysis/annotation snapshot; distinct configuration provenance is retained.
Scientific masks, review snapshots, reviewed belt signals,
analysis-time artifact support and detector grids remain even where some values
coincide. None are discarded merely for file-size reduction.

## Verification baseline

Unchanged committed main: **122 passed, 2 failed, 0 incomplete** across 11
focused cache, respiratory artifact, observation, review-history, phenotype,
selected-label, HDF5 and synthetic group suites.

Pre-existing failures identified separately from cleanup regressions:

- `test_respiratory_artifacts/testReopenAddRemoveCommitAndRevisionMirrors`:
  cross-recording fallback identity/revision assertions (baseline line 232).
  The result fallback now checks recording identity before importing state.
- `test_stage6_freeze/testHdf5MlExportKeepsNativeAndAddsFilteredCanonicalBundle`:
  exported channel-name assertion (baseline line 914). The fixture's mojibake
  `SpO2` display text was corrected to the actual Unicode subscript spelling;
  exported signal calculations/names were already correct.

The candidate also adds lightweight storage/scientific round-trip and complete
single-recording workflow checks: automatic regeneration from reviewed caches,
`analyze_and_review`, `review`, cancellation, selected reanalysis,
immutable history, annotation revisions and MAT/HDF5 consistency. All generated
recordings, outputs and workbooks are synthetic and temporary. No full cohort
or real recording analysis is run.

Final verification: **130 unique focused checks passed, 0 failed, 0 incomplete**.
This combines the 129-test candidate suite with the latest targeted reruns after
fixes and one additional configuration-snapshot test. Both baseline failures
above now pass. The new workflow verifies exact preservation of earlier review
rounds, including empty metadata shapes, and byte-unchanged results/caches on
Cancel. MATLAB syntax checks passed for the changed source/test files.
