# CoreML trade-offs and decision

**Decision status:** Approved by Yisheng Jiang on 2026-09-26 (PT).

## Context

The app runs the `liebharc/homr` OMR pipeline on-device with ONNX Runtime (ORT) 1.24.2. SegNet and the encoder use fp16 models through the ORT CoreML execution provider (EP), with CPU fallback. The decoder remains fp32 on the ORT CPU provider only so that its output matches homr's tokens exactly; the encoder context is cast from fp16 to fp32 before it enters the decoder. The models have been bundled in the app since build 3.

The compatibility gate is a C-scale staff that must produce 12/12 expected tokens, together with a nine-page oracle parity guard against drift. This keeps the CoreML acceleration boundary measurable rather than relying on visual similarity alone.

## Measurements

The following measurements were taken on-device with build 5 on an iPhone17,5 running iOS 26.3, using ORT 1.24.2, on 2026-09-26 (PT):

| Session | Create | First run | Memory |
| --- | ---: | ---: | ---: |
| SegNet, CoreML | 2,750 ms | 235 ms | 239 MB footprint |
| Encoder, CoreML | 30,751 ms | 155 ms | 817 MB peak |
| Decoder, CPU | 268 ms | 196 ms | 430 MB footprint |

Total warmup was 34,370 ms. Gate 1 passed 12/12, with a 378 ms decode. As a comparison point, OMR Core measures a full-page parse at 3–6 seconds on Linux CPU-only, with a peak of about 1.3 GB.

## What CoreML gives us

CoreML can use the Neural Engine and GPU, which improves inference speed and can reduce power use during repeated scans. Its fp16 execution also reduces model and activation memory compared with an all-fp32 path.

## Costs and risks

The first CoreML session creation is a slow compile that is effectively per chip. It can happen again after reinstalling the app, updating iOS, or purging the system cache. The encoder's 30.751-second create time dominates current startup, and the high startup footprint compounds the memory needed by a full-page parse, creating a real jetsam risk.

fp16 execution and Apple's partitioning can drift across OS and device releases. That is why the decoder stays on the ORT CPU provider in fp32: it is the exactness boundary for homr token parity. CoreML is also a black box whose partitioning and performance can change with iOS versions, and unsupported operators may silently fall back to CPU.

## Alternatives considered

**CPU-only for everything.** This would load quickly, remain deterministic, and preserve an exact homr match, but each scan would be slower and use more battery.

**Ship a native precompiled CoreML encoder (`.mlmodelc`).** This would make the first launch fast, but it would remove ORT from that model, violate the locked rule that the encoder runs through the ORT CoreML EP, and add a second model artifact. Every model update would also require re-validation against homr.

## Decision and implementation direction

The approved decision is to keep the ORT CoreML EP and add a persistent model cache. OMR Core is adding `ORTCSession(modelURL:provider:cacheDirectory:)`; this maps to CoreML's `ModelCacheDirectory` and throws when used for CPU sessions. The app should use `<Application Support>/coreml-cache/<sha256 from models.lock>/` for the encoder and SegNet only, exclude that directory from backup, and prune stale directories.

The cache key must not depend on the bundle path because the container UUID changes when the app is updated. Use `COREML_CACHE_KEY` in the model metadata or an explicit key derived from the `models.lock` SHA. Warmup should begin in the background at app launch so the first compile overlaps with framing the photo rather than blocking the capture flow.

## Open items

After the cache lands, measure a warm relaunch and confirm the compile is avoided. Also measure the peak footprint of one full-page parse on the device; record the result in Diagnostics and make it available through **Copy as prompt**.
