# Kkomkkomi Store Upload

Use the project root entrypoint with the shared `store-upload` tool.
The profile binds the personal repository identity, platform identifier, version source, artifact, and existing guards.
Build with the project's existing release commands before planning an upload.

```bash
./store-upload --store apple --operation doctor
./store-upload --store google --operation doctor
./store-upload --store google --operation binary
./store-upload --store apple --operation screenshots
```

Planning is offline and does not authenticate or upload.
Review the emitted digest, track, file hashes, command, and extra effects.
When an upload is authorized, repeat the same arguments with `--execute --expected-digest <digest> --receipt /absolute/new-receipt.json`.
The receipt directory must exist and each attempt needs a new receipt.
A successful child command remains pending remote verification and does not prove publication.

Apple credentials use `APP_STORE_CONNECT_API_KEY_JSON` or the existing standard Fastlane/`ASC_*` p8 contract.
Google credentials use an explicitly assigned `SUPPLY_JSON_KEY` outside the checkout.
No credential search or fallback is performed.
File shape is checked locally; store permissions still require an authenticated remote read.
The launcher uses `STORE_UPLOAD_TOOL` when set, otherwise `${CODEX_HOME:-$HOME/.codex}/skills/store-upload/scripts/upload.py`.
Copy the shared scripts together when using a different machine or CI; dependencies remain the project's installed pinned tools.

Use `metadata`, `screenshots`, and Google `images` as separate operations with the profile's existing Fastlane layout.
An explicit path overrides a configured asset directory; native binary lanes retain their fixed path and testing track.
Apple listing changes target an existing editable version, append screenshots, and do not submit review.
The route guide of the shared skill (`references/routes.md` beside its `scripts/`) describes the account-scoped API and browser automation of unsupported slots.

Native binary uploads run the existing release checks, including clean checkout, release notes, RevenueCat configuration, and IPA version checks.
Commit the intended release inputs before upload; uncommitted work is a blocking gate.

A binary plan also reads the build record beside the file (`build-record.txt`), which `merry run build ipa` and `merry run build aab` write: the commit of HEAD and the SHA-256 of the file.
The plan stops when the record is missing, names another commit, or holds another hash, so an upload never takes a file of an earlier build.
Build from a clean tree at the commit that you upload, because a build from a tree with uncommitted changes gets no record.
