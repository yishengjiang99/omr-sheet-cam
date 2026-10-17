# Product review tracker (internal, not filed on GitHub)
Source: /workspace/omr-audit/product-review.md   Updated: 2026-10-17

## Recommendations
| # | Item | Effort | Impact | Status |
|---|------|--------|--------|--------|
| R1 | Scan meter ("3 of 5 used") + gentler paywall sequence | S | High | Overlaps audit P1.6/P2.2 (Stream D) |
| R2 | Paywall rebuild: price hierarchy, Free vs Pro table, Restore/Manage in Settings | S-M | High | Partly in audit P6.1/P1.10 (Stream A) |
| R3 | First 60 seconds: "See it work" primary, sample with real sheet layout | M | High | Backlog |
| R4 | Capture coaching: frame guide, live light/tilt hints, pre-scan quality check | M | High | Backlog |
| R5 | Store presence: name/keywords/subtitle, replace mockup hero screenshot | S | High | Backlog (needs name decision) |

## Launch risks
- Analytics consent/opt-out (Guideline 5.1.1): Backlog
- Hero screenshot is a mockup (2.3.3): Backlog
- Paywall price hierarchy (3.1.2): covered by R2
- Pro value thin, volume-only (3.1.2(a)): needs decision

## Open decisions for Yisheng
1. Analytics opt-in vs opt-out
2. Store name incl. "Sheet Music" (trademark risk)
3. Second Pro benefit beyond volume
4. Non-renewing 30-Day Pass
5. Recognizer exposing uncertain notes

## Decisions made by Chief of Staff (2026-10-17, per Yisheng "Make decisions"; reversible, revisit anytime)
1. Analytics: opt-out with a clear Settings toggle plus first-run disclosure line (safer default; no PII). Move to opt-in if App Review pushes back.
2. Store name: keep the brand, change only subtitle/keywords to include "scan sheet music"; do NOT put the incumbent's trademark in the app name.
3. Pro value: keep volume-only for the first TestFlight; add a second benefit (export MusicXML/PDF) after launch metrics.
4. 30-Day Pass: no, not now (adds IAP/review complexity).
5. Uncertain notes: defer to post-launch; log as a recognizer feature request.
6. Hero screenshot: replace the mockup with real in-app captures before submission.
7. P9.1 contextual upsell: build behind a flag, default OFF.

## Update 2026-10-17 (Yisheng): analytics are anonymous
Decision 1 revised: no consent prompt needed beyond a short privacy-policy disclosure. Keep a Settings toggle optional (low priority). Keep the event filter dropping identifiers (see issue P10.3) so it stays anonymous.
