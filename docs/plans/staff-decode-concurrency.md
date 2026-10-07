# Staff decode concurrency

Owner: OMR iOS. Measured structure for Copy-as-prompt; fill device numbers when available.

## Rules

- Each concurrent staff owns its own encoder ORT session, decoder ORT session, and `OrtIoBinding` / KV state.
- Do **not** share one `OrtIoBinding` across staffs.
- Do **not** assume concurrent `RunWithBinding` on one ORT session is safe — use `PageInferenceSession.staffPool`.
- Progress callbacks stay monotonic (`completed` only increases).
- Results stay in `layout.staffs` order.

## Defaults

| Platform | `recommendedStaffConcurrency` |
|----------|-------------------------------|
| iPhone (UIKit) | 2 |
| Linux / macOS host / warmed single session | 1 |
| Override | `OMR_STAFF_CONCURRENCY=1\|2\|4` (capped at 4) |

App path that reuses one warmed encoder+decoder stays at concurrency **1** until a pool is created (`PageInferenceSession.load`).

## RSS note (approx, fp32 decoder + fp16 encoder ONNX)

| Slots | Extra model RSS (order of magnitude) |
|-------|--------------------------------------|
| 1 | baseline (~decoder 47 MB + encoder 26 MB) |
| 2 | +~73 MB |
| 4 | +~220 MB |

## Device table (fill from Copy-as-prompt)

| Device | conc=1 wall ms | conc=2 wall ms | conc=4 wall ms | peak phys_footprint | notes |
|--------|----------------|----------------|----------------|---------------------|-------|
| (pending) | | | | | after decoder zero-copy |

Bottleneck after KV zero-copy (Linux CPU sample, C-scale staff): encoder ~0.9–1.0 s, decoder ~0.24–0.32 s (13 tokens). On device, CoreML encoder may invert that — re-measure.
