# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Ripple — a voice-first, minimal-UI grounding companion app for people in early-stage dementia (iOS, SwiftUI + SwiftData). Full product rationale lives in `Docs/grounding-companion-build-plan.md` and `Docs/grounding-companion-interaction-design.md` — read these before making product-level changes; they explain *why*, not just *what*.

## Build / run / test

There is no Xcode project, workspace, or `Package.swift` checked into this repo — it is currently a loose collection of `.swift` sources plus `Assets.xcassets`. There is no lint config and no test target. To actually build or run the app, the files need to be added to (or the repo turned into) an Xcode project targeting iOS 26+, iPhone 15 Pro and later (Apple Intelligence / `FoundationModels` requires this). Don't assume `xcodebuild`/`swift test` commands work until that project exists — check for one before relying on it.

## The one rule the whole codebase follows

**Deterministic Swift code decides what is true and when to act. A language model, when available, only decides how to phrase it.** The most sensitive lines (distress, "am I safe", night-mode reassurance, "say that again") skip the model entirely and are spoken verbatim. Every architectural decision below exists to preserve this rule — when adding a feature, decide up front which side of the line it's on before writing code.

## Architecture

**Store (`Models.swift`, SwiftData).** Source of truth: `Person`, `Event` (a single bidirectional timeline — past entries are memories, future entries are upcoming plans; there is no separate "task" or "agenda" model), `Conversation`, `ComfortTopic`, `GroundingFacts` (the highest-stakes record — `isComplete` must hold because night-mode/distress paths read it directly with no fallback). Every model carries `lastModified` for future sync.

**Two model-facing engines, split by direction, both degrading gracefully to deterministic behavior when Apple Intelligence is unavailable (`canImport(FoundationModels)` + `#available(iOS 26, *)` + `SystemLanguageModel.default.availability`):**
- `ComprehensionEngine` faces inward: turns an utterance into a `QueryIntent` (routing only, via `@Generable` constrained decoding) or extracts a `ConversationBeat` (topics/people/tone) from conversation turns. Nothing it returns is ever spoken directly — a hallucinated name/topic just fails to match the store and is dropped.
- `PhrasingEngine` faces outward: takes an already-true line built by `GroundingService` and warms its tone. Never introduces facts; on any failure/timeout it returns the original line unchanged.

`PhrasingEngine.converse` is the one deliberate exception to "never introduces facts", reached only for `.unclear` — something no record answers, like "I'm hungry, can you help." Meeting that with a fixed line about the garden is its own harm, so the model composes a reply. It may only *acknowledge and offer*: `EmpatheticReply` splits the output into one sentence naming the feeling and one question offering to talk, so there is structurally nowhere to put a claim.

`converse` serves two intents, both of which have no factual answer: `.unclear` and `.feeling`. `.feeling` exists because every other intent is a *question* — without it the classifier had to force "I feel really sad today" into the nearest one and answered it with "Maya is here at three o'clock". When adding an intent, check whether it is answering something that was never asked.

It is told the person's words and **nothing else** — no name, no place, no one on duty. An earlier version passed the on-duty caregiver so it could point to them for help; the model turned "on duty" into "Sarah is here with you," asserting a presence the store never claimed. Context it cannot verify is context it will assert. `vetted` then rejects any reply containing a known name (every `Person.name` plus the caregiver and primary contact are passed in — questions about people have a grounded path, so a name here is always unearned), any digit (no clock or calendar backs this reply, so a number is invented), or anything over 240 characters. Rejected replies fall back to `GroundingService.unsure`, which is true. Don't widen what it is told, and don't route a store-answerable question through it.

`QueryInterpreter` is the deterministic first pass at understanding a question (pattern matching, zero latency) — `ComprehensionEngine` is only consulted when it returns `nil`. Model calls are the fallback path, not the primary one.

`GroundingService` is pure, deterministic, model-free: it builds every spoken/displayed sentence from store records (`GroundingDigest` is the bounded window of facts/events handed to the model as prompt context — never let the model fetch its own data).

`CompanionSession` is the one object that owns a live conversation turn (mic → comprehension → grounding → phrasing → speech, in that explicit order, half-duplex) — see its file header for why this must not be split across objects. On close it folds the conversation into a deterministic `ConversationDigest` (never re-summarized prose) and writes one `Event` recap.

`SpeechManager` / `ListeningService` / `AudioSessionCoordinator` handle the audio session, TTS priority queue (`.grounding` preempts everything, `.reply`/`.ambient` queue), and speech-to-text respectively. Speaking and listening are mutually exclusive (half-duplex) — listening pauses while the companion talks, both to avoid feedback and because `AudioSessionCoordinator` is the single place that owns session category switches.

`RippleServices` is the app-wide DI container (`speech`, `phrasing`, `comprehension`, `session`), injected once via `.environment(services)` at the root and re-injected explicitly into sheets (SwiftUI sheets build outside the parent view tree, so environment values don't automatically flow in).

## Conventions worth preserving

- New `@Generable` model outputs go behind both `canImport(FoundationModels)` and `#available(iOS 26, *)`, with a deterministic fallback — follow the existing pattern in `ComprehensionEngine`/`PhrasingEngine` rather than adding a new capability-check style.
- Anything derived from user speech/model output that could name a person or topic must be validated against the store before use (see `resolve(_:people:)` and `mergeTopic` for the pattern) — a model string is a lookup key, never content to store or speak.
- `EventSource`/completion tracking distinguishes conversation-derived, caregiver-authored, and confirmation-tap events, but this distinction is caregiver-facing only and must never surface to the person (dignity note in the interaction-design doc).
