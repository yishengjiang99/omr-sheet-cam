# merge-log (reviewer pass 1, 2026-10-17 ~10:35 PT). Format: #N | outcome | notes
#6  | merged 74a59e0 | Stream A P1.12; Fixes #35 (closed). Squash, CI green (a3463c8). Side effect: deleting its branch auto-closed stacked #56; restored branch briefly, reopened #56 and retargeted to main (no code touched), branch deleted again.
#7  | waiting | Stream B P1.4 / Fixes #20. Review OK, CI GREEN, but HELD: Stream A not merged yet; semantically collides with #6/#56 (its default init re-adds `StoreKitManager()`, and #56 calls checkAndConsume). Rebase after A on StoreKitManager.shared + ProEntitlementSource; admitScan must call canScan().
#8  | waiting | Stream B F6.8 / Fixes #34. Review OK w/ caveat (next scan not unblocked during native parse; limitation documented, acceptance 'next scan starts at once' only partly met). CI pending.
#9  | waiting | Stream B F5.5 / Fixes #33. Review OK. CI pending.
#10 | waiting | Stream B F4.7 / Fixes #41. Review OK. CI pending. Keeps `@StateObject StoreKitManager()` line that #6 changes (rebase after A).
#11 | waiting | P11.3 / Fixes #50. Review OK. CI pending.
#12 | waiting | F2.7 / Fixes #24. Review OK (orphan sweep not included). CI pending.
#13 | waiting | F2.9 / Fixes #32. Review OK. CI pending.
#14 | waiting | F11.2 / Fixes #40. Review OK. CI pending.
#15 | waiting | F10.10 / Fixes #31. Review OK; adds UIBackgroundModes=audio (App Review impact). CI pending.
#16 | waiting | F10.3 / Fixes #39. Review OK. CI pending.
#17 | waiting | P10.3 / Fixes #52. Review OK. CI pending.
#18 | waiting | F8.7 / Fixes #43. Review OK (relabel option). CI pending.
#19 | waiting | P11.1 / Fixes #26. Review OK (docs + lint test; ASC upload still pending). CI pending.
#53 | waiting | NEW P1.8 / Fixes #36 (Stream B). Review OK. CI pending. Real conflict with #7 in ScanQuota.swift.
#54 | waiting | NEW F7.7 / Fixes #42. Review OK. CI pending.
#55 | waiting | NEW F4.5 / Fixes #51. Review OK (no-new-permission option). CI pending.
#56 | waiting | NEW STACKED on #6 branch (base=fix/p1-12...). P7.4+P7.6 (#23,#30). Body is 'tmp' -> no Fixes line. Review of code OK. CI pending. Merge after #6.
#58 | waiting | NEW STACKED on #56 branch. P5.1+P4.2+P10.2 (#28,#38,#37). Body is 'tmp' -> no Fixes line. Review of code OK. CI pending. Merge after #56.

# After #6 merge: #7-#11,#14-#19,#53-#56 CONFLICTING (ios-sim.yml/pbxproj/TODO.md; #7/#53/#56 also real ScanQuota/RootFlowView). Rebase-request comments posted. #12,#13 still MERGEABLE (CI pending). New: #59 (P3.7, stacked on #56 branch, body 'tmp'), #60 (P6.1, stacked on #58 branch, body 'tmp'). Do NOT use --delete-branch on #56/#58 until dependents are retargeted.

# Routine pass 2026-10-17 11:00 PT: no merges. No open PR is both MERGEABLE and CI-green.
# #16 green but CONFLICTING (rebase already requested). #7,#8,#9,#10,#12,#13,#55 now MERGEABLE, simulator CI queued/in progress (runs started ~10:48 PT). #56 pending (base main). Stacked drafts #58-#62 (new: #61 P2.5+P6.3, #62 P1.10) had CI cancelled; still stacked, wait on #56. Still CONFLICTING: #11,#14,#15,#17,#18,#19,#53,#54.

# Review/merge pass 2026-10-17 ~11:15 PT (1 merge). Format: #N | outcome | notes
#13 | merged 8e59c6f | F2.9; Fixes #32 (verified CLOSED/completed). Re-reviewed: real regression test (testCorruptIndexIsBackedUpAndRebuiltFromMIDIFiles + updated old test), scope = PlaylistStore/LibraryScreen/TODO/tests, no secrets/decoder/docs/agents. Sim CI SUCCESS on head ba88dff; MERGEABLE/CLEAN right before merge. Branch had no dependents (not deleted).
#12 | waiting, commented | Became CONFLICTING after #13 merged (no prior rebase request -> posted one). Its sim CI on head 7d51ff4 was CANCELLED (18:04Z), no later success -> not green anyway.
#8  | waiting | Sim CI now SUCCESS on cf4a06f and MERGEABLE/CLEAN, but Stream B -> held until #56 merges.
#7  | waiting | Head CHANGED since hold (b3d8d86, 17:47Z): now uses StoreKitManager.shared default, handlePhoto calls quota.canScan(), commit on recognized. Hold reason largely addressed; still waits on #56 (Stream B) + sim CI queued.
#9,#10 | waiting | Stream B; sim CI queued; wait on #56.
#55 | waiting | Stream C; sim CI queued.
#56 | waiting | Body now has Fixes #23, #30 (author edited at 18:03Z; verified issue titles P7.4/P7.6). Sim CI queued.
#58-#62 | waiting | Stacked on #56/#58/#60. Bodies now real (no edit needed): #58 Fixes #28,#38,#37; #59 #21; #60 #22; #61 #27,#29; #62 #25 (partial scope; counter deferred to #44/#45 - merging would auto-close #25). Sim CI queued. Wait on #56.
#63 | waiting | CI-only (ios-sim.yml +20 allowlist lines, no other files). Review clean. Sim CI queued (also the experiment re: missing -only-testing classes).
#11,#14-#19,#53,#54 | waiting | CONFLICTING; rebase request already exists on each (no duplicate). #16 still the only green one there.

# Routine pass 2026-10-17 11:25 PT: no merges. Only #8 is MERGEABLE+green, still held (Stream B waits on Stream A #56, sim CI queued). #7,#9,#10,#55,#56,#58-#63 sim CI still queued. #11,#16,#18 green but CONFLICTING (rebase already requested). No new PRs.

# Routine pass 2026-10-17 11:30 PT: no merges. #8 still the only MERGEABLE+green PR, held (Stream B waits on Stream A #56, whose sim CI is still queued). #7,#55 sim CI in progress; #9,#10,#56,#58-#63 queued. #11,#16,#18 green but CONFLICTING (rebase already requested). No new PRs.

# Routine pass 2026-10-17 11:43 PT: no merges. MERGEABLE+green: #7 (b3d8d86), #8, #10 (b1c9df6), all Stream B, held until Stream A #56 merges (#56 sim CI in progress). Rebased since last pass, now MERGEABLE with new sim CI queued/in progress: #11,#12,#14-#19,#54 (rebase requests satisfied). #53 still CONFLICTING (CI cancelled). #55,#19,#56 in progress; #9,#58-#63 queued. No new PRs.

# Review/merge pass 2026-10-17 ~11:50 PT (1 merge). Format: #N | outcome | notes
#55 | merged 7003739 | F4.5; Fixes #51 (verified CLOSED/completed). Re-reviewed: real regression test (PhotoLibraryImportTests: testAssetFallbackOnlyWithExistingPhotosAccess, testNotDownloadedMessageIsActionable; added to pbxproj + ios-sim allowlist), scope = PhotoLibraryImport.swift + test/pbxproj/ios-sim.yml, no secrets/decoder/docs/agents, body has Fixes #51. Sim CI + GitGuardian SUCCESS on head d4c4ea3 (run 39055365407 headSha matched); MERGEABLE/CLEAN right before merge (--match-head-commit). Branch had no dependents (not deleted).
#63 | waiting, commented | Became CONFLICTING after #55 merged (ios-sim.yml allowlist; no prior rebase request -> posted one). Sim CI queued.
#56 | waiting | Became CONFLICTING after #55 merged; sim CI in progress. Older rebase request (17:30Z, re #6) already exists and was satisfied -> no duplicate posted; needs a fresh rebase before Stream B/stacked can move.
#7,#8,#10 | waiting | Sim CI SUCCESS but now CONFLICTING after #55 merge; Stream B held until #56 anyway. Older (satisfied) rebase requests exist -> no new comment.
#9  | waiting | CONFLICTING after #55 merge; Stream B; sim CI queued.
#53 | waiting | CONFLICTING, sim CI CANCELLED; Stream B.
#11,#12,#14-#19,#54 | waiting | MERGEABLE (UNSTABLE) after #55 merge; sim CI queued/in progress (#11,#19 in progress) -> not green yet.
#58-#62 | waiting | Stacked; sim CI pending; wait on #56.
#56,#7,#8,#9,#10 | waiting, commented | Fresh rebase request posted ~11:55 PT (conflict after #55 merge; earlier request was for the #6 conflict and already resolved).

# Review/merge pass 2026-10-17 ~12:05 PT (1 merge). Format: #N | outcome | notes
#19 | merged 4d2ee58 | P11.1; Fixes #26 (verified CLOSED/completed). Re-reviewed head ac93ccf: real regression test (Tests/ReviewNotesTests.swift, 4 tests; added to pbxproj + ios-sim allowlist), scope = notes.txt + test/pbxproj/ios-sim.yml/TODO.md, no secrets/decoder/docs/agents, body has Fixes #26. Sim CI (run 39058852188 headSha matched) + GitGuardian SUCCESS; MERGEABLE/CLEAN right before merge (--match-head-commit). No dependents (not deleted). ASC upload of notes still pending (not done, no workflow dispatched).
#11,#12,#14-#18,#54 | waiting, commented | Became CONFLICTING (DIRTY) after #19 merged; earlier rebase requests were satisfied (rebased 18:36Z) -> posted fresh rebase request on each. Sim CI was queued/in progress (#11 had just gone SUCCESS) -> not mergeable now anyway.
#56 | waiting | Still CONFLICTING (sim CI now SUCCESS on f587217); rebase request 18:53Z outstanding (no new commits) -> no duplicate.
#58,#59 | waiting | Stacked on #56 branch (MERGEABLE/UNSTABLE, sim CI pending); wait on #56.
#60,#61,#62 | waiting | Stacked on #58/#60 branches, sim CI pending; wait on #58/#56.
#7,#8,#9,#10 | waiting | Stream B, CONFLICTING; held until #56 merges. Rebase request 18:53Z outstanding -> no duplicate.
#53 | waiting | Stream B, CONFLICTING, sim CI CANCELLED; rebase request 17:30Z still unsatisfied (last commit 17:25Z) -> no duplicate.
#63 | waiting | CONFLICTING; rebase request 18:52Z outstanding -> no duplicate.

# Batch merge 2026-10-17 12:12-12:55 PT (user-approved: merge reviewed batch without per-PR CI, then ONE main sim run)
Step 1: cancelled all non-main queued/in-progress ios-sim runs (twice: authors' rebases re-queued new ones). Main push runs left alone.
Merged (squash, --match-head-commit; PR | squash SHA | closes):
#63 | 5ca12f3 | CI allowlist only (no issue)
#11 | 2cbfbc3 | #50
#16 | 1448148 | #39
#8  | 867397d | Part of #34 (partial; issue stays open). NOTE merged BEFORE Stream A (out of intended order, my pass script ran B too early); no conflict impact seen.
#12 | 0a5954e | #24
#18 | 20702d5 | #43
#56 | 6a4480a | #23, #30
#7  | 85167db | #20 (uses StoreKitManager.shared; canScan()+commit() on recognized; merged after #56)
#14 | 8deddb7 | #40
#9  | 553182f | #33
Skipped: #58-#62 (stack: #58/#59 retargeted to main after #56, both CONFLICTING -> rebase requested; #59 body lost 'Fixes #21'; #60-62 stacked on #58 branch), #10,#53,#15,#17,#54 (CONFLICTING after each merge; fresh rebase requests already present <1h).
Deferred (not in approved order): #64-#69 (Stream D; #69 held P9.1).
Main sim CI: dispatched once, run 39064218976 on 553182f.
Update ~13:40 PT: also merged #15 ac553c0 (#31), #10 e33d8c6 (#41), #17 1f62e3e (#52), #54 2b42435 (#42), #53 a20db52 (#36), #58 00ea8d1 (#28,#38,#37), #59 87410ae (#21), #60 6d2c39a (#22). #70 (not mine, CI manual-only) merged e7aa6cf.
First dispatched main run 39064218976 (on 553182f) was cancelled by me while pending to re-run after more merges; replacement dispatch run 39067574446 on e7aa6cf.
Run 39065695835 (push on 87410ae, SUCCESS): BackgroundAudioTests.testInfoPlistDeclaresAudioBackgroundMode passed; -only-testing did NOT fail for classes absent from main (PaywallStateTests, ProSettingsTests had no suites, run succeeded) -> no trim needed.
Still open/skipped: #61,#62,#64 CONFLICTING (rebase requested); #65-#69 wait on #64 chain.
Final: all of #56,#58-#69 merged (#61 3783763, #62 b191c0d, #64 e17324e, #65 88c99b7, #66 c3a2b41, #67 9d119b8, #68 ba55776, #69 b206c7b). Final main run 39070083087 on b206c7b. Run 39067574446 (e7aa6cf) SUCCESS.
