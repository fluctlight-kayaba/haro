# Haro — Terminal Code Platform for AI Workflows

> "Haro Haro, build complete!"

A terminal-native code platform built in MetaScript. Agent and editor share the same surface — review, direct, annotate, edit — in one tool. Free-canvas rendering, Raiser VM plugins, building blocks for anyone building agentic terminal tools.

**Core design sources:**
- [Vimcraft](https://github.com/vimcraft-labs/vimcraft) (Zig + Hermes) — rendering engine, multi-layer compositor, buffer ops, terminal I/O
- [pi](https://github.com/earendil-works/pi-mono) — agent loop design, provider abstraction, tool dispatch, session format
- [Neovim](https://neovim.io) — plugin philosophy, extensible core, `haro.*` API model

## Identity

**Name**: Haro (ガンダム00のハロ). Small, round, loyal companion robot. Says "Haro Haro!" a lot.

**What**: Terminal code platform where AI agent and human share the same surface. Agent edits code, human reviews diffs, annotates feedback, directs next steps — all in one tool. Not a chat app, not a plugin bolted onto an editor. Designed from the ground up for AI-assisted coding.

**Free-canvas**: The rendering surface is not limited to "editor with lines of text." It can render code, diffs, annotations, agent conversations, and custom plugin UI — composited as layers on a shared canvas. More flexible than Neovim, more capable than a diff viewer.

**Building blocks**: Haro is a platform, not just a product. The rendering engine, agent core, plugin system, and default plugins are all building blocks. Anyone can use them to build agentic terminal tools — custom agents, review surfaces, interactive diff viewers, annotation systems.

**Personality**: Friendly and talkative. Announces actions and completions with short, cheerful status lines ("Haro Haro, read 3 files!", "Haro thinks this needs a fix..."). Chatty to stay engaging, never spammy — one line per action, never walls of text.

**Target**: Single native binary, zero runtime dependencies. `scp haro server:~` and it works.

**Positioning**: Neovim built for the AI era. Core is small, plugins are powerful, defaults serve AI workflows. Open and extensible — not a closed product like Cursor.

**Why MetaScript**: A systems programming language with TypeScript syntax — compiles to a single native binary that sips RAM instead of needing Node.js. Ships with Raiser, a built-in VM that lets users write plugins in TypeScript (similar to how pi does extensions, but running on a systems-grade runtime). Plus: DRC (no GC pauses), actors (tool isolation), `Promise<Result<T,E>>` (typed errors), and compile-time metaprogramming (macros, quote/AST manipulation, custom DSLs).

## Architecture

```
haro/
├── src/
│   ├── main.ms                  ← entry: parse args, boot platform
│   │
│   ├── render/                  ← Terminal rendering engine
│   │   ├── compositor.ms        ← Multi-layer compositing (base, gutter, diff, annotation, cursor)
│   │   ├── display.ms           ← ANSI output, synchronized updates, cursor tracking
│   │   └── buffer.ms            ← Rope-based text buffer (read-heavy, review-optimized)
│   │
│   ├── input/                   ← Terminal I/O
│   │   ├── terminal.ms          ← Raw mode, termios, terminal size
│   │   └── keys.ms              ← Key event parsing, vim navigation (j/k, search, jump)
│   │
│   ├── agent/                   ← AI agent core (embedded subsystem)
│   │   ├── provider/
│   │   │   ├── types.ms         ← Model, Context, Message, ToolCall, ToolResult
│   │   │   └── anthropic.ms     ← Anthropic streaming API via std/http
│   │   ├── tools/
│   │   │   ├── read.ms          ← file read tool
│   │   │   ├── write.ms         ← file write tool
│   │   │   ├── bash.ms          ← subprocess execution tool
│   │   │   └── edit.ms          ← find-replace edit tool
│   │   ├── loop.ms              ← Conversation loop, LLM stream consumption, tool dispatch
│   │   └── session.ms           ← JSONL session persistence
│   │
│   ├── plugin/                  ← Raiser VM plugin system
│   │   ├── host.ms              ← Plugin lifecycle, sandboxing
│   │   └── api.ms               ← haro.* API surface (buffers, events, agent, annotate)
│   │
│   └── defaults/                ← Default plugins (swappable, removable)
│       ├── diff.ms              ← Side-by-side diff viewer
│       ├── annotate.ms          ← Bidirectional annotation (Human↔Agent)
│       ├── highlight.ms         ← Tree-sitter syntax highlighting
│       └── system-prompt.ms     ← AGENTS.md loader, prompt builder
│
├── AGENTS.md                    ← this file
└── build.ms                     ← MetaScript build config
```

### Layer model

Multi-layer compositor — each concern is a separate layer, blended per frame:

```
Layer 0:   base           ← buffer text content
Layer 100: gutter          ← line numbers, signs, annotation indicators (▍)
Layer 200: cursorline      ← current line highlight
Layer 300: virtual_text    ← plugin overlays (annotations, agent notes)
Layer 400: selection       ← visual selection highlight
Layer 500: diff            ← diff highlights (added/removed/changed)
Layer 600: overlay         ← modals, annotation editor, command palette
```

Dirty flags per layer — only recomposite what changed.

### Platform Backends

Anything OS-specific hides behind an interface with one impl per platform, selected at build time — never `#ifdef`-style branching inside a shared file. Code above the interface never knows which OS it runs on.

Convention (first instance: the `Terminal` interface):

```
input/
├── terminal.ms           interface + factory (picks impl by build target)
├── terminalPosix.cms     extern → libc (termios, ioctl)      — --os=macos/linux
├── terminalWindows.cms   extern → kernel32 (console API)     — --os=windows
└── terminalVirtual.ms    in-memory queue + capture           — always compiled
```

Rules:
- `Posix` / `Windows` / `Virtual` camelCase suffix; the bare name (`terminal.ms`) holds the interface + factory.
- The build selects the real backend per `--os`; the `Virtual` impl is **always** compiled — every sim test runs on it, on any OS.
- ANSI/VT is the shared wire format both platforms speak (Windows 10 1511+ with VT mode on). Rendering, diff, and key parsing stay platform-agnostic — only raw-mode, size query, and read/write differ.

## Design Principles

1. **AI-first, not AI-bolted-on** — the platform is designed around agent workflows. Review, direct, annotate are first-class. Manual editing is secondary but available.

2. **Neovim philosophy: small core, powerful plugins** — defaults serve AI workflows but everything is swappable via Raiser VM. Diff viewer, annotation, even the agent itself are plugins.

3. **Free-canvas rendering** — the compositor is not locked to "lines of text." Layers can render anything: code, diffs, annotations, agent output, custom UI. Plugins define what appears on the canvas.

4. **Native binary first** — C backend is primary. JS backend is secondary (for testing/dev only).

5. **Review over write** — the world is shifting from "human writes, AI helps" to "AI writes, human reviews." Haro is optimized for the review + direct workflow. Less editing complexity (no macros, no registers), more diff/annotation/navigation power.

6. **Actor model** — agent tools run as actors (isolated state, crash-safe). The agent loop is an actor. Communication via message passing.

7. **`Promise<Result<T,E>>`** — LLM calls return typed errors. No throw/catch in async paths. Use `try await` to unwrap.

8. **No npm dependencies** — std/http for API calls, std/json for serialization, std/fs for files, std/process for bash tool.

9. **Metaprogramming where it counts** — system prompt builders, tool schema generation, session serialization, and DSL macros are all compile-time candidates.

## Plugin API

Raiser VM plugins with haro.* API:

```typescript
haro.buffer.open("src/main.ms");
haro.buffer.onSave((path, content) => { ... });

haro.agent.onToolCall((tool, args) => { ... });
haro.agent.onResponse((message) => { ... });

haro.annotate.add({ file: "src/main.ms", lines: [42, 50], author: "AGENT", text: "verify" });
haro.annotate.onUserAnnotation((ann) => { ... });

haro.diff.show("HEAD~1");
haro.diff.onHunkSelect((hunk) => { ... });
```

Same model as Neovim's Lua API, but TypeScript via Raiser VM.

## Build & Run

```bash
# Build native binary (host platform)
msc build src/main.ms --target=c --output=haro

# Cross-compile — build selects the platform backend (_posix / _windows)
msc build src/main.ms --os=macos   --output=haro
msc build src/main.ms --os=linux   --output=haro
msc build src/main.ms --os=windows --output=haro.exe

# Run
./haro                          # interactive mode
./haro -p "list files"          # print mode (non-interactive)
./haro diff                     # diff viewer mode
./haro diff HEAD~1              # diff specific commit

# Test
msc test src/
```

## Dependencies

- **MetaScript stdlib**: `std/http`, `std/json`, `std/fs`, `std/process`, `std/io`, `std/os`
- **MetaScript compiler** ([github.com/metascriptlang/recompiler](https://github.com/metascriptlang/recompiler)): invoked via `msc` CLI in `$PATH`

## Related Projects

- **Vimcraft** ([github.com/vimcraft-labs/vimcraft](https://github.com/vimcraft-labs/vimcraft)): the Zig + Hermes predecessor. Rendering engine, compositor, buffer ops are ported from here.
- **Neovim** ([neovim.io](https://neovim.io)): plugin philosophy and API design reference.
- **recompiler** ([github.com/metascriptlang/recompiler](https://github.com/metascriptlang/recompiler)): the MetaScript language and compiler. If haro hits a compiler limitation, fix it there.
- **pi** ([github.com/earendil-works/pi-mono](https://github.com/earendil-works/pi-mono)): reference for agent loop design and provider patterns.
- **Lumen** ([github.com/jnsahaj/lumen](https://github.com/jnsahaj/lumen)): reference for diff viewer UX (diff plugin).

## Session Format

JSONL with tree structure (like pi). Each line: `{ id, parentId, role, content, timestamp }`. Branching via parentId pointers — no file duplication.

## Phase Plan

| Phase | Goal | Status |
|-------|------|--------|
| 0 | Project setup, AGENTS.md, ROADMAP | Done |
| 1 | Rendering engine: terminal I/O, compositor, buffer | Pending |
| 2 | Agent core: Anthropic provider, tools, conversation loop | Pending |
| 3 | Basic TUI: agent output + vim navigation, end-to-end MVP | Pending |
| 4 | Diff viewer plugin | Pending |
| 5 | Annotation plugin (bidirectional) | Pending |
| 6 | Raiser plugin system | Pending |
| 7 | Session persistence, branching | Pending |
| 8 | More providers (OpenAI, Google) | Future |
| 9 | Tree-sitter syntax highlighting | Future |

## Implementation Methodology

Goal-driven, test-first, everything reproducible on a virtual runtime. The full framework — goals, principles, test levels, lessons learned — lives in **`docs/METHODOLOGY.md`**. Read it before implementing any subsystem.

The short version:

- **Core loop**: failing test first, at the lowest level that can express the behavior → minimal implementation → pass → refactor. Bug fixes start with a failing regression test — that is the definition of "reproduced".
- **Real pipeline, virtual boundary**: the platform runs against a `Terminal` interface (real: termios; virtual: in-memory input queue + output capture). Sim tests inject bytes, the real pipeline processes them, assertions read state + captured ANSI + counters. In-process, synchronous — no IPC, no sleeps.
- **Deterministic assertions**: pipeline counters and thresholds, not golden files, not wall-clock.
- **Tests graduate or die**: debug scratch lives in /tmp, never committed; a test either becomes a named suite or gets deleted.
- **MetaScript idiom**: `struct` for value types, `interface` for reference types, `match` for dispatch, closures for callbacks, `test`/`assert` with power assert. Zig→MetaScript translation patterns in `docs/VIMCRAFT-DELTA.md`.

## Rendering Reference

Haro's rendering engine implements a three-stage pipeline: compositor → diff → ANSI render. The algorithms descend from Neovim's grid protocol and Helix's terminal optimizations, but are implemented natively in MetaScript — no allocator threading, no function-pointer callbacks, no manual refcounting.

### Three-stage pipeline

```
Stage 1: Compositor    — blend N layers in z-order (Porter-Duff "over")
Stage 2: Diff          — compare current vs previous frame, output only changed cells
Stage 3: ANSI Render   — generate escape codes with adjacent-skip + attribute dedup
```

**Stage 1 — Compositor**: Blend layers back-to-front (painter's algorithm). Fast path: opacity = 1.0 and cell has content → direct copy (95% of cells). Dirty rectangle incremental: only re-composite cells within dirty rects.

**Stage 2 — Diff**: Double buffer (current + previous grid). Compare cell-by-cell on dirty lines only. Initial previous uses sentinel (char=0) so first render detects all cells as changed. Typical frame: 2-400 changed cells, not full grid.

**Stage 3 — ANSI Render**: Generate escape codes with:
- Adjacent cell skipping (skip cursor move if next update is adjacent)
- Attribute deduplication (only emit SGR codes when bold/italic/underline/fg/bg changes)
- Cross-frame attribute tracking (state persists between frames)
- Synchronized updates (DCS sequences `\x1bP=1s...\x1b\\` wrap output for atomic flush, eliminates tearing on iTerm2/Alacritty/WezTerm/tmux)

### Screen grid — O(1) scroll via line-offset indirection

Double buffer: `current[height][width]` and `previous[height][width]`. `Cell` is a value-type struct (stack-allocated, zero RC overhead):

```typescript
struct Cell {
    char: u21;           // Unicode codepoint
    fg: uint32;          // packed RGB
    bg: uint32;
    attrs: uint8;        // bold | italic | underline
    is_wide: boolean;    // second cell of double-width char
}
```

Scrolling rotates an `offsets[]` array (logical row → physical row mapping) instead of copying cells. For a 200×50 terminal scrolling 1 line: 50 offset updates vs 10,000 cell copies. `swapBuffers()` is O(1) — pointer swap + rotate offset arrays.

### Rope buffer

Tree-based rope, leaf ~512 bytes. O(log n) insert/delete/concat. `newline_count` cached per node → `lineCount()` and `byteOfLine()` are O(log n). UTF-8 safe split points (walk backward through continuation bytes to find character start). DRC refcounting enables node sharing for undo without manual refcount management.

### Layer system (z-index ordering)

| z-index | Layer | Purpose |
|---------|-------|---------|
| 0 | base | buffer text content |
| 100 | gutter | line numbers, signs, annotation indicators (▍) |
| 200 | cursorline | current line highlight |
| 300 | virtual_text | plugin overlays (annotations, agent notes) |
| 400 | selection | visual selection highlight |
| 500 | diff | diff highlights (added/removed/changed) |
| 600 | overlay | modals, annotation editor, command palette |

Each layer has its own grid + dirty flag + dirty rect tracker. Layers sorted by z-index via binary search insertion. Dirty flags per layer — only recomposite what changed.

### Terminal I/O

Raw mode via termios: disable `ECHO`, `ICANON`, `ISIG`, `IXON`, `ICRNL`. Set `VMIN=1, VTIME=0` (blocking read, wait for ≥1 byte). Enter alternate screen buffer (`\x1b[?1049h`). Enable SGR mouse mode (1006) + bracketed paste (2004).

Input handling: persistent byte buffer (append, don't replace across `stdin.read()` calls). Parse returns `complete` / `incomplete` / `none`. ESC timeout tracking — when ESC received alone, wait before treating as standalone vs start of escape sequence.

## Open Design Questions

- **Raiser VM readiness**: is it stable enough to host plugins? Need to verify API surface before Phase 6.
- **Terminal raw I/O**: MetaScript stdlib needs termios bindings (raw mode, winsize). May need to contribute to recompiler stdlib.
- **SSE parsing**: provider streaming needs Server-Sent Events parser. Not in MetaScript stdlib yet.
- **Buffer data structure**: rope — tree-based, leaf ~512 bytes, O(log n) edits. Proven, refcounted node sharing for undo. See Implementation Methodology below.
- **Annotation persistence**: JSONL (simple) vs struct serialization (binary, faster).

## Naming Conventions

Prefer **camelCase** everywhere — file names and code identifiers, in both MetaScript and C.

- **File names**: camelCase — `terminal.ms`, `terminalVirtual.ms`, `terminalPosix.cms`. The platform suffix is camelCase too (`Posix` / `Windows` / `Virtual`), never `snake_case`.
- **Types** (interface, struct, class, enum): PascalCase — `Terminal`, `TermSize`, `VirtualTerminal`.
- **Functions, fields, locals**: camelCase — `newVirtualTerminal`, `enterRaw`.
- **C code**: camelCase for symbols we own (companion `.c` helpers, exported names). External symbols we don't own — libc (`tcgetattr`, `ioctl`), kernel32 (`SetConsoleMode`) — keep their real names; that snake_case is the only sanctioned fallback, forced by the platform API.

## Git Rules

NEVER commit without asking first. Before any `git commit`, present the plan — the file list and the exact commit message(s) — and wait for explicit approval. Review happens together, before the commit, not after. This holds even during `/split-commit`: propose the split, then stop.

NEVER push without asking.

NEVER use `git stash`, `git reset`, `git checkout .`, `git restore`, or any command that discards working tree state.

## Conversational Style

- Short, direct answers
- No emojis in commits or code
- Answer questions before making edits
- Technical prose only
