# Repair browser validation — 2026-09-28

Stage 4: scenario validation and operational exceptions.

## Scope and environment

Latest repair slice, built with `next build --webpack` and served through `next start` on `127.0.0.1:3157`. Database/API: isolated local ports 55422/55421. Synthetic organization, original/replacement serials, customer, documents and two real local Auth accounts. No production records or payments were used.

The fixture was prepared through the existing SQL scenario up to version 21 in delivery stage, with the replacement already delivered and original disposition `scrap_proposed`. Preparation is server-side fixture setup; it is **not** browser validation of intake, diagnosis, replacement execution, QC or handover.

## Scrap path verified through the browser

| Check | Observed result |
| --- | --- |
| Before recording | Scrap inputs available to current original custodian; close disabled. |
| Missing fields | Record disabled until reference, evidence reference and execution note are filled. |
| Confirmation | Cancel/confirm dialog; no additional note is required inside the dialog. |
| Cancel | Dialog closes, fields retained, no scrap record or version change. |
| Actual record | Server Action succeeds; version 21 → 22; terminal `scrapped` original custody; record and actor displayed. |
| Recorder has both permissions | Own-approval control absent; explanation states another person must confirm. Close remains disabled. |
| Second account | Recorder's evidence, note and IMEI visible; independent approval control available. |
| Second-person approval | Server Action succeeds; version 22 → 23; distinct approving actor/time displayed. |
| Independent close permission | Second account has no close permission and receives the relevant explanation. |
| Recorder returns after approval | Close enabled; two-button closure confirmation shown. |
| Close | Server Action succeeds; version 23 → 24; closed stage, no repeat-close control, immutable scrap summary and both audit events remain. |

The accounts were switched sequentially through the normal logout/password login UI. This verifies separate identities, permissions and shared persisted state. It is **not** a simultaneous-session concurrency test.

A terminology issue found during this check was corrected: a scrapped original now displays `محل اجرای اسقاط` and `تعیین تکلیف فیزیکی`, instead of presenting a final disposition as a physical custodian. The close confirmation title is `بستن پرونده؟`.

Development-mode menu clicks initially did not respond in the first browser tab. The production build in a fresh tab responded normally; no application cause was established for the earlier observation. Do not treat that as a reproduced product defect or a confirmed fix.

## Responsive check

At 390 × 844, the final scrap summary and actor/evidence/approval text remain readable. Mobile navigation opens and closes. Document scroll width equals client width (390 px); the stage strip keeps its own existing horizontal scrolling. The temporary viewport override was reset afterward. Input forms and confirmation dialogs were exercised at the default desktop viewport; their mobile submission flow is not claimed here.

## Remaining checks
- Browser paths for warehouse disposition, remote replacement shipping, damage return/retest and issued replacement re-entry.
- Simultaneous-session stale-version, concurrent approval and closure attempts.
- Uploaded scrap documents/signature validation; currently evidence is a text reference.
- Production rollout and full operational acceptance.
