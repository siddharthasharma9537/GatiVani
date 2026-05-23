# GATIVANI PROJECT ORCHESTRATION PLAN
## Flutter Newspaper-to-Audio Application | 3-Week Production Sprint

---

## EXECUTIVE SUMMARY

**Project:** GatiVani — Flutter app converting newspapers to audio via OCR + summarization + TTS
**Current State:** Code-complete, credentials integrated, awaiting UI/tests/deployment
**Target State:** Production-ready across Web/Android/iOS with >80% test coverage
**Timeline:** 3 weeks (15 working days)
**Team:** 5 parallel subagents + orchestration layer

---

## 1. CRITICAL PATH ANALYSIS

### Dependency Graph (High-Level)

```
                  [Service Optimization Agent]
                            |
                            v
   [UI/UX Agent] -----> [INTEGRATION POINT 1] <----- [Testing Agent]
        |                   (Day 7)                       |
        v                                                 v
   [Documentation Agent] <------ [INTEGRATION POINT 2] (Day 12)
                                         |
                                         v
                              [Deployment Agent]
                                         |
                                         v
                                   [PRODUCTION]
                                     (Day 15)
```

### Critical Path Items (Sequential — Cannot Parallelize)
1. **Service layer stabilization** (Day 1-3) — UI cannot finalize bindings without stable service signatures
2. **UI shell + navigation** (Day 4-6) — Tests cannot validate flows without screens to drive
3. **Integration test harness** (Day 8-10) — Required before deployment pipeline can gate releases
4. **CI/CD secret provisioning** (Day 11) — Blocks all automated builds
5. **App store submission packaging** (Day 13-15) — Final, irreversible step

### Parallelizable Workstreams
- UI/UX building screens AND Testing writing service-level unit tests (Days 1-6)
- Documentation writing API docs AND Optimization refactoring services (Days 1-7)
- Deployment preparing pipeline configs AND all other workstreams (Days 1-10)

---

## 2. WEEK-BY-WEEK BREAKDOWN

### WEEK 1: FOUNDATION & PARALLEL BUILD (Days 1-5)

**Goal:** Stable service layer, design system locked, test harness running, CI scaffold in place.

| Day | UI/UX | Testing | Service Opt | Documentation | Deployment |
|-----|-------|---------|-------------|---------------|------------|
| 1 | Design system tokens, theme, typography | Test infra setup, mocks for FirebaseService | Audit all 47 improvements, prioritize P0/P1/P2 | API reference scaffolding | GitHub Actions skeleton, branch protection |
| 2 | Atom components (buttons, cards, sliders) | Unit tests: SarvamAIService (OCR + TTS) | P0 fixes: SarvamAI rate limiting, retry logic | Service architecture diagram | Firebase project config, env separation (dev/staging/prod) |
| 3 | Home screen + News list screen | Unit tests: GeminiService, NewsService | P0 fixes: GeminiService caching layer, token budget | Setup guide draft | Android signing config, keystore management |
| 4 | Article detail + Audio player screen | Unit tests: StorageService, FirebaseService | P1 fixes: StorageService chunked uploads | iOS deployment guide draft | iOS provisioning, App Store Connect setup |
| 5 | Settings + Onboarding flow | Widget tests: design system atoms | P1 fixes: NewsService pagination, offline cache | Web deployment guide draft | Web hosting setup (Firebase Hosting / Vercel) |

**Week 1 Exit Criteria (CHECKPOINT — Day 5 EOD):**
- Design system documented and 100% atom coverage
- Service layer signatures FROZEN (any further changes require orchestrator approval)
- Unit test coverage on services >70%
- CI runs `flutter analyze` + `flutter test` on every PR
- All 47 optimizations triaged into P0/P1/P2 buckets

---

### WEEK 2: INTEGRATION & HARDENING (Days 6-10)

**Goal:** End-to-end flows working, integration tests passing, performance benchmarks met.

| Day | UI/UX | Testing | Service Opt | Documentation | Deployment |
|-----|-------|---------|-------------|---------------|------------|
| 6 | Wire UI to services, state management | Widget tests: home/news/detail screens | P1 fixes: parallel OCR for multi-page | User guide + screenshots | CI: build matrix (web/android/ios) |
| 7 | **INTEGRATION POINT 1**: Full user flow demo | Integration test: scan -> summarize -> play | P2 fixes: telemetry, structured logging | Troubleshooting guide | Staging deployment automation |
| 8 | Accessibility pass (semantic labels, screen reader) | Integration test: offline mode, sync | P2 fixes: memory profiling, image compression | Contributing guide, code style | Crashlytics + Analytics integration |
| 9 | Localization scaffolding (Hindi, English, Tamil) | Coverage gap analysis, push to >80% | P2 fixes: lazy loading, background tasks | Architecture decision records | Beta tester pipeline (TestFlight, Play Internal) |
| 10 | Polish: animations, transitions, empty states | Golden tests for visual regression | Performance benchmarks document | API docs finalized | Production rollout plan + rollback strategy |

**Week 2 Exit Criteria (CHECKPOINT — Day 10 EOD):**
- All P0 + P1 optimizations merged
- Test coverage >80% across unit + widget + integration
- End-to-end flow demoable on all 3 platforms
- Staging environment receives every merged PR automatically
- Crash reporting and analytics emitting events

---

### WEEK 3: POLISH, DEPLOY, LAUNCH (Days 11-15)

**Goal:** Production launch with monitoring, rollback ready, docs complete.

| Day | Focus | Owner Agents |
|-----|-------|--------------|
| 11 | Bug bash: triage all open issues, fix P0/P1 | All agents (UI, Testing, Optimization) |
| 12 | **INTEGRATION POINT 2**: Release candidate build | Deployment + Testing (smoke tests) |
| 13 | Beta release to internal testers, gather feedback | Deployment + UI/UX (rapid iterations) |
| 14 | Final bug fixes, App Store / Play Store submission | Deployment + Documentation (release notes) |
| 15 | **PRODUCTION LAUNCH** + monitoring | All agents (incident response standby) |

**Week 3 Exit Criteria (LAUNCH — Day 15 EOD):**
- App available on Web, Play Store (open testing track), TestFlight
- Monitoring dashboards live (crash-free rate >99%, p95 latency tracked)
- Rollback playbook tested
- All documentation published

---

## 3. TASK DEPENDENCIES MATRIX

| Task | Depends On | Blocks |
|------|-----------|--------|
| Service signature freeze | Service audit complete (Day 1) | UI binding, integration tests |
| Design system locked | Brand tokens approved | All UI screens, golden tests |
| CI pipeline running | GitHub repo permissions | All automated tests, deployments |
| Firebase env config | Credential audit | Staging deploys, integration tests |
| Integration test harness | Service freeze + UI shell | Beta release gating |
| App Store provisioning | Apple Developer account active | iOS TestFlight + production |
| Play Store signing | Keystore generated + secured | Android release tracks |
| Crashlytics integration | Firebase env config | Production monitoring |

---

## 4. DAILY STANDUP TEMPLATE

```
DATE: YYYY-MM-DD | DAY: X of 15 | WEEK: X

== AGENT REPORTS ==

[UI/UX Agent]
  Yesterday:
  Today:
  Blockers:
  Coverage delta: +X screens | total: X/Y

[Testing Agent]
  Yesterday:
  Today:
  Blockers:
  Coverage delta: +X% | total: XX.X% | target: 80%

[Service Optimization Agent]
  Yesterday:
  Today:
  Blockers:
  Optimizations merged: X/47 | P0: X/X | P1: X/X | P2: X/X

[Documentation Agent]
  Yesterday:
  Today:
  Blockers:
  Pages complete: X/Y

[Deployment Agent]
  Yesterday:
  Today:
  Blockers:
  Pipeline status: green | yellow | red

== ORCHESTRATOR NOTES ==

Critical path status: ON TRACK | AT RISK | BLOCKED
Decisions needed:
Cross-agent handoffs scheduled:
Risks surfaced:
```

---

## 5. RISK REGISTER & MITIGATION

| Risk | Probability | Impact | Mitigation | Owner |
|------|------------|--------|------------|-------|
| Sarvam AI rate limits hit during testing | High | Medium | Mock service in tests, request quota increase Day 1 | Service Opt + Testing |
| Apple Developer account not provisioned | Medium | High | Verify Day 1, escalate if not active by Day 3 | Deployment |
| Service signature changes break UI mid-week | Medium | High | Hard freeze Day 5, contract tests, semver discipline | Orchestrator |
| Test coverage stalls below 80% | Medium | High | Coverage gate in CI from Day 5, daily delta tracking | Testing |
| Gemini API cost overruns | Low | Medium | Token budget per request, daily cost dashboard | Service Opt |
| Flutter web performance issues | Medium | Medium | Lighthouse benchmarks Day 7, perf budget enforced | UI/UX + Optimization |
| Localization assets late | Low | Low | English-only acceptable for v1 launch, ship others as patch | UI/UX |
| Credential leak in CI logs | Low | Critical | Secret scanning, masked variables, audit Day 1 | Deployment |
| Firebase quota exhaustion in staging | Low | Medium | Alerts at 70%, separate billing alert at 80% | Deployment |
| Single agent becomes bottleneck | Medium | High | Daily standup surfaces blockers, orchestrator reroutes work | Orchestrator |

---

## 6. SUCCESS METRICS PER WORKSTREAM

### UI/UX Agent
- Screens delivered: 12+ (home, news list, detail, player, settings, onboarding x3, profile, library, search, error states)
- Accessibility: WCAG 2.1 AA on all screens
- Lighthouse score (web): >90 performance, >95 accessibility
- Animation frame budget: 60fps on mid-tier Android

### Testing Agent
- Unit test coverage: >85% on services, >75% on view models
- Widget test coverage: 100% of design system atoms, >80% of screens
- Integration tests: full happy path + 5 error paths
- Golden tests: every screen, light + dark mode

### Service Optimization Agent
- All 47 optimizations triaged; 100% of P0 + P1 merged
- API cost reduction: >30% via caching + batching
- p95 latency: OCR <3s, summarization <5s, TTS <4s
- Memory: <150MB steady state on Android

### Documentation Agent
- API reference: 100% of public methods documented
- Setup guide reproducible from clean machine in <30 min
- Architecture diagrams: service layer, data flow, deployment topology
- Onboarding doc validated by external reviewer

### Deployment Agent
- CI build time: <8 min for PR validation
- Staging deploy: automated on every main merge
- Production deploy: one-click with manual approval
- Rollback time: <5 min to previous version
- Crash-free sessions: >99% at launch

---

## 7. RESOURCE ALLOCATION & PARALLEL OPPORTUNITIES

### Maximum Parallelism Windows
- **Days 1-4:** All 5 agents work fully independently (only dependency is service freeze on Day 5)
- **Days 6-9:** UI + Testing must coordinate on widget contracts; Optimization + Docs work independently
- **Days 11-12:** Bug bash mode — all agents triage and fix in shared queue

### Sequential Bottlenecks (UNAVOIDABLE)
1. **Service signature freeze (Day 5)** — gates UI integration AND integration tests
2. **Integration Point 1 (Day 7)** — gates beta-readiness assessment
3. **Integration Point 2 (Day 12)** — gates production submission
4. **App Store review (post Day 15)** — out of our control, plan for 1-3 day wait

### Recommended Coordination Cadence
- **Daily 15-min standup:** All agents, orchestrator-led, async-friendly
- **Twice-weekly integration sync (Tue/Fri):** UI + Testing + Optimization deep dive
- **Weekly retro (end of Week 1, 2):** Adjust plan based on velocity

---

## 8. HANDOFF PROTOCOLS

| Handoff | From -> To | Trigger | Artifact |
|---------|------------|---------|----------|
| Service contract | Optimization -> UI | Day 5 freeze | Frozen interface doc + Dart abstract classes |
| Screen-ready signal | UI -> Testing | Per screen completion | PR merged + screenshot in PR description |
| Test coverage report | Testing -> Orchestrator | Daily | CI artifact, coverage delta in standup |
| Optimization rollout | Optimization -> Deployment | Per P0/P1 merge | Performance benchmark before/after |
| Doc publishing | Documentation -> Deployment | Day 14 | Static site deployment trigger |
| Release candidate | Deployment -> All agents | Day 12 | Tagged build, smoke test checklist |

---

## 9. IMMEDIATE NEXT ACTIONS (DAY 1)

1. **Orchestrator:** Confirm all agent contexts loaded, distribute this plan, schedule Day 1 standup
2. **UI/UX:** Begin design tokens, deliver Figma/spec by EOD
3. **Testing:** Spin up `flutter test` infra, write first FirebaseService mock
4. **Service Opt:** Publish 47-item triage spreadsheet, get P0 list approved
5. **Documentation:** Scaffold docs site, audit existing inline docs
6. **Deployment:** Verify GitHub Actions enabled, audit secret storage, confirm Apple/Play accounts

---

## 10. KEY BOTTLENECKS IDENTIFIED

1. **Service signature freeze on Day 5** — Highest leverage point. If this slips, entire Week 2 cascades. Mitigation: orchestrator gates this with explicit go/no-go.
2. **Apple Developer account provisioning** — External dependency, can take days. Verify Day 1, no exceptions.
3. **Test coverage ramp** — Coverage often stalls late. Mitigation: daily delta tracking, gate PRs at 75% from Day 7, 80% from Day 10.
4. **App Store review queue** — 1-3 days outside our control. Submit by Day 12 to leave buffer for Day 15 launch.
5. **Sarvam AI quotas** — Could throttle integration testing. Request capacity increase Day 1.

---

**Plan owner:** Orchestration Agent
**Plan version:** 1.0
**Created:** 2026-05-11
**Next review:** Day 5 (Week 1 checkpoint)
