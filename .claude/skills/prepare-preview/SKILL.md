---
name: "prepare-preview"
description: "An instrument for reaching a design decision together and keeping it: turns a topic discussed in conversation into two artifacts in one folder — a detailed editable SOLUTION working-doc and a short team PREVIEW brief (.md + a colored PDF with 🟢🟡🔴 markers and mermaid diagrams, via headless Chrome). The input is a topic description plus the details given in the discussion — NEVER a ticket id; there is no tracker in this project. The conversation is a primary source alongside the project's own docs (docs/research, docs/protocol, docs/design/spec, the open-questions register) and the repo, and the documents must hold the whole context so a cold reader sees what was decided, what was rejected and what is still open without the chat history. Built for NOX's current phase, where there is no implementation yet: it describes top-level parts, how they talk, formats and contracts, decisions with their alternatives, corner cases and open questions — and deliberately produces NO file-by-file change maps, code, or document-level status apparatus. UPDATE is the normal working mode as the discussion moves on; it amends and never silently drops what was already recorded, and reconciles resolved questions back into the register."
user-invocable: true
disable-model-invocation: false
---

## Purpose (explain this to the user when invoked)

Prepares, per topic, **two artifacts in one folder**:

1. **`<slug>-solution.md`** — the detailed, editable **working document**: the full picture of the solution, part
   by part, with contracts/formats, decisions and rejected alternatives, corner cases and open questions. This is
   the doc the owner edits across rounds and later feeds into Spec Kit or a protocol spec.
2. **`<slug>-preview.md` + `<slug>-preview.pdf`** — a SHORT **team brief** derived from it: the top-level map,
   diagrams, decisions and blockers, readable in ~5 minutes. The PDF is rendered by headless Chrome and is what
   gets presented.

Two modes:

- **FRESH** — first pass: build the picture from the conversation + project docs + repo, write both artifacts.
- **UPDATE** — the normal working mode. The owner reviewed, or the discussion moved on ("do it this way instead",
  "this part is wrong", "we decided X"): apply it to the EXISTING documents, re-verify anything it touches,
  rewrite both, regenerate the PDF, and report exactly what changed.

## What this skill is FOR

**It is an instrument for reaching a decision together, not a spec and not a task card.** The cycle is: discuss →
write down what was agreed → the owner reads it and pushes back → update → discuss again. The documents are the
place where the agreement accumulates, so that the next round starts from what was settled instead of
re-deriving it.

Three consequences that govern everything below:

1. **The input is never a ticket.** There is no tracker in this project and none should be assumed. The input is
   a description of the topic plus whatever key details the owner gave in the conversation. Do not ask for a
   ticket id, do not name the documents after one, do not leave ticket-shaped fields in them.
2. **The conversation is a primary source, on a par with the project's documents.** A decision the owner stated
   in chat is a fact, and it is usually the freshest fact available — the docs may not have caught up yet. Record
   it with its date and attribute it («решение владельца, <дата>»). Never quietly re-open something already
   agreed, and never re-ask a question the conversation already answered.
3. **The documents must hold the whole context.** They are the durable memory of a discussion that will span many
   sessions. Anyone picking them up cold — the owner in a month, a teammate, a future session — must be able to
   see what was decided, what was rejected and why, and what is still open, without reading the chat history.

**Phase rule — this is a design skill, not a change-planning skill.** NOX currently has no implementation of the
backend, protocol or transport. Therefore this skill MUST NOT produce: a file-by-file change map, "which files
will be edited", code snippets of the future implementation, migration plans, or test plans for code that does not
exist. It describes **the solution**: what the parts are, what each is responsible for, how they talk, what
travels between them, what was decided and why, and what is still open. If the owner later wants an
implementation plan, that is Spec Kit's job (`/speckit-specify` → `plan` → `tasks`), and this document is its input.

When invoked, show a short intro:

> Соберу preview по теме: детальный solution-документ (рабочая база) + короткий team-бриф (.md + цветной PDF с
> диаграммами). Источники — документы проекта (`docs/research/`, `docs/protocol/`, `docs/design/spec/`, реестр
> открытых вопросов) и репозиторий. Скажи тему; если по ней уже есть документы — применю правки (update), иначе
> соберу с нуля (fresh). Сначала прочитаю релевантные доки и задам уточняющие вопросы.

## Step 0 — Input & mode

Take the topic from the invocation (`/prepare-preview client-backend-connect`) — a short kebab-case **slug**
describing the subject, never a ticket id. If none was given, ask what the preview is about and agree a slug.
Capture any edit request or newly agreed decision given alongside.

Skim this skill's `assets/`: `solution-template.md`, `preview-template.md`, and the PDF recipe
(`head.html` / `tail.html` / `render-pdf.sh`).

**Detect the mode.** Look for existing `<slug>-solution.md` / `<slug>-preview.md` (check `docs/preview/` first,
then ask). Found → **UPDATE** (confirm: «нашёл существующие документы по <slug> — применяю правки, не пересобираю
с нуля?»). Otherwise → **FRESH**.

## Step 1 — Source preflight (read before writing)

**The conversation and the project's own documents are the primary sources**, the repo is the second, and the web
is optional. Where they disagree, the conversation is the most recent and usually wins — but say so in the
document rather than silently overriding a written decision. Report what you actually read, ✅ / ⚠️ / ❌ — and if
something the topic depends on does not exist yet, say so instead of inventing it.

Read whatever the topic touches:

- **`docs/research/`** — `summary.md` (state of play), `client-backend-deployment.md`, `snikket-fit.md`, and
  **`open-questions.md`** (the register — always read it; a preview must not contradict or silently re-decide an
  open question).
- **`docs/protocol/`** — `wire-surface.md` and anything else already agreed there.
- **`docs/design/spec/`** — the authoritative UI/UX corpus, when the topic touches product behaviour;
  `docs/blueprints/mobile/` when it touches client architecture.
- **The repo** — to ground any claim about how the app behaves today. Verify, never assume; cite `path:line` in
  the solution doc when a claim rests on code.
- **`.specify/memory/constitution.md`** — when the topic touches a principle (platform parity, language
  discipline, the phase working mode).
- **Web** — only if the owner asked for external precedent, or a claim genuinely needs a primary source. Load
  WebSearch/WebFetch via ToolSearch. Never cite a URL you did not fetch.

**Core principle — never guess.** If a fact needed for the picture is missing, name the gap in the document as an
open question. A confident diagram built on a guess is worse than an honest hole.

In UPDATE mode, re-read at least what the requested edits touch, plus the register.

## Step 2 — Build the picture → write `<slug>-solution.md`

Work out the solution at the level of **parts and their interactions**, not files. **Do not write any file yet —
the save location is a mandatory ask (Step 5): resolve it first.**

The spine of the analysis, in this order:

1. **Parts.** What components exist in this topic, and what is each one responsible for. One line each. Include
   parts that already exist in the repo and parts that do not exist yet — mark which is which.
2. **Interactions.** Who talks to whom, in which direction, over what. This is where the diagrams come from.
3. **What travels.** The concrete contracts: payload shapes, link/QR formats, command and event names, field
   sizes. Be specific — «токен» is useless, «16 байт, одноразовый, TTL 15 минут» is a design.
4. **Decisions.** Every fork you resolved, with the alternatives and the reason. Anything you could not resolve
   goes to open questions instead of being quietly decided.
5. **Corner cases.** What happens when it fails, when it is retried, when the user does the unexpected, when the
   network/machine/address changes. This section is what makes the document worth reading twice.
6. **Scope boundary.** What this topic explicitly does not cover, and where that lives instead.

In UPDATE mode, read the existing solution doc as the base and apply the edits surgically.

**Nothing already recorded may quietly disappear.** An update adds and amends; it does not silently drop.

- A decision that no longer holds is **marked as revised** with the date and the reason, not deleted — the reader
  needs to know it was considered and why it changed.
- An open question that got answered moves to a decision **and** is marked resolved in the register (Step 7); it
  does not just vanish from the table.
- A corner case that turned out to be a non-issue says so; an unexplained absence reads as an oversight.
- Every round appends a changelog entry: what changed and why.

This is what makes the document worth returning to. If an update makes it shorter by forgetting things, the skill
has failed at its main job.

## Step 3 — Clarifying interview (ASK, don't assume — use AskUserQuestion)

Ask only what is genuinely open **and** would change the document. Do not ask what the register or the docs
already answer — fold those in as stated assumptions with a link.

Typical for this project:

- A fork the analysis surfaced that only the owner can settle (a trade-off between anonymity, simplicity and
  reach almost always appears).
- The scope boundary, when the topic could reasonably be drawn wider or narrower.
- Which audience the preview is for, if that changes the depth.

**Do not** ask a generic architectural-pattern question — this project has its blueprint and constitution; consult
them instead of interviewing.

## Step 4 — Derive the preview brief (.md)

Summarize the solution into `assets/preview-template.md` → `<slug>-preview.md`.

- **~5-minute read.** Tables and diagrams over prose. The solution doc holds the depth.
- **Diagrams are required, not decorative.** At least two: one **component/relationship** view (who the parts are
  and how they connect) and one **flow or sequence** view (the main path end to end). Add a state diagram when
  lifecycle matters. Keep each readable on one page — if a diagram needs more than ~10 nodes, split it.
- **Do not list absent connections in the brief.** Naming what does NOT connect to what belongs in the solution
  doc (§3), where there is room to explain it. In a 5-minute brief a list of negatives reads as noise — the
  diagram already says what connects. Make the diagram unambiguous instead.
- **Cut supporting evidence from the brief.** Which other projects reached the same conclusion, which sources
  back a claim — that is the solution doc's job. The brief states the conclusion and moves on.
- **Markers:** 🟢 · 🟡 · 🔴 · ⚠️ — used **inside** the content, where they carry meaning: what exists versus what
  does not, what is decided versus open, which corner case is unresolved.
- **No document-level status apparatus.** Do NOT write a status badge, a readiness state, a risk rating, an
  estimate, a «Границы» line, a mode field or a «Что это»-style meta preamble. These are leftovers from
  ticket-tracking and they make a design document read like a task card. The document describes **how the thing
  works**; what is unresolved belongs in the open-questions section, which says it better.
- **The brief ends on the open questions.** No out-of-scope section either — that, like the absent connections and
  the supporting evidence, is negative space: it tells the reader what the document is *not* about, which is the
  solution doc's job (§8 there). A five-minute brief should close on what someone has to decide, not on a list of
  things nobody was going to find here anyway.
- **The «Открытые вопросы и блокеры» section is REQUIRED** — 🔴 blocker · 🟡 open question · 🟢 accepted assumption.
  Cross-reference the register by question id (Q1, Q7…) where one exists.
- **No file-by-file map, no code.** If a repo file genuinely matters (e.g. «этот механизм уже есть в
  `lib/general/nox_qr_envelope.dart`»), name it in full repo-relative form and say why it matters — but never turn
  the document into a change list.
- Russian prose; code identifiers, paths, command names and formats verbatim in English.

## Step 5 — Save location

**FRESH: ask via AskUserQuestion and WAIT for an answer BEFORE writing ANY file.**

> Куда положить документы по <slug> (solution + preview + pdf, в одну папку)? Дефолт — `docs/preview/<slug>/`
> (трекается в git, потому что бриф идёт команде). Для локального черновика назови нетрекаемую папку.

**UPDATE: write back to the folder the documents already live in, without asking.** Re-asking on every review
round is friction with no upside — the owner is iterating in place. Ask only if they requested a copy elsewhere.

All three artifacts go in the SAME folder.

## Step 6 — Generate the PDF (headless Chrome)

```bash
bash .claude/skills/prepare-preview/assets/render-pdf.sh "<folder>/<slug>-preview.md" "<folder>/<slug>-preview.pdf"
```

Colored markers and mermaid render; needs network for the CDN on first run. The script leaves only `.md` + `.pdf`.
If it reports FAILED, surface the reason — never claim a PDF exists when it does not.

**Check the diagrams actually rendered.** A mermaid syntax error silently produces an empty block in the PDF. If
in doubt, open the PDF or re-render after simplifying the diagram.

## Step 7 — Reconcile the register, then summarize

1. **Update `docs/research/open-questions.md`** when this round resolved or created questions: a decision taken →
   mark the question solved with the date and the reason; a new fork surfaced → add it. This is what keeps the
   docs operable across rounds instead of drifting into a pile of one-off briefs.
2. Report the folder and the three files, plus the open questions the team must resolve. In UPDATE mode, list
   exactly what changed.
3. Note that the solution doc is the input for Spec Kit (`/speckit-specify`) or a protocol spec when the topic is
   ready to be built.
4. Do not commit unless asked.

## Quality bar

- **Nothing invented.** Every claim traces to a project document, to the repo (with a path), or to a fetched
  source — or is flagged as an open question. Formats and sizes are concrete, not gestures.
- **The preview explains the solution, not the code.** No file lists, no snippets, no migration or test plans for
  things that do not exist.
- **Diagrams carry real information** — the parts, the direction of the arrows and what travels on them. A diagram
  that only repeats the headings is noise; cut it.
- **Decisions are explicit and reversible on paper**: what was chosen, what was rejected, why, and what would have
  to change to revisit it.
- FRESH yields a reusable solution doc plus a 5-minute brief; UPDATE edits both surgically, regenerates the PDF and
  says what changed.
