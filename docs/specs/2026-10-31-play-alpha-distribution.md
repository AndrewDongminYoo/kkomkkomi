# Closed Alpha distribution of build 6 (#40)

## Approved outcome

On 2026-10-31 the operator explicitly selected the closed `alpha` track for existing production `1.1.2`, version code `6`.
The earlier internal draft is a different track and is not the distribution target of this request.
Reuse the uploaded bundle from clean source `bcac1e4e7dbbdcf04c4241f082e695cde5fde5f8` and its [verified provenance](../notes/2026-10-31-production-build-provenance.md).

## Invariants

- Verify live source/destination states and the production package `kr.donminzzi.kkomkkomi` before a write.
- Use the native Play Console existing-bundle release flow; the existing upload lane would upload the same version code again.
- Record the exact release target before dispatch and reconcile an unknown outcome before retrying.
- Keep production, internal tester configuration, countries and existing closed-test eligibility unchanged.
- Verify Alpha's resulting version/status and the existing tester participation/access page separately.
- Keep Android installation, device compatibility, actual code 6 delivery and runtime behavior unverified without an eligible Android device.

## Acceptance and limits

Read back Alpha code 6 and distinguish a saved draft, review submission, publication and tester access.
An authenticated web page may establish tester membership or an available participation route; it cannot establish an Android install or the delivered binary version.
No tester enrollment, account/list change, binary rebuild/reupload, production rollout, listing/image transfer or backend deployment is included.
Issue #40 remains open for acceptance not observed, including its separate internal-track criterion.
No product UI change is proposed, so visual implementation approval is not applicable.
