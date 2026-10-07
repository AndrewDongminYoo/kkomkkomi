# Report photo and company metadata

Date: 2026-10-07. The operator approved this scope in the all-issues session.
The M1 local-first design owns the existing units, report and persistence model.
This spec resolves the choices in #39, #59 and #61 without changing photo-slot ratios (#62).

## Company phone (#59)

Add an optional business phone to the company profile. Trim its outer whitespace; an empty value means no phone.
Keep the existing company-name validation. Edit and save both fields together.
The report preview and the first-page PDF header show the saved phone. The web publisher sends no phone,
so client pages and web reports remain name-only. No contact person, address or logo joins this change.
SQLite upgrades forward from version 5, preserving old profiles with an empty phone.
Both privacy pages name the local field and its inclusion in a PDF shared with a chosen recipient.

## Gallery (#39)

Allow one gallery image for either existing before/after slot, before the M2 live camera is introduced.
Mark that photo as selected from the gallery in the preview, PDF and web report. Do not infer its capture time.
The source belongs to the photo in its zone record; replacing a photo replaces its metadata too.
Old photos keep an unknown source, rather than being relabeled retrospectively.
Normalize supported input to JPEG, preserve the visible orientation, and remove unnecessary metadata before saving.
An unsupported or malformed image fails visibly and leaves the previous photo intact.
Device acceptance must cover JPEG, PNG and real-device HEIC picking; simulated or unit decoding is separate evidence.
The Android lost-picker path must preserve gallery provenance.

## Capture time (#61)

Only a future in-app camera capture may supply its directly observed capture time.
Store it beside the photo reference as nullable UTC data, never in Exif and never backfilled from file times,
visit dates or picker return times. Gallery, recovered picker and old photos have no capture time.
Show a supplied time in the PDF and preview only; publish no capture time to the web.
A device clock is an app observation, not independently verified evidence.
The in-app camera must manage lifecycle and cancellation and avoid recording audio.

## Verification and release

Test migration and round trips, replacement and cancellation, source labels in every output, phone/time omission
from Firebase payloads, PDF text and pagination, and the profile/capture UI at large text sizes.
Run the repository check and coverage gates. Real-device camera/gallery acceptance remains a release check.
Hosting, rules and app distribution require their own operator approval; this spec authorizes code only.
