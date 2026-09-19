# Grounding Companion — Interaction Design

*Daytime paths and night mode (sundowning)*

---

## Core principle

The app keeps the person oriented in **what's true right now**, delivered warmly. It never sources facts about the person's life — every fact is either caregiver-approved or read back from the confirmation log. **The model phrases; it does not invent.**

---

## Shared foundation

Both modes run off one store and one rule.

**The store**
- Routine & tasks (caregiver-authored, ordered steps)
- Daily log — what the person has done today (from their own "done" taps)
- People — name, relationship, photo, one line of recent context
- Grounding facts — home name/place, current caregiver, primary contact
- Approved reassurances — a small set of caregiver-written calming lines

**The rule:** task steps and reassurances are caregiver-authored templates. The model only paces, phrases, and picks the right moment. It does not generate procedures, medical content, or new facts.

---

## Daytime paths

### 1. Time orientation (ambient)

Three directions, same store:

- **Forward** — what's coming: *"Your daughter Maya visits at 3 o'clock."*
- **Present** — what's now, or nothing: *"It's 2 o'clock. Nothing's needed right now — you had lunch about an hour ago."*
- **Backward** — what's done (the peace-of-mind engine): *"You've already had breakfast and taken your walk today."*

The backward view is what breaks the anxious "did I / didn't I" loop. It is 100% reliable because it only reads the log back in warm language.

### 2. Task tracking

- Caregiver writes an ordered step list once (e.g., "Make coffee").
- App surfaces **one step at a time**, and answers *"what's next," "say that again," "I'm stuck."*
- The model adjusts warmth and detail; it never improvises the procedure.

**Confirmation logging:** the person taps "Done" → logged with a timestamp → available to the backward view and to the caregiver.
> Framing boundary: this records *that they tapped done*, not that the stove is physically off. Present it as a memory record, never a safety guarantee. (Smart-home state via HomeKit is the reliable upgrade — later.)

### 3. Reflection & gentle conversation

- Reads the day's log back as reassurance.
- Opens a soft thread from what was done — *"You were out in the garden this morning. How did it look?"* — rather than testing recall with *"What did you do today?"*

### 4. Visitor cards (small piece)

Who's coming / who's been: name, relationship, photo, one line of context (*"Your son David — visited last Sunday"*). Reuses the people store. No live face recognition in v1.

---

## Night mode (sundowning)

**When it's active:** an evening window the caregiver sets, or the person opening the app at night.

**Different rules from daytime.** Repeatedly correcting or reasoning with someone who is sundowning tends to backfire; reassurance, one gentle grounding cue, and redirection work better. So night mode is calm, minimal, and does **not** argue.

### The grounding card

High-contrast, large text, one screen:

```
You are at home, Margaret.

It is nighttime — about 9 o'clock.

You are safe. Everything is okay.

        [ Call David ]
```

Three fields, all from the store: **place** · **time** · **who to call**. Plus one approved reassurance line.

### The three behavioral rules

1. **Reassure first, ground second.** Warmth ("You're safe, I'm right here") comes before any fact ("it's nighttime"). Never lead with the correction.
2. **Offer once — don't argue.** If the person doesn't accept the grounding, do **not** repeat or insist. Switch to a calming option (a familiar photo, soft music) and keep the call button visible.
3. **Escalate to a person, not more words.** When distress continues, the answer is a one-tap call to the caregiver — not more conversation.

### Guardrail

At night the model draws **only** from caregiver-approved reassurances and the person's grounding facts. No free generation. A creative model improvising with a frightened, disoriented person is the exact risk to design out.

---

## Caregiver updates & controls

This is where the app's **self-improving** principle actually lives — not model retraining, but the caregiver keeping the person's world current. The store is meant to change over time, and both what's *in* it and what's marked *done* can come from the caregiver as well as the person.

### Updating the store over time

From a caregiver view (their own device, synced to the person's phone), they can:

- **Edit routine & task templates** — reorder or reword steps, change timing, retire tasks that no longer fit.
- **Manage people** — add an upcoming visitor, refresh a photo, update the one-line context (*"David — visited last Sunday"*).
- **Update grounding facts** — home/place and, especially, the current on-call contact.
- **Add approved reassurances** — when the caregiver learns a line that reliably calms the person, they add it to the night-mode set.

Keep it low-friction: caregivers are stretched, so favor quick-add and gentle prompts (*"David just visited — add a note?"*) over long forms. The store getting richer and more accurate over time *is* the personalization.

> Critical-field guardrail: **place** and **who-to-call** must be validated as always-present, because night mode reads them directly. Never let the highest-stakes screen fall back to empty or stale values (e.g., an on-call contact who has changed).

### Shared completion (caregiver can mark done too)

Completion can come from **either the person or the caregiver**, and both write to the same daily log — because the caregiver often does the task *with* or *for* the person, or simply knows it happened.

- The caregiver can mark a task done from their device (*"I helped her dress," "she took her walk"*).
- The log records the source internally (self-tapped vs. caregiver-marked) for the caregiver's own clarity. This distinction is **not** surfaced to the person.
- If both mark the same task, dedupe.

Why this matters for **reliability**: the backward-looking "what you've done today" reflection is only as good as the log. If the person forgets to tap, the reassurance would wrongly imply nothing's been done. Caregiver marking keeps that view true — so *"you've already had breakfast"* stays accurate and calming even on a day the person didn't self-report.

> Dignity note: surface caregiver-marked items exactly the same gentle way as self-marked ones (*"you had breakfast this morning"*) — never in a way that feels like the person is being watched or checked up on.

---

## Deliberately out of scope (v1)

- **Medication logic** — no dosing, no double-dose prevention.
- **Free-form night chat** — no open-ended model conversation during a sundown episode.
- **Safety guarantees** — a confirmation tap is a memory record, not proof the physical action happened.

---

## One-line summary

Daytime, it gives structure and peace of mind. At night, it gives place, time, and a person to call — calmly, once, without arguing.
