# WORKLOG: sf2-201-pin (SF2Engine → SoundFont 2.01, .gbk = .spec)

- The sf2player-swift pin moves from 53b4503 to 24e105f (branch sf2-201-gbk-sync, PR sf2player-swift#2). At this pin `.gbk` is an alias of `.spec`, and the engine now has a non-normative master bus: -3 dB gain, compressor, lookahead limiter at -0.3 dBFS, and a safety clip.
- Because `.gbk == .spec`, `SF2SequenceBuilder.plan` always builds the spec plan. That plan has per-channel presets, CC and bend events, drums on ch 10, and a makeup gain of x2.
- The parity references were regenerated with `scripts/sf2-parity/render-gbk.mjs` against gbk eee3c44 (branch sf2-201-compliance, PR gbk#38). The script's `buildPlan` now mirrors `specPlan`. Result on Linux: both songs are bit-exact (bitExactPCM=true).
- How the expected values changed:
  - The level is about -12 dB versus the old gbk-legacy refs. For c_scale, peakL moved from 0.1445 to 0.0365. Causes: no sample peak-normalization, the 2.01 attenuation and velocity curves, one voice per preset split, and the -3 dB master gain. The spec plan's x2 makeup gain is included.
  - The first audible frame moved from 44 to about 124: 66 frames of limiter lookahead, plus the 2.01 delay/attack minimum.
  - There is one more setPreset event per channel, from the spec plan.
- Test expectations updated:
  - SpecPlanTests: the default plan is now the spec plan.
  - PracticeFeatureTests.testSeekIntoAHeldNoteSoundsIt: the voice count is now taken 256 frames after the seek, because the 2.01 release ends the short E4 inside the old 2048-frame window.
- Local `swift test --package-path Packages/SF2Player` (Linux): 33 tests, 0 failures. The iOS simulator and app tests were not run locally.

## 2026-10-22 (merge)
- gbk #38 merged (main 4a3da62); sf2player-swift #1 + #2 merged (main f7d144c). Pin -> f7d144c78b34b1a21770aa1eb747087d586f13d3.
- f7d144c adds `.spec` track CC7/10/11 through channel controller state. SF2Player plans use the power-on defaults
  (100/64/127), which never override in-stream CCs, so audio is unchanged: parity refs regenerated against gbk main
  4a3da62 differ only in `gbkCommit` (PCM metrics identical, bit-exact).
- Local `swift test --package-path Packages/SF2Player` with SF2PLAYER_SF2 set: 33 tests, 0 failures, 0 skipped.
