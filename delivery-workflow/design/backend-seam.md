# backend seam — pty_tmux, declarations, command-map

> Settles the backend seam. Launch mechanism = tmux+send-keys, retained as baseline
> (owner decision). The seam is redesigned from scratch: capabilities declared, never
> name-switched — a renamed CLI can never silently change behavior. Owner ruling: the
> service structural family is **deleted**, not deferred — v2 has exactly one structural
> adapter; codex joins as a pty declaration when actually adopted.

## 1. The two-layer seam

- **Layer 1 — declaration (config, per backend)**: `config/backends/<name>.kv`. Holds the
  **command-map** (generic opcodes → the CLI's literal flag strings, with `{model}`,
  `{effort}`, `{workspace}`, `{profile}`, `{bootstrap}` placeholders — `{bootstrap}` is
  the adapter-quoted positional "Read and execute <prompt-path>" argument), the **screen
  signature set** (closed regex classes for pane classification), and the **capability
  list**. Adding a PTY CLI = adding one declaration file. Zero code. Self-check pins
  every declaration's placeholders to the adapter's substitution set.
- **Layer 2 — structural adapter (code, per structural family)**:
  `runtime-scripts/backends/pty_tmux.sh` — the only family. It owns what a string map
  cannot express: PTY lifecycle, injection discipline, liveness probing, teardown.
  A future non-PTY backend would mean writing a second adapter against the documented
  contract in §6 — possible without touching the ferry, but deliberately **not pre-built**.

The ferry calls adapter functions only; the adapter reads the declaration. Neither layer
ever branches on a backend *name*.

**Invariant (capability 0)**: the adapter is a mechanical pipe. It carries zero cross-role
reasoning — it never frames, summarizes, or pre-judges anything an agent produces.

## 2. Capabilities and role admission

Declared set (closed vocabulary): `pty`, `subagent`, `stop_gate`, `heartbeat`,
`heartbeat_covers_subagents`, `warm_resume`, `nudge`, `takeover`.

Role admission requirements (checked per (role → backend) assignment **at every spawn**,
where the assignment is actually resolved — the topic-level pair is only what the launch
door can see; any miss → refuse with a self-describing reason, never a silent fallback):

| role | requires |
|---|---|
| author | `pty, subagent, stop_gate, heartbeat` (+ `heartbeat_covers_subagents` for impl; absent → impl budget/`working`-age are the only guards, stated at start) |
| reviewer | `pty, stop_gate, heartbeat` |

`warm_resume` gates the warm rows of stages.tsv: a backend without it forces those rows
cold (degradation is named at topic start, never silent).

**Declarations are promises; the onboarding probe makes them facts.** `launch.sh` first use
of a backend (and after any CLI version change, recorded in the run surface) runs a scratch
session probe: Stop gate actually blocks a record-less turn-end; the heartbeat hook actually
writes the store; injection actually arrives; each declared signature actually matches the
live UI. Probe failure = the declaration is wrong; the topic refuses to start on it.
Implemented as `runtime-scripts/probe.sh` (launch-invoked; one probe per unique backend in
the **config-reachable set** — the topic-level values plus every distinct
`agent.<role>.backend` in a `slice.<nn>.<agent>.kv` on disk, because the spawn resolves per
(role, slice) and a slice-only backend would otherwise never be probed at all; unchanged
CLI version = cached pass; hard items refuse, soft items — `working`, `modal` — are
attested when observed and named as unobserved otherwise; the drill proves both probe
directions against the mock backend).

**Promise and fact are checked at the same line.** The capability list is a *promise*; a
valid probe record is the *fact*, and for a long time only the promise was ever checked at
the spawn — nothing asked whether it had been proven, and the probe ran at launch over a
different, smaller set. So the spawn now asks both: `probe.sh --verify` reads the stored
record's own identity (CLI version ⊕ declaration ⊕ profile ⊕ the probe's own code ⊕
`result=pass`) and spawns nothing, so it is the probe's derivation rather than a copy of
it. Absent or stale → `park(template_error)` naming the backend and the one instruction
that clears it. This is Kubernetes' admission split: validate at the door where the fix is
free, and let the runtime path still fail honestly, because the door cannot see what is
written after it. It costs no session — the probe cache is per workspace and **survives
launches**, so a backend proven on any earlier launch of this topic stays proven, and
switching back to it mid-run just works.

**A CLI's own prompts are the backend's surface too.** The self-update prompt is
the measured case: three anchors on one topic — a probe reporting every capability
missing while the refusal blamed the declaration, a stage session parked
`unknown_screen` while the CLI merely awaited an answer, and a launch probe hung
past four minutes until an operator answered it by hand. Nothing was broken; a
question was unmodelled. It joins the modal allowlist like any other declared
overlay, with the act being the prompt's own default, and the allowlist stays
exact — an unmatched modal still parks loudly. The scratch session's fixed name
gets the fence the ferry's cold spawn already had, because the other half of that
incident was the orphan a killed launch left sitting on it.

**Capability is not availability, and the probe says which one it is answering.**
The cache key — CLI version ⊕ declaration ⊕ profile ⊕ probe implementation — is
exactly right for the question a probe answers: can this declaration's promises be
made facts. Quota is a property of none of those, so the key is not widened for it.
Instead the cached result **steps aside** while the topic holds an unresolved
`backend_quota` halt — the workflow's own evidence that this backend was unusable —
and the live re-probe then classifies the quota pane and refuses with its own exit
code, distinct from a declaration failure. Both halves were measured on one event
chain: a relaunch inside a zero-quota window reported a cached pass and spawned
sessions that were born dead, and a probe that did run would have burned its whole
timeout and then blamed the declaration for a backend that was merely out. The
refusal forwards the pane's own line verbatim, because the reset time differs per
CLI — a daily window, a rolling hour, another timezone — and a driver that computes
or defaults one is inventing the single fact the operator needs.

## 3. Command-map (worked declarations)

Opcodes: `cmd.launch` (the full cold spawn line), `cmd.version` (for the run-surface pin).
Backend, model and effort are **first-class per-agent parameters** resolved from config
(default → topic → (slice, agent)) and substituted at spawn — v1's hardcoded
`--model <slug> --effort max` literals become placeholders. The backend is the one of the
three that also selects the profile template and the signature set, so the spawn — not the
launch — is where it binds; §2's admission asks both its questions there.

The launch line executes as ONE string, parsed by the pane's shell (tmux
default-shell) — so quoting written in a declaration is load-bearing, not
cosmetic. `{model}` is double-quoted at the flag site because a tier suffix
(e.g. a bracketed context-tier suffix such as `model[1M]`) is a glob class to
that shell: unquoted it kills the pane under zsh ("no matches found" — an
attempt born dead) and silently rewrites the slug under bash where a matching
filename exists (both measured 2026-08, tmux 3.0a). Config values stay bare
slugs; the quoting lives in the declaration, and 30-closure enforces it as a
blanket rule (quoting a glob-free slug changes nothing).

`config/backends/claude.kv`:

```
family=pty_tmux
cmd.launch=claude --model "{model}" --effort {effort} --permission-mode dontAsk --add-dir {workspace} --settings {profile} {bootstrap}
cmd.version=claude --version
prompt_style=positional
profile=profiles/settings-hooks.json
cap=pty,subagent,stop_gate,heartbeat,heartbeat_covers_subagents,warm_resume,nudge,takeover
frame_settle=0.4
sig.working=(esc to interrupt|Thinking|Running command|✻)
sig.composer_line=^[[:space:]\xC2\xA0]*❯
sig.awaiting_input=^[[:space:]\xC2\xA0]*❯[[:space:]\xC2\xA0]*$
sig.error_retryable=(API connection error|overloaded_error|Retrying in)
sig.quota_exhausted=(usage limit reached|hit your (session|weekly|Opus) limit|[Yy]our limit will reset at)
sig.backend_overloaded=529 Overloaded
sig.modal.trust=(Do you trust the files in this folder\?|Yes, I trust this folder)
act.modal.trust=Enter
nudge_text=continue
```

(Values are verbatim from the shipped declaration — the adapter reads a line
to its end, so a declaration line never carries a trailing comment; the
composer/awaiting signatures anchor the live-measured classification domain,
NBSP-tolerant on both sides.)

`frame_settle` is the gap between the two frames of the stability test: how
long this CLI's output may pause mid-flight and still be flowing. It belongs
here for the same reason the signatures do — it is a property of the backend's
RENDERING, measured, not a constant the adapter is entitled to assume for
every CLI. OPTIONAL: an absent or non-numeric value falls back to the
live-measured 0.4 (a settle time is a comfort, and a typo must not stop a
session being classified at all), and 30-closure refuses a value that is
present but not a number, so which one is in force is never a guess. A backend
that paints synchronously declares less and stops paying for a frame that
cannot change — the self-check's mock declares 0.05, which is 27s off one
drill run.

`probe.latency` is the onboarding probe's reaction bound (seconds): how long
this CLI may take to paint its idle composer after a turn ends, to echo an
injected line, to exit after `/exit`. The probe's sub-phases each exit the
moment their event arrives, so the bound is spent only on proving "it never
came" — it is a property of the CLI's responsiveness, declared for the same
reason `frame_settle` is. OPTIONAL: absent or non-numeric falls back to 30, the
constant the probe carried before; 30-closure refuses a value that is present
but not a whole number. The self-check's mock declares 5.

`config/backends/claude.kv`: identical shape; `cmd.launch=claude --model "{model}" ...`
(flag names per the claude CLI; same capability list, own signature literals).
`codex.kv`: authored 2026-08-17 against codex-cli 0.147.0, every signature live-measured
in scratch tmux sessions (hook semantics included: Stop exit-2 blocks the turn end and the
stderr text becomes the continuation prompt; PreToolUse fires per tool call). Two
codex-specific facts the authoring measured: hooks reach the session through the
**project layer** (`<cwd>/.codex/hooks.json`, gated by the trust dialog — cmd.launch
mounts the baked profile there, since codex has no `--settings` flag), and a `//`
comment key in hooks.json makes codex **silently skip the whole file** — which is why
`codex.hooks.json` carries `hooks` and nothing else. The probe still attests on first
real use and on every `cmd.version` change.

Signature/action rules: the modal set is an **exact-match allowlist** (one `act.modal.*`
per known modal); an unmatched modal or unmatched screen state → `park(unknown_modal)` /
`park(unknown_screen)` with the captured text attached — signature rot is loud, never a
silent misclassification. Full-auto runs with `--permission-mode dontAsk`; a permission
modal appearing at all is config drift, surfaced not auto-answered.

## 4. tmux mechanics (the retained baseline, with v1's paid-for lessons)

- **Cold spawn**: `tmux new-session -d -s <name> -x 220 -y 50` + the `cmd.launch` line with
  the **bootstrap as the positional argument** ("Read and execute <abs>/stage_prompt.md") —
  constant shape, no post-boot injection window, no quoting surface, prompt content never
  in the command line. `pipe-pane` armed at spawn → `.runtime/logs/<stage>.log`. The
  `-x 220 -y 50` geometry is part of the declared contract the screen signatures read, so
  the spawn pins `window-size manual` on the window: a declared parameter is never
  renegotiated with a client (with the default `smallest`, any attach — read-only included
  — permanently rewrites the pane size with no rebound). The pin needs
  tmux >= 2.9 (window-size, default-size and resize-window arrived together in
  2.9); on an older tmux every spawn refuses at the pin, and the refusal names
  the floor and the machine's version.
- **Session names**: `delivery-<topic>-<slice>-<stage>`; charset allowlist
  `[A-Za-z0-9_-]` (a `:` or glob can redirect tmux targets); always addressed with the
  exact-match prefix `-t "=<name>"`.
- **Injection** (single primitive, shared by nudge and warm re-activation — one state
  machine, `none|nudge_pending|resume_pending` mutually exclusive, so a nudge can never
  fuse with a re-activation):
  1. capture-pane twice, frames must agree (absorbs the one-event repaint lag);
  2. classified `awaiting_input` **with empty composer** — emptiness is the CURSOR's
     question, not the text's: a TUI paints its hint/ghost AFTER the cursor and a human's
     typing BEFORE it, and a plain capture renders the two identically (live-measured:
     Claude Code 2.1.228 hints into an EMPTY box, which made every classification
     `unknown` and every injection a refusal). So the declared regex is applied to the
     composer line TRUNCATED AT THE CURSOR; when tmux cannot place the cursor the
     whole-line rule answers, as before. Text before the cursor refuses ALWAYS; it is
     `park(operator_interference)` with the screen attached only when tmux reports a
     writable client attached — a human demonstrably there (v1's fused-submission
     incident, closed structurally). With nobody attached the same screen is a rendering
     artifact: refused as `composer_occupied`, which the nudge caller retries past and the
     warm caller cold-falls-back from, rather than parking on an absent operator;
  3. `send-keys -l '<text>'` then a separate `send-keys Enter`. **Never navigation keys**
     (`Left`/`Escape` are destructive on the measured TUI).
- **Liveness**: dual-pid (pane pid + tmux server pid) + process start identity (pid-reuse
  defense; procfs on Linux, `ps` on macOS — `lib/platform.sh`), recorded in the sessions surface at spawn — the launch command IS the pane
  command, so a dead CLI has no pane and pid liveness is the whole dead-detection
  truth (a hypothetical pane-alive-CLI-dead state has no composer and parks
  `unknown_screen`, loudly). Full classification stack in `state-and-liveness.md` §5.
- **Teardown**: exact-target kill; **fail-closed** — never start a replacement tmux server
  to prove absence; if the recorded socket is gone while the launcher generation is alive,
  refuse and surface. Parks leave sessions alive for postmortem attach (takeover is a
  feature); startup reconcile fences them next run.

## 5. Nudge and pause recovery

Within-stage pause (server drop, retry banner, idle composer) is **nudge**, not warm-resume:
classify via signatures → `error_retryable`/`awaiting_input` → inject the declared
`nudge_text` through the §4 primitive. One nudge per quiet episode; no effect within
nudge-grace → bounded respawn → park. `working` state has its own max age (hard ceiling)
so a stuck spinner cannot extend forever. Every timeout is an independent config literal
(no derived defaults). Respawn needs no explicit backoff: each respawn re-enters the
quiet-grace + nudge-grace observation ladder before the next can fire — the ladder IS
the backoff — and a cold spawn's own boot time adds a natural floor.

## 6. Adapter contract (for a hypothetical second family; documentation, not code)

`spawn_cold(decl, session, cmd) → ids` · `alive(ids) → running|dead` ·
`classify_screen(decl, ids) → state` · `inject(ids, text)` (with the §4 preconditions) ·
`teardown(ids)` (fail-closed) · `reconcile(prefix) → sessions`. Plus the capability-0
invariant and: the session-side tools (`record.sh`, `heartbeat.sh`) must be reachable from
inside the spawned process (true trivially for local PTYs; a sandboxed family would need an
ingest path — decide then, not now).

## 7. Why not headless/SDK (the negative space, recorded)

The obvious alternative to driving a TUI is the CLI's headless mode
(`-p`/stream-JSON) or an agent SDK: structured events instead of screen
classification, no injection window, no signature probing — everything §3–§5
exist for has a machine interface there. It is not taken because: (a) the
daily-driver backend is a wrapper CLI whose model-swap and external billing are
proven only on its TUI path — no evidence either way for its headless path, and
only a live probe could settle it; (b) takeover-as-a-feature: parks leave real
terminals a human can attach to and drive, which no headless stream provides;
(c) nothing is lost structurally — the declaration+probe seam isolates exactly
what a migration would touch, so a headless family would be a second adapter
under §6's contract with event mappings in place of screen signatures. The
screen-driving subsystem is the price of (a)+(b), paid knowingly — not an
unexamined default.

## 8. Prior art and the layering (why the cursor, not the rendering)

The composer-emptiness fix (`b1033da`) sits at a chosen layer, not a guessed
one. A TUI's "is the box empty" can be answered at three layers, weakest to
strongest:

- **Guess the rendering** — strip SGR dim runs, normalise NBSP, match known
  placeholder text. Measured and rejected: the placeholder text varies across
  sessions; SGR terminators are not always `ESC[22m` (measured `ESC[0m`);
  NBSP normalisation was unnecessary and would have swallowed tmux's rc on the
  capture pipeline. Every variant guesses what the TUI drew.
- **Read a terminal fact** — the cursor. The terminal knows where the cursor
  is; a TUI paints its hint AFTER it and a human types BEFORE it. One
  `display-message` call answers exactly. This is what shipped.
- **Read a protocol fact** — the application declares "I am at an input
  prompt". OSC 133 semantic prompt marking (FinalTerm/FTCS; iTerm2, WezTerm,
  kitty, VS Code, Ghostty) is the correct endgame: the markers ride the
  `pipe-pane` stream already captured, so no cursor inference is needed. It is
  not available — `anthropics/claude-code#32635` (requesting Claude Code emit
  them) is closed-as-duplicate, unimplemented, so no markers ride the captured
  stream to read. Claude Code's Notification hook is **wired** (the
  profile wires `idle_prompt|permission_prompt`
  to `session/notify_event.sh`, which appends the `notify_events` surface; the
  watch loop reads a fresh `idle_prompt` as PRIMARY for the idle classification
  with the screen as corroboration — state-and-liveness.md §5). It does not
  cover `modal.self_update` (a CLI self-update prompt, outside Claude Code's
  hook surface), `quota_exhausted`, `backend_overloaded`, or
  `error_retryable`, which stay screen-only; the codex declaration does not carry the hook surface yet and
  stays screen-only (named, never silent).

The middle layer — guessing the rendering — is the failure mode the cursor
fix retired. Short term: the cursor (a fact the terminal knows). Long term:
OSC 133 (a fact the application declares) or the Notification hook (a fact the
hook channel carries). The screen stays only for what only it can see —
modals the wrapper paints, quota, retryable errors — with undeclared states
parking loudly rather than guessed.
