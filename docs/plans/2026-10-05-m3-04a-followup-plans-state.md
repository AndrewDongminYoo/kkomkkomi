# M3-04a follow-up: the pending notice of a same-plan purchase and the management link on a failed read

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the two state defects of the plans screen that #46 records, in a pull request that touches only the plans state and the one port method that it needs.

**Architecture:** `Entitlements.managementUrl()` answers a small value that tells a known answer (a URL, or none) from a failed read. `PlansCubit` keeps the earlier URL on a failed read, and it records the offer of a pending purchase and clears the pending notice when a refresh or a plan report shows that offer active.

**Tech Stack:** Flutter, `bloc`, `bloc_test`, `mocktail`.

**Spec:** #46 (https://github.com/AndrewDongminYoo/kkomkkomi/issues/46), which links the two review threads of #45. The design is `docs/specs/2026-10-04-m3-subscriptions-design.md`, and the plans screen is the brief `docs/plans/2026-10-05-m3-04a-plans-screen.md`. Refs #36. Closes #46.

## Global Constraints

- Scope: `lib/application/entitlements.dart`, `lib/billing/revenuecat_entitlements.dart`, `lib/presentation/adapters/free_entitlements.dart`, `lib/presentation/plans/cubit/`, `test/helpers/fakes.dart`, and their tests. No screen layout, no copy, no privacy text, no other port method changes.
- Every port method still answers without throwing.
- A failed `managementUrl()` read keeps the URL that the state already holds; a successful answer without a URL clears it (the behavior of `75ba4e6` for that case stays).
- The pending notice clears when the refreshed offers show the pending offer's `isActive`, when a plan report or a refresh shows a different plan than the one at the time of the purchase (the existing rule), and never because of a failed read.
- Coverage of `lib` stays at 100%, and `merry run check` passes.

## Review Focus

1. Basic monthly is active, Basic annual is bought and pending, then approved: the next refresh shows Basic annual active and no pending notice.
2. A refresh where `managementUrl()` fails while a URL is shown: the URL stays.
3. A refresh where `managementUrl()` answers no URL after the plan ended: the URL goes.
4. A pending purchase whose refresh fails: the notice stays.
5. A pending purchase of Pro while on Basic, approved: the notice clears by the existing plan rule, and the pending offer record is cleared too, so a later refresh does not act on it.

---

### Task 1: The management link answer

**Files:**

- Modify: `lib/application/entitlements.dart` (a value type, for example `ManagementLink` with `const new.unknown()` for a failed read and `const new(Uri? url)` for a known answer, and `managementUrl()` returns it), `lib/billing/revenuecat_entitlements.dart` (a caught failure gives the unknown answer), `lib/presentation/adapters/free_entitlements.dart` (a known answer without a URL), `test/helpers/fakes.dart`
- Modify: `lib/presentation/plans/cubit/plans_cubit.dart` (apply the URL only for a known answer)
- Test: the adapter tests, `test/presentation/plans/cubit/plans_cubit_test.dart`

- [ ] **Step 1:** Tests for Review Focus 2 and 3; see them fail; implement; `merry run check`; commit `fix(plans): keep the management link when the store does not answer`.

### Task 2: The pending offer

**Files:**

- Modify: `lib/presentation/plans/cubit/plans_state.dart` (the id of the pending offer, in `==`, `hashCode`, and `copyWith` with a wrapper that can clear it), `lib/presentation/plans/cubit/plans_cubit.dart` (record it on a pending outcome, clear the notice and the record when the refreshed offers show that id active, and clear the record whenever the notice clears)
- Test: `test/presentation/plans/cubit/plans_cubit_test.dart`, `test/presentation/plans/view/plans_view_test.dart` if the state constructor changes

- [ ] **Step 1:** Tests for Review Focus 1, 4, and 5; see them fail; implement; `merry run check` and `merry run coverage`; commit `fix(plans): clear the pending notice when the pending offer becomes active`.

### Task 3: Records

- Create: this brief as `docs/plans/2026-10-05-m3-04a-followup-plans-state.md`, the first commit.
- Modify: `CLAUDE.md` only where it describes the management link or the pending notice of the plans screen.
