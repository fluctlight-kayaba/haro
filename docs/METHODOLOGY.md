# Haro Development Methodology

How we build Haro: goal-driven, test-first, everything reproducible on a virtual runtime. This doc is the framework — mechanics get refined as we implement. When reality contradicts this doc, fix the doc.

## Goals

The methodology exists to deliver four things. Everything else is negotiable.

1. **Reproducibility at every scale.** Any behavior — a rope split, a cell blend, a full frame render, a key sequence — can be reproduced in isolation, in-process, without a real terminal. If reproducing a bug requires manually poking a live terminal, the test infrastructure has a gap; fix the gap, not just the bug.

2. **Diagnosable failures.** A failed test explains itself from its output alone — power-assert decomposition, state snapshots, captured ANSI — without re-running under a debugger. Haro's own agent will read these reports to fix its own code; treat test output as an API, not a log.

3. **One suite, runs everywhere.** CI runs exactly what local runs: unit, sim, perf gates. There is no "works locally" tier. Single binary + no vendored runtime makes this cheap — keep it that way.

4. **Tests as assets.** Every committed test has a name and a reason to exist. Debug scratch lives in `/tmp` and dies there — or graduates into a named suite.

## Principles

- **Test-first at the lowest level that expresses the behavior.** Pure logic → unit test. Cross-module behavior (input → render) → sim test. Don't write a sim test for what a unit test can express; don't unit-test what only matters end-to-end.

- **Real pipeline, virtual boundary.** Simulate at the I/O boundary only; everything inside runs for real. Never mock internal modules — mock-based tests verify the mock, not the system.

- **In-process and synchronous.** Tests drive the platform in the same process; an injected input is fully processed when the call returns. No IPC, no sleeps, no polling, no "wait for settle" — this kills flakiness at the root.

- **Deterministic over wall-clock.** Assert on counters the pipeline exposes (cells composited, SGR codes emitted, frames rendered, diff cell count). Wall-clock budgets are smoke-level only, with generous headroom.

- **Thresholds over golden files.** Assert properties ("< 50 cursor toggles for 20 movements", "frames unique") rather than byte-exact output. Golden files churn on every renderer tweak; properties survive refactors.

- **Fixtures by state, not by input.** Set up test state directly (`setBuffer(...)`, `setCursor(...)`). Only input tests go through the key path — otherwise every test transitively depends on input parsing working.

## The Core Loop

Feature:

1. Write the failing test at the lowest level that can express the behavior
2. Verify it fails
3. Implement the minimum
4. Verify it passes; `msc test src/` stays green
5. Refactor with tests as the safety net

Bug fix:

1. Reproduce as a failing test — this is the definition of "reproduced"
2. Fix minimally
3. Full suite green; the test stays, named after the behavior (not the incident)

## Test Levels (target shape — build as we go)

| Level | What | Driven by | Asserts on | Exists from |
|---|---|---|---|---|
| **Unit** | pure logic: rope ops, cell blend, diff, ANSI gen, key parse | direct function calls | power assert | Phase 1 |
| **Sim** | real pipeline on a virtual terminal | injected bytes / direct state setup | state + captured ANSI + counters | Phase 1, grows with the pipeline |
| **Perf gates** | named budgets on hot paths | sim scenarios | deterministic counters (+ coarse wall-clock smoke) | when the render pipeline stabilizes |
| **Plugin e2e** | `haro.e2e.*` exposed via Raiser VM | plugin scripts | same surface as sim | Phase 6 |

All levels run with `msc test` — MetaScript's built-in `test`/`assert` keywords. No separate test runner, no scripting VM needed for levels 1–3.

### VirtualTerminal — the virtual runtime

The platform runs against a `Terminal` interface with two implementations:

- **real**: termios raw mode, stdout writes, SIGWINCH resize
- **virtual**: input byte queue, output capture buffer, programmatic resize

Everything above the interface is identical in both. A sim test injects `\x1b[A` into the queue → the real input parser parses it → the real compositor/diff/renderer run → ANSI lands in the capture buffer — and the test asserts on any stage: parsed key events, grid cells, diff output, escape-code counts.

```typescript
test "cursor down renders only changed cells" {
    const term = new VirtualTerminal(80, 24);
    const platform = bootHeadless(term);
    platform.setBuffer("line one\nline two\nline three");

    term.resetCounters();
    term.inject("j");
    platform.tick();

    assert platform.cursor().line === 1;
    assert term.counters().cellsUpdated < 200 : "cursor move must not repaint the grid";
}
```

(Shape, not final API — refine as the pipeline lands.)

## Lessons from Vimcraft

Vimcraft (the Zig + Hermes predecessor) documented and ran a serious methodology: two-level tests, mandatory E2E-first TDD, an in-process synchronous test API, threshold assertions, perf budgets, LLM-readable JSON reports. Its wins are baked into the principles above. Its failure modes are what the goals guard against:

| Vimcraft did | What actually happened | Our counter-principle |
|---|---|---|
| E2E suite + perf gates ran local-only; CI ran unit tests only | "builds fail on threshold" was aspiration, not mechanism | one suite, runs everywhere |
| new sandbox dir per debugging session | 27 of 111 sandboxes were empty husks; always-pass debug tests got committed | tests graduate or die |
| E2E-first TDD mandated for everything | suite sprawl, near-duplicate sandbox families | lowest expressive level first |
| fixtures set up by typing keys (`iHello<CR>...`) | every test coupled to insert mode + key parsing | fixtures by state |
| perf asserted via `Date.now()` wall-clock | thresholds padded to absorb noise; real regressions fit under them | deterministic counters |
| real PTY even under headless tests | heavyweight, CI-hostile | virtual terminal interface |

What it got right and we keep: in-process synchronous test API (kills flake at the root), same API for testing and debugging (debug sessions harden into regression tests), threshold/property assertions (zero golden-file maintenance), perf budgets as named constants in a normal test suite, and test reports rich enough that an agent can diagnose a failure without re-running.

## Decide As We Go

Direction noted, decision deferred until the code forces it:

- **JSON state reports** (state_before/after/checkpoints per test): valuable — Haro's agent debugging Haro is a core workflow. Likely lands around Phase 3 with the TUI. Not Phase 1.
- **Sim test placement**: colocated `*_test.ms` vs `tests/sim/`. Leaning `tests/sim/` since sim cuts across modules — decide when the first sim test exists.
- **Perf gate numbers**: budgets come from measuring the real pipeline, never invented upfront.
- **Agent-facing report format**: shape it when the agent exists to consume it.
