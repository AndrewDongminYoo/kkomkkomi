# Gallery device acceptance (#82)

## Scope

Run the existing gallery flow for JPEG, PNG and HEIC on a physical iPhone, and record the exact build and source formats.
This is partial acceptance of [issue #82](https://github.com/AndrewDongminYoo/kkomkkomi/issues/82): the operator has no Android phone, so Android physical acceptance remains open.
The [report metadata spec](2026-10-07-report-photo-and-company-metadata.md) owns normalization, provenance and failure behavior.
No conversion dependency or product behavior change is justified without a reproduced failure.
The [iPhone result record](../notes/2026-10-30-gallery-device-acceptance.md) contains the completed operator observations and the remaining evidence gaps.

## Evidence boundaries

- A mocked picker test proves the arguments and error mapping of the Dart adapter, not native picking or conversion.
- Photo-store fixture tests prove decoding, sanitization and rejection of those bytes, not which bytes the native picker returns.
- A simulator or emulator result does not satisfy either physical-device row.
- An installed version/build number does not identify its source commit or Flutter version.
- An unsupported file rejected by Photos before it reaches the app does not exercise the app's failure notice.
- Successful JPEG, PNG and HEIC picks do not prove rejection behavior.
- Synthetic HEIC fixtures exercise picking of HEIC-encoded data, not every camera, HDR, orientation or HEIC variant.

## Device pass

Prepare non-private fixtures with verified byte formats and hashes before importing them.
Record the source fixture format separately from the picker result and stored output; a filename alone is insufficient.
Use an identified development build, whose Firebase identity and publisher are unavailable, and a disposable client, zone and visit.
Keep production data intact.
Installation, launching and photo-library imports on the daily iPhone require explicit approval for the individual operation.
Do not uninstall an app, erase its data or terminate it implicitly.

1. Record the commit, build mode, flavor, bundle identifier, version/build, Flutter/Dart versions, iPhone model and OS version.
2. Pick each verified source through the real Photos picker for an existing before/after slot.
3. Record acceptance or rejection, visible orientation, the retained preview, gallery provenance and absence of an inferred capture time.
4. Reopen the visit to check persistence, then check the report preview.
5. Cancel a replacement and confirm that the previous photo remains.
6. If an unsupported image reaches the app, record the failure notice and previous-photo preservation.
   If no such input reaches the app, mark physical rejection as not observed and retain the automated evidence separately.
7. Record whether an additional conversion step is needed for the tested iPhone cases only.
   Leave the Android decision unresolved until a physical Android pass exists.

Sharing a PDF, importing fixtures, deleting fixtures, cleaning up test data and publishing reports are separate operations.
This pass does not authorize production distribution, store uploads, Firebase configuration changes or deployment.

## Completion and documentation

An iPhone-only record may be reviewed and merged without closing #82 or claiming cross-platform acceptance.
Do not use an automatic issue-closing reference in that PR.
The final record distinguishes observed results, automated results and remaining gaps.
Update applicable claims in `CLAUDE.md`, the original metadata spec and the first-distribution note in the same PR when the evidence changes those claims.
After merge, the operator-requested memory review records only a needed project-scoped correction, with the final evidence as its source.

## Precedent

Oracle returned `raw/sources/.claude/projects/-Users-dongminyu-Development-01-personal-kkomkkomi/memory/console-note-update-with-closing-pr.md` at source commit `9670d54de3076c5239713f54900c7a855bd18478`.
It confirms that device steps must follow currently implemented screens and that affected console notes belong in the same PR.
The current gallery action was checked before writing this procedure.
No HEIC-specific precedent was found, and the Oracle snapshot's current-source freshness is unverified.
