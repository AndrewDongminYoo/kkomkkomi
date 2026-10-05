# M3-04b: the active client limit and the PDF footer

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A company cannot keep more active clients than its plan allows, and the report preview and PDF leave out the footer text for a paid company, so the plans screen of 4a describes behavior that the app has. After this pull request, a release build is allowed again.

**Architecture:** The domain gets the client limit of each plan. `ClientListCubit` asks `Entitlements.currentPlan()` only when the company already has at least as many active clients as the Free limit, and the client list shows a notice with an entry to the plans screen at the limit. The visit report decides the footer from `Identity.hasPaidEntitlement()`, the same token claim that decides the web report footer, and `lib/export/` gets a flag that leaves the footer text out.

**Tech Stack:** Flutter, `bloc`, `bloc_test`, `mocktail`, `pdf`.

**Spec:** [`docs/specs/2026-10-04-m3-subscriptions-design.md`](../specs/2026-10-04-m3-subscriptions-design.md), section "Device rules". The split is [`2026-10-05-m3-subscriptions.md`](2026-10-05-m3-subscriptions.md); the operator split PR 4 into 4a (#45) and 4b on 2026-10-05 and chose the client limit as the second entry of the plans screen. Refs #36.

## Global Constraints

- Limits (spec, "Purpose and approved scope"): Free 2 active clients, Basic 5, Pro no limit. An active client is a client that is not archived. Put the limit on `Plan` in the domain (for example `int? get clientLimit`, null for no limit) with a domain test.
- Keep RevenueCat out of the path of a Free company that stays under the Free limit: `ClientListCubit` asks `Entitlements` only when the count of active clients already equals or exceeds the Free limit. This continues the rule of 4a that a screen contacts RevenueCat only when the plan matters to it (`4f3d071`).
- At the limit, the add control shows a notice that names the plan and its limit and offers an entry to `PlansPage.route()`, instead of the name dialog. `addClient` checks the limit again before it saves, so a race cannot pass it. Nothing is deleted or archived, and a company above its limit after a downgrade keeps every client and cannot add one.
- `currentPlan()` gives the last plan that it knew, or Free without any answer (port contract), so the limit fails toward Free only when RevenueCat never answered on this device.
- The PDF and the report preview leave out the footer text when `Identity.hasPaidEntitlement()` answers true for the open visit report, and print it otherwise. This departs from the spec's "The PDF prints the footer unless the cached entitlements hold `basic` or `pro`": the token claim is the same source as the web report footer (#44), it keeps RevenueCat out of the PDF path of every company, and an offline device prints the footer, which fails toward the footer as the spec's trust boundary does. The pull request body states the departure.
- `lib/export/` still imports only the domain and `package:pdf`: the caller passes a flag (for example on `ReportDocument` or as a renderer argument). Keep the page number in the footer row when the text is left out.
- The privacy pages (both languages) and their test: section 9 names each moment when the app contacts RevenueCat; add the moment when a company at the Free limit asks to add a client. If a section enumerates the moments when the app sends a request to Google (token refresh), add the visit report screen.
- Records: the split plan and the console note drop the constraint that no release build is made between 4a and 4b, and say that releases are allowed again after this merge, subject to the deploy order (the rules of #42 before a build that writes `unbranded`).
- User-facing text: `user-facing-copy` skill (Toss-style 해요체), ARB keys in both languages, `KeepAllText`, and no overflow at `tester.useNarrowScreenWithLargestText()`.
- Coverage of `lib` stays at 100%, and `merry run check` passes. Name no price, billing term, or fee.

## Review Focus

1. A Free company with 0 or 1 active clients adds a client: no call to `Entitlements` at all (a counting fake proves it).
2. A Free company with 2 active clients (and any number of archived ones) taps add: the limit notice and the plans entry, no name dialog, no save.
3. A Basic company with 4 active clients adds the fifth, and is stopped at the sixth; a Pro company with 12 adds the thirteenth.
4. A company with 3 active clients after a downgrade to Free keeps all three, and cannot add.
5. The PDF and the preview of a paid company have no footer text and still have the page number; an offline or Free company's PDF has the footer.

---

### Task 1: The domain limit

- Modify: `lib/domain/plan.dart`; Test: `test/domain/plan_test.dart`
- [ ] Tests for each plan's limit and an `allowsAnotherClient(int activeClients)` (or equivalent) at each boundary; implement; commit `feat(domain): give each plan its active client limit`.

### Task 2: The client list limit

- Modify: `lib/presentation/client_list/cubit/client_list_cubit.dart`, `client_list_state.dart`, `lib/presentation/client_list/view/` (the add control and the notice), `lib/presentation/client_list/view/client_list_page.dart` (read `Entitlements` from the context), ARB files, `test/helpers/fakes.dart` if `FakeEntitlements` needs call counting
- Test: the client list cubit, view, and page tests
- [ ] Tests for Review Focus 1–4 and the narrow-screen check of the notice; implement; `merry run check`; commit `feat(clients): stop adding clients at the plan's limit`.

### Task 3: The report footer

- Modify: `lib/export/` (the flag, the renderer, the document builder), `lib/presentation/visit_report/` (read `hasPaidEntitlement()` once when the screen opens, show the preview without the footer text, and render the PDF with the flag)
- Test: `test/export/report_pdf_test.dart` (with `PdfSummary`), `test/export/boundary_test.dart` stays green, the visit report cubit and page tests
- [ ] Tests for Review Focus 5; implement; `merry run check` and `merry run coverage`; commit `feat(report): leave the footer text out of a paid company's PDF`.

### Task 4: Disclosure and records

- Modify: `web/privacy/index.html`, `web/privacy/en/index.html`, `test/web/privacy.test.mjs`, `docs/notes/2026-10-02-first-test-distribution.md`, `docs/plans/2026-10-05-m3-subscriptions.md`, `CLAUDE.md` ("Current state", the client list, the visit report, and the release constraint)
- Create: this brief as the first commit of the pull request
- [ ] `merry run web`, cspell with `--gitignore-root` (the worktree root), `trunk check`; commit `docs(privacy): name the client limit check as a RevenueCat contact` and `docs: describe the client limit and the PDF footer`.

The pull request body lists the departure from the spec, and the Hosting deploy after the merge, with the operator's approval.
