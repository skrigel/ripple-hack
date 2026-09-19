# Grounding Companion — iOS Build Plan

*A voice-first, minimal-UI grounding app for early-stage dementia, built on Apple's on-device stack.*

---

## The product in one line

The person picks up their phone when they're unsure; the app immediately tells them where they are, what time it is, and what's happening — warmly, out loud — and offers a few big buttons for help. A caregiver keeps it current.

---

## The one rule that keeps it reliable

**Deterministic code decides *what's true* and *when to act*. The model only decides *how to say it*. The most sensitive lines skip the model entirely.**

Everything below follows from this.

---

## Architecture: five layers

**1. Store (SwiftData) — the source of truth.** Fully on-device, private, offline. Entities: `Person`, `Task`→`Step`, `LogEntry`, `GroundingFacts`, `Reassurance`. Every record is sync-ready (UUID + `lastModified` + `source`) so remote sync is a later add, not a rewrite.

**2. Scheduler — the "when" (plain Swift, no model).** Watches the clock and store; emits typed intents: `.presentOrientation`, `.startTask(id)`, `.reflectOnDay`, `.sundownGrounding`. Drives local notifications. Testable, deterministic — this is why the app can be trusted.

**3. Phrasing — the "how" (Foundation Models).** The *only* place the LLM lives. Turns an intent + injected facts into a short spoken line. Skipped for verbatim content.

**4. Presentation — voice-first (AVSpeechSynthesizer + minimal SwiftUI).** Spoken line is primary; screen mirrors it in large text plus 2–3 huge buttons.

**5. Caregiver mode — PIN-gated editing + shared completion.** Writes to the same store.

---

## Two entry paths (the UX spine)

A personal phone can't speak from the background, so the app is reactive, with two ways in:

**A. On-demand (primary).** Person opens the app → it speaks the present orientation *instantly* and shows the home screen. Opening the app *means* "help me."
- Requirement: the open moment must be instant. The present-orientation line is **precomputed and templated**, refreshed on a timer and on `foreground`. No model call, no spinner.
- The model may enrich *after* the instant line, never before it.

**B. Scheduled nudges.** `UserNotifications` fires at routine times and in the sundown window. Notification (text) → user taps → app foregrounds → speaks the relevant flow.

> Design honestly around the constraint: notifications are the proactive channel; **voice happens only when the app is in the foreground.** Don't rely on "Announce Notifications" — it's outside your control.

---

## The home screen (minimal, on-demand help)

On open, the app speaks the present grounding and shows a small, fixed set of large targets. Recommended starting set (tune with a real user):

- **"What's happening now?"** — re-speak / expand present orientation.
- **"Help me do something"** — task list → pick → step-by-step pacing.
- **"I'm not sure"** — calm grounding (place, time, "you're safe") + call button.
- **"Say that again"** — replays the last spoken string. No model, instant, 100% reliable.
- A persistent **Call [Caregiver]** affordance.

Never show more than ~3 primary buttons at once. The screen is a calm anchor, not a dashboard.

---

## The LLM integration pattern

**a. Structured output whose payload is a spoken sentence.**
```swift
@Generable
struct SpokenResponse {
    @Guide(description: "One or two warm, short sentences to speak aloud")
    let speech: String
    let showCallButton: Bool
}
```
Feed `speech` to both the synthesizer and the on-screen label — one string, two channels. Constrained decoding guarantees you get a clean, well-formed result.

**b. Template-first gradient.** The more sensitive the moment, the less the model is involved:
- *Verbatim, no model:* night-mode reassurances, task steps, "say that again," the instant open line.
- *Model-for-tone:* time orientation, day reflection — rephrase known facts warmly.
- *Model-with-light-reasoning:* pick the fitting reassurance; open a gentle thread from the log.

**c. Inject facts, don't let the model fetch them.** Retrieve the needed facts in code and put them in the prompt. Reserve tool calling for later.

**d. Graceful degradation.** Foundation Models needs an Apple-Intelligence device (iPhone 15 Pro+, iOS 26+). Check `SystemLanguageModel` availability at launch; if unavailable, **run templates-only** so the app still fully works.

**e. Responsiveness.** Precompute the open line; prewarm the session on foreground; stream responses so speech starts on the first sentence.

---

## Data model sketch

```
Person        { id, name, relationship, photo, recentContext, lastModified }
Task          { id, title, steps:[Step], scheduleHint, lastModified }
Step          { id, order, text }
LogEntry      { id, taskRef?, label, timestamp, source(self|caregiver), lastModified }
GroundingFacts{ homeLabel, primaryContactName, primaryContactPhone, lastModified }  // night mode reads these
Reassurance   { id, text, lastModified }  // caregiver-approved, verbatim
```
Critical-field rule: `GroundingFacts.homeLabel`, `primaryContactName`, and `primaryContactPhone` must be validated non-empty — night mode depends on them directly.

---

## Caregiver mode (v1: same device)

- PIN-gated section inside the same app.
- Edit routines/tasks, people, grounding facts, and approved reassurances.
- **Shared completion:** caregiver can mark tasks done (writes `LogEntry` with `source = caregiver`); source is internal, never surfaced to the person; dedupe if both mark.
- Validate critical fields on save; confirm changes to the on-call contact.
- **Deferred to v1.1:** remote companion app, remote editing/marking, adherence signals — enabled by the sync-ready records.

---

## Voice & accessibility (this *is* the design)

- Slow speech rate, warm high-quality/enhanced voice (consider Personal Voice later).
- Screen mirrors the spoken line in large Dynamic Type; WCAG-AA+ contrast; generous tap targets; minimal motion.
- "Say that again" always available.

---

## Apple frameworks

| Need | Framework |
|---|---|
| Local store | SwiftData |
| On-device LLM | FoundationModels |
| Speech output | AVFoundation / AVSpeechSynthesizer |
| Scheduled nudges | UserNotifications |
| Call caregiver | `tel://` via UIApplication (or CallKit) |
| UI | SwiftUI |
| Voice input (optional, later) | Speech |

Target: iOS 26+, iPhone 15 Pro and later (Apple Intelligence required for the model; templates-only fallback otherwise).

---

## Phased build plan

- **Phase 0 — Spike the loop.** Prove: intent → `@Generable SpokenResponse` → spoken by AVSpeechSynthesizer → mirrored on a bare screen. If this feels good, the app will.
- **Phase 1 — On-demand heartbeat.** Store + instant precomputed present-orientation on open + the minimal home screen with buttons. This is the MVP.
- **Phase 2 — Task tracking.** Step pacing, confirmation taps, log writes, backward "what you've done" reflection.
- **Phase 3 — Night mode.** Grounding card, three behavioral rules, call button — mostly templated.
- **Phase 4 — Scheduled nudges.** `UserNotifications` for routine times + sundown window; tap-to-open routing.
- **Phase 5 — Caregiver mode.** PIN editing, shared completion, critical-field validation.
- **Phase 6 — Polish.** Voice tuning, prewarm/stream latency, accessibility pass, field test with a real user.
- **Later:** remote sync, visitor cards, optional voice input, HomeKit for real device-state confirmations.

---

## v1 cut line

**In:** on-demand grounding, task tracking with confirmation + reflection, night mode, scheduled nudges, same-device caregiver mode, templates-only fallback.

**Out:** remote sync, medication logic, free-form night chat, voice input, face recognition, safety guarantees on confirmations.
