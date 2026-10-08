# Capture dates on visit reports

## Problem and direction

Issue #83 identifies that a camera photo taken on another day shows only its time under a report headed with the visit date.
The in-app camera of merged PR #79 now records an observed capture time, so that caption can mislead a report recipient.
The operator approved continuing #83 through the PR loop after its selection.

## Behavior

Convert the observed capture timestamp to device-local time, as the existing report caption does.
Compare its complete calendar date with the time-zone-free `VisitDate`.
When the dates match, retain the existing `Captured HH:mm` or `촬영 HH:mm` caption.
When they differ, show `Captured yyyy-MM-dd HH:mm` or `촬영 yyyy-MM-dd HH:mm`, including the year.
The preview and shared PDF receive the same labels.
Keep gallery provenance, unknown capture times and missing-photo behavior unchanged.
No web metadata, stored timestamp, public API, timezone policy, dependency or release change is needed.

## Acceptance criteria

1. A different capture day shows its date and time in the preview and actual shared PDF, in English and Korean.
2. A matching local day retains the time-only caption, including an instant whose UTC date differs from its local date.
3. A different year with the same month and day still shows the capture date.
4. Captions remain complete at 320 logical pixels and the largest supported text size.
5. Gallery and unknown-time captions remain covered by the existing regression tests.

## Evidence and limits

The issue is https://github.com/AndrewDongminYoo/kkomkkomi/issues/83.
`reportLabelsOf` owns the localized callback used by both outputs; `VisitDate` is explicitly a calendar date without a timezone.
Project-scoped Oracle retrieval for capture time and report date returned \[no precedent found\].
Device-local presentation can differ when a report is generated in another timezone; this preserves the existing behavior rather than introducing a location or timezone record.
Operator visual approval of rendered preview and PDF artifacts remains required before merge.
