# Approved report metadata implementation

Source: `docs/specs/2026-10-07-report-photo-and-company-metadata.md` and operator approval on 2026-10-07.

1. Add the optional local business phone, forward migration, profile form, preview/PDF header and privacy copy.
   Verify old-profile upgrades, clearing the field and omission from public payloads. Publish a draft PR for #59.
2. Add per-slot provenance and gallery selection, sanitized JPEG normalization, Android lost-picker provenance,
   and preview/PDF/web labels. Verify replacement, cancellation, recovery and publishing. Publish a draft PR for #39.
3. Add nullable per-slot time handling for an actual in-app capture hook and PDF/preview captions; old and gallery
   photos remain blank. Introduce the in-app camera only with lifecycle and cancellation tests and a device check.
   Publish a draft PR for #61, clearly separating tested metadata from camera/device acceptance.

Keep each PR reviewable; do not merge or deploy. Never insert the operator's private report URL into tracked files.
