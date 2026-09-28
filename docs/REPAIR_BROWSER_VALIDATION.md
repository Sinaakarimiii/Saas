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

## Warehouse path verified through the browser

A separate synthetic case starts at delivery version 21 with replacement handover already recorded and original disposition `parts_proposed`. Setup reused the existing two local test Auth accounts, with independent roles in the new fixture organization. Earlier stages were prepared through the SQL scenario, not exercised in the browser.

| Check | Observed result |
| --- | --- |
| Before transfer | Warehouse finalization and case closure disabled. |
| Sender releases original | Current custodian records destination, recipient, carrier, unique reference and evidence; version 21 → 22. Transfer is in transit; finalization and closure remain unavailable. |
| Intended recipient signs in | Destination receipt control available; warehouse finalization still disabled before acceptance. |
| Physical destination receipt | Recipient records independent reference/evidence; version 22 → 23; original location/custodian now match destination. Case handling owner remains unchanged. |
| Warehouse finalization | Recipient records original condition and received items; version 23 → 24; finalization control disappears and warehouse receipt remains visible. |
| Close authorization | Recipient has no close permission; UI explains the independent permission. Sender signs back in; closure is enabled. |
| Cancel/confirm closure | Two-button dialog requires no extra note. Cancel retains the delivery stage. Confirmation closes once, version 24 → 25; transfer, warehouse condition and receipt remain visible. |
| Processing boundary | Closure succeeds without parts extraction, as approved by the user. No claim of completed warehouse processing is made. |

A database read independently confirmed `closed`, version 25, `parts_received`, accepted transfer, destination/warehouse recipient/current custodian agreement, and audit outcome `replaced_original_parts_received`.

The closed-case delivery summary had lost the replacement identity shown during delivery. Its title and IMEI now stay explicit after closure, selected by the receipt's device ID. Browser reload of the rebuilt production app verifies this display. Business rules are unchanged.

This browser run covers the parts path at the desktop viewport with sequential accounts. The refurbish path and a later warehouse movement are also browser-verified in the separate scenario below. Evidence remains a synthetic text reference; file upload and signature validation were not tested.

## Responsive check

At 390 × 844, the final scrap summary and actor/evidence/approval text remain readable. Mobile navigation opens and closes. Document scroll width equals client width (390 px); the stage strip keeps its own existing horizontal scrolling. The temporary viewport override was reset afterward. Input forms and confirmation dialogs were exercised at the default desktop viewport; their mobile submission flow is not claimed here.

## Remaining checks
- Additional incident variants and role boundaries beyond the completed post/courier damage runs.
- Simultaneous independent browser logins; overlapping approval/closure RPC transactions are covered in `REPAIR_CONCURRENCY_VALIDATION.md`.
- Uploaded scrap documents/signature validation; currently evidence is a text reference.
- Production rollout and full operational acceptance.

## Replacement post delivery — browser validation

A new synthetic local case was prepared with the existing remote SQL fixture through delivery version 20. Intake, execution and QC in this preparation are server-side fixture setup, not browser coverage. The current custodian then used the production-build UI to dispatch by post to the approved colleague recipient.

| Check | Observed result |
| --- | --- |
| Dispatch | Replacement IMEI and tracking code shown; status changes to in transit. In-person receipt control disappears. |
| Before destination receipt | Original return and case closure remain disabled. Original location/custodian still show the workshop/current staff member. |
| Destination receipt | Separate reference/evidence recorded; destination confirmation summary replaces inputs. Original-return control becomes available; closure remains disabled. |
| Original return | Independent original-device receipt/condition recorded; original custody changes to the approved recipient; closure becomes available. |
| Closure dialog | Cancel preserves delivery stage; confirm closes without requiring an extra note. |
| Closed case | Replacement IMEI and destination receipt remain explicit; separate original-return receipt and history remain visible; mutable controls disappear. |

Independent database read confirms closed version 24, post receipt bound to the executed replacement, stock issued with the exact receipt, and return bound to the original device. This is one sequential owner session, not a race or two-person delivery test. All references, address and carrier are synthetic. Actual carrier integration and uploaded receipt validation are not covered. Courier damage recovery is covered in the following run. Local screenshot: `.local-db/repair-remote-post-browser-verified.png` (ignored; not published).

## Replacement courier damage recovery — browser validation

A separate synthetic fixture starts in delivery at version 20. One authorized owner session exercised the entire recovery loop in the production-build UI:

| Check | Observed result |
| --- | --- |
| First courier dispatch | Replacement identity/tracking shown; original stays in workshop custody. |
| Damage incident | Open damage blocks destination receipt and closure; physical-return form is shown. |
| Physical return | Separate reference/evidence, location and condition recorded; incident resolved; new dispatch disabled pending fresh quality controls. |
| T11 | Cancel keeps delivery stage; confirm moves to test. Prior test/outgoing check explicitly marked invalid. |
| Fresh functional test | Revision 3 succeeds but T08 remains disabled until independent test release and a fresh outgoing check/release. |
| Fresh outgoing check | Revision 3 binds the approved colleague recipient and authority. T08 becomes available only after release. |
| Second courier dispatch | New tracking/reference/evidence accepted after T08; the first return/incident remains in history. |
| Second destination receipt | Receipt accepted for the second shipment; independent original return still required before closure. |
| Closure | Original return recorded; T09 closes at version 33. Replacement receipt, original return and damage/retest events remain visible. |

Independent database read confirms damage epoch 1, old functional tests at epoch 0 and fresh revision 3 at epoch 1, first dispatch `returned`, second receipt bound to tracking `DAMAGE-TRACK-002`, stock `issued` against that exact receipt, and a resolved damage incident. The second dispatch retains the schema's `in_transit` value after receipt; destination receipt is the authoritative delivery fact. No enum change is asserted.

The browser automation's initial datetime fill did not commit a valid value. After correcting the native day segment with keyboard input, the existing form accepted the valid deadline. This is not evidence of a product fix. Synthetic evidence references, no real carrier or payment, sequential session only. Local screenshot: `.local-db/repair-damage-browser-verified.png` (ignored; not published).


## Refurbish receipt and later warehouse movement — browser validation

A separate synthetic local case starts at delivery version 21, with replacement handover already recorded and original disposition `refurbish_proposed`. Earlier stages and handover were prepared with the warehouse SQL fixture; they are not browser coverage. Two existing local Auth accounts were used sequentially through normal logout/login.

| Check | Observed result |
| --- | --- |
| Before original transfer | Refurbish receipt and closure disabled. |
| First release and acceptance | Sender records original transfer; recipient independently records physical receipt `REFURB-IN-001`; versions 21 → 22 → 23. Current physical custodian changes; case handling owner stays separate. |
| First warehouse finalization | Recipient records condition/items, explicitly stating refurbishment has not been performed; version 23 → 24. Finalization control disappears; recipient still has no close permission. |
| Later release | Recipient sends original to a second warehouse and the other staff member; version 24 → 25. Both transfers remain visible. On the close-authorized account, closure is disabled while the second transfer is in transit. |
| Second acceptance | New destination recipient records `REFURB-IN-002`; version 25 → 26. Closure remains disabled: the old warehouse receipt does not establish the new warehouse disposition. A new finalization control is available. |
| New warehouse finalization | New recipient records condition/items against the accepted second transfer; version 26 → 27. Summary switches to second warehouse/receipt; closure becomes enabled. |
| Cancel/confirm | Two-button close dialog requires no extra note; cancel leaves closure available. Confirmation closes at version 28. Both transfer references, current warehouse condition and replacement IMEI remain visible. |
| Processing boundary | Case closes with refurbishment explicitly not started, consistent with the approved documented-handover policy. This does not verify warehouse processing or restored saleable stock. |

An independent database read confirmed `closed`, version 28, `refurbish_received`, second accepted transfer and current warehouse recipient/custodian agreement. The second warehouse audit event retains complete `previousReceipt` and `currentReceipt` JSON, referencing `REFURB-IN-001` and `REFURB-IN-002`; closure outcome is `replaced_original_refurbish_received`.

No application changes were needed for this scenario. The browser run uses the existing production build at the default desktop viewport and does not establish simultaneous-session safety. Evidence is a synthetic text reference; the fixture's intake storage metadata is not a real uploaded document.


## Issued replacement re-entry — browser validation

The replacement issued in the completed refurbish scenario (`900000000000012`) was submitted through the normal new-case UI in the same synthetic organization. The prior repair case remains closed at version 28. This run uses the real application intake and Storage upload flow, rather than fixture inserts for the new case.

| Check | Observed result |
| --- | --- |
| New request | Raw IMEI recorded without automatic verification. The new case has no physical receipt and cannot advance to diagnosis yet. |
| Physical intake | Location, responsible recipient, items and label-matched IMEI entered; a locally generated PNG explicitly marked synthetic was selected through the browser file chooser and uploaded. Receipt/verified IMEI recorded at version 2. |
| Custody boundary | Prior recipient custody remains visible with an explicit request for fresh location/custodian evidence. The UI does not silently replace the earlier recipient record at intake. |
| Fresh custody baseline | Authorized staff select current custodian and record independent physical-return evidence; version 2 → 3. New location/custodian appear on the case. |
| Diagnosis transition | Two-button confirmation with no additional note; case advances to diagnosis at version 4. |
| Duplicate attempt | A second raw request for the same IMEI is allowed. Attempting physical intake with verified IMEI, uploaded synthetic label and no exception is rejected with the existing-open-case message. Diagnosis remains disabled. |

Independent database reads confirmed that the new case's verified device ID equals the prior execution's replacement device ID; current staff custody belongs to the new case. Replacement stock remains `issued`, with the prior allocation case and issued receipt preserved; the prior receipt still identifies the same replacement and the previous case remains closed at version 28. The uploaded object has `image/png` metadata and 13,372 bytes. The rejected duplicate remains intake version 1 with no physical receipt or verified device, and exactly one open verified case exists for this device.

No application changes were needed. This is sequential browser coverage of issued replacement re-entry after a closed prior case, actual synthetic image upload, custody baseline and duplicate rejection. It does not verify genuine device identity, signatures, cross-branch races, duplicate-exception approval, or available/allocated-stock rejection through the browser; existing SQL regression coverage remains separate.


## Two open browser views — stale version rejection

The re-entry case was opened in two browser tabs under the same local Auth account at diagnosis version 4. This deliberately tests stale browser state; it is not an independent-login or overlapping-database-transaction race.

| Check | Observed result |
| --- | --- |
| Conflicting drafts | Each tab contains different findings. First tab saves diagnosis revision 1, case version 4 → 5. Second tab still shows the old no-diagnosis state and its own draft. |
| Stale save | Second tab attempts its save with old version 4. UI reports `پرونده تغییر کرده است. صفحه را تازه کنید و دوباره بررسی کنید.` Its draft remains available; the server diagnosis is not overwritten. |
| Reload recovery | Reloaded second tab displays the first tab's revision 1 and findings. |
| Stale finalization | Both tabs open the same revision-1 confirmation at version 5. First confirmation finalizes once, version 5 → 6; the second confirmation is rejected with the version-conflict message inside the dialog. |
| Stale stage confirmation | Second tab reloads to version 6. Both tabs open T02 confirmation. First confirmation reaches decision, version 6 → 7; the second remains on its stale diagnosis view and receives the version-conflict message. |
| Reload after conflict | Second tab reloads into the correct decision stage, then the temporary test tab is closed. The primary case tab remains open. |

An independent database read confirmed decision version 7, exactly one diagnosis revision with the first tab's findings, one `diagnosis_saved`, one `diagnosis_finalized`, and one T02 event. Rejected stale commands produced no duplicate diagnosis/finalization/transition event. No application code changes were required.

Independent-identity approval/closure races and overlapping database lock/replay behavior are now covered separately in `REPAIR_CONCURRENCY_VALIDATION.md`. Two open tabs sharing one login are not evidence for those scenarios; simultaneous independent browser logins remain pending.
