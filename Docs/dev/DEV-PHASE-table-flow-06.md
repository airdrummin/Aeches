# DEV — Phase 06: Cleanup

## Purpose

Codebase hygiene and stabilization after all feature phases are complete. Remove dead code paths, unused state vars, orphaned functions, and legacy stubs introduced or left behind by Phases 01–05. Normalize any naming inconsistencies introduced during the refactor. This phase does not introduce any new behavior.

---

## Entry Criteria

- Phases 01 through 05 are ALL marked Complete in DEV-INDEX-table-flow.md.
- The full hand recording flow has been manually verified end-to-end:
  - Session creation → seat selection → dealer button → preflop recording → post-flop → fold-out OR showdown → New Hand
- All files in the Code Familiarity Checklist below have been read using the Read tool.

---

## Scope

### Included

- Remove any unused `@State` variables that were added as scaffolding during earlier phases and are no longer referenced
- Remove stub functions (`advanceHighlight()`, `advanceToNextSeat()`) if they were fully replaced by their implementations in Phase 03 (confirm they are not still stubs)
- Remove the `SeatSelectionView` standalone view if it is confirmed unreachable by any live navigation path. **Do not remove `TableOvalView`, `SeatButtonView`, `SeatState`, or `seatPosition()` — these are used by `HandEntryView`.** Only remove the `SeatSelectionView` struct itself if it has no live callers.
- Remove the original `saveBar` computed property from `HandEntryView` if it is no longer referenced after the Action Controller replaced it
- Remove any `// TODO:` comments that were resolved in prior phases
- Remove any `// Phase XX:` annotation comments (these were scaffolding for the dev process, not permanent documentation)
- Remove `sizeLabel: String?` from `SeatState` if it was not already removed in Phase 04
- Audit all `switch phase` sites in `HandEntryView` — ensure no leftover `case .showdown, .handClosed: break` stubs remain that were only added for exhaustive coverage; replace with real handling or confirm they are correct
- Normalize: ensure all private functions in `HandEntryView` follow the same naming convention (camelCase, verb-first: `applyAction`, `closeStreet`, `syncSeatActions`, `triggerFoldOut`, etc.)
- Remove any duplicate or shadowed `@State` vars if any were introduced across phases
- Ensure `CardSlot → Card` conversion helper is defined once and not duplicated

### Excluded

- Any new features, logic, or architecture
- Villain profiles (remains out of scope)
- Pot size, effective stack, or commentary entry
- Changes to `Models.swift`, `ContentView.swift`, `NewSessionView.swift`, or `LoginView.swift` unless they contain dead code directly introduced by this project
- Formatting-only changes to files not touched by this project

---

## Code Familiarity Checklist

Before writing any code, confirm you have read and understood:

- [ ] `/Aeches/HandEntryView.swift` — full file post-Phase 05. Read every `@State` var, every function, every `switch phase` site.
- [ ] `/Aeches/SeatSelectionView.swift` — full file. Identify which structs/functions are used by `HandEntryView` and which are only used by `SeatSelectionView` itself.
- [ ] `/Aeches/ContentView.swift` — confirm `SeatSelectionView` is not called from `RecordTab` or any other active navigation path
- [ ] `/Aeches/Models.swift` — confirm no orphaned extensions were added (e.g., `StreetName.next()`) that should remain

---

## Implementation Steps

1. **Read all checklist files** using the Read tool.

2. **Audit `HandEntryView` `@State` vars.** List every `@State` property. For each one, confirm it is read or written somewhere in the live code path. Remove any that are declared but never used.

3. **Audit private functions.** List every `private func` in `HandEntryView`. Confirm each has at least one call site. Remove any that are unreachable.

4. **Remove the `saveBar` computed property** if it has no reference in `HandEntryView.body` or elsewhere.

5. **Audit `SeatSelectionView`.** Check if it has any call sites in `ContentView.swift`, `AechesApp.swift`, or any other file. If the only reference to it is its own `#Preview`, the struct itself is safe to remove. **Preserve the file** — only remove the `SeatSelectionView` struct body if confirmed dead. The file must remain because it houses `TableOvalView` and related components.

6. **Remove resolved `// TODO:` comments** in `checkStreetClose()` and anywhere else they appear from this project's work.

7. **Remove scaffolding comments** of the form `// Phase 01:`, `// Phase 02:`, `// stub`, etc. These were dev-process annotations, not documentation.

8. **Confirm `StreetName.next()` extension** is defined once and in the correct file (it should be in `HandEntryView.swift` or a `Models+Extensions.swift` if created). If it was added to `Models.swift` directly, that is acceptable — just confirm there is no duplicate.

9. **Audit `SeatState`** — confirm `sizeLabel` is gone, `betLevel` is present, and no other stale fields remain.

10. **Audit `switch phase` exhaustiveness** — open every `switch phase` in `HandEntryView` and verify each case has real handling (not empty stubs added for compiler satisfaction in Phase 01).

11. **Run a final compiler check** — build the project in Xcode (or `xcodebuild`) and confirm zero errors and zero warnings introduced by this project.

12. **Update DEV-INDEX-table-flow.md** — mark Phase 06 as Complete.

---

## UI Verification Checklist

This phase introduces no visual changes. After cleanup:

- [ ] Full hand recording flow still works end-to-end (session → seat → dealer → preflop → postflop → showdown/fold-out → new hand)
- [ ] Card picker still opens and commits cards correctly
- [ ] Action Controller bar still renders with correct buttons per street and bet context
- [ ] Auto-highlight and auto-fold still fire correctly
- [ ] Raise arrows still display correct bet levels
- [ ] Fold-out and showdown transitions still fire correctly

---

## Stop / Go Criteria

**Stop and report if:**
- Removing any code causes a compiler error (it should not — only confirmed-dead code is removed)
- `SeatSelectionView` has an unexpected live call site not visible in a static search

**Proceed if:**
- All removals are confirmed dead code with no active references

---

## Rollback Plan

All removals are of dead code. If a removal causes a regression (e.g., a `#Preview` fails to compile), restore only that specific removed item. No behavioral rollback should be needed.

---

## Exit Criteria

- No unused `@State` vars remain in `HandEntryView`
- No unresolved `// TODO:` comments from this project remain
- No scaffolding `// Phase XX:` comments remain
- `SeatState` has no `sizeLabel` field
- `SeatSelectionView` struct is either removed (if dead) or retained with a clear comment that it is a preview host only
- Zero compiler errors and zero warnings introduced by this project
- DEV-INDEX-table-flow.md Phase 06 status updated to Complete
- Full hand recording flow verified working after cleanup
