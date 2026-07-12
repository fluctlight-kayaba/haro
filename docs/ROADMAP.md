# Haro Roadmap

## Context

Haro is a terminal code platform for AI workflows, built in MetaScript. Three core design sources:

- **Vimcraft** (Zig + Hermes) — rendering engine, multi-layer compositor, buffer ops, terminal I/O
- **pi** (TypeScript/Node.js) — agent loop design, provider abstraction, tool dispatch, session format
- **Neovim** — plugin philosophy, small core + powerful plugins

Not a 1:1 port of any of them — Haro merges their best ideas into one platform designed from the ground up for AI-assisted coding.

### What we adapt from each source

| Source | What we take | Haro equivalent |
|---|---|---|
| Vimcraft | Multi-layer compositor, display/cursor tracking, rope buffer, terminal raw I/O | `src/render/`, `src/input/` |
| pi | Agent loop, provider abstraction, tool dispatch, JSONL session format | `src/agent/` |
| Neovim | Small core + Raiser VM plugins, `haro.*` API, extensible defaults | `src/plugin/`, `src/defaults/` |
| Lumen | Diff viewer UX, annotation flow | `src/defaults/diff.ms`, `src/defaults/annotate.ms` |

### What we do differently

| Aspect | pi (TypeScript) | Vimcraft (Zig) | Haro (MetaScript) |
|---|---|---|---|
| Distribution | npm + Node.js | Zig binary | Single binary, zero deps |
| Memory | V8 GC | Manual + allocators | DRC deterministic |
| Tool execution | Promise.all, shared state | N/A | Actor isolation, message passing |
| Error handling | throw/catch, untyped | Zig errors | `Promise<Result<T,E>>`, typed |
| Plugin system | TS extensions | Hermes JSI | Raiser VM (TypeScript, native) |
| Rendering | pi-tui (string[] renderer) | Multi-layer compositor | Free-canvas compositor (ported from Vimcraft) |
| Provider SDKs | 30+ npm packages | N/A | std/http direct, hand-written |

---

## Phase Plan

### Phase 0: Foundation (current)

**Goal**: Project setup, define architecture, AGENTS.md, ROADMAP.

- [x] Project repo, git, AGENTS.md
- [x] ROADMAP.md
- [ ] Begin Phase 1

### Phase 1: Rendering Engine (ported from Vimcraft)

**Goal**: Terminal rendering works — compositor, display, buffer, input. The canvas can render text, layers, dirty-flag recomposition.

- [ ] `src/input/terminal.ms` — raw mode (termios), terminal size, resize detection
- [ ] `src/input/keys.ms` — key event parsing, basic vim nav (j/k, gg/G, search)
- [ ] `src/render/buffer.ms` — rope-based text buffer (read-heavy, review-optimized)
- [ ] `src/render/display.ms` — ANSI output, synchronized updates, cursor tracking
- [ ] `src/render/compositor.ms` — multi-layer compositing, dirty flags per layer
- [ ] Render a file to terminal, navigate with j/k

**Milestone**: Open a file in Haro, see rendered text with line numbers, navigate with vim keys.

**May need**: termios bindings in MetaScript stdlib (contribute to recompiler if missing).

### Phase 2: Agent Core (adapted from pi)

**Goal**: LLM communication works — Anthropic provider, tools, conversation loop. Agent can read files and run bash.

- [ ] `src/agent/provider/types.ms` — Model, Context, Message, ToolCall, ToolResult, StreamEvent
- [ ] `src/agent/provider/anthropic.ms` — Anthropic streaming API via std/http
- [ ] `src/agent/tools/read.ms` — file read tool
- [ ] `src/agent/tools/bash.ms` — subprocess execution tool
- [ ] `src/agent/tools/write.ms` — file write tool
- [ ] `src/agent/tools/edit.ms` — find-replace edit tool
- [ ] `src/agent/loop.ms` — conversation loop, LLM stream consumption, tool dispatch
- [ ] `src/agent/session.ms` — JSONL session persistence
- [ ] `src/defaults/system-prompt.ms` — AGENTS.md loader, prompt builder

**May need**: SSE parser in MetaScript (contribute to recompiler stdlib if missing).

**Milestone**: `./haro -p "list files in src/"` works. LLM reads files, runs bash, responds.

### Phase 3: Basic TUI (rendering + agent, end-to-end)

**Goal**: Interactive mode. Agent output rendered on the free-canvas compositor, vim navigation, streaming text.

- [ ] `src/main.ms` — CLI entry, mode dispatch (interactive, print, diff)
- [ ] Agent output → compositor layer (streaming text display)
- [ ] Basic message/conversation view on canvas
- [ ] Footer (model, token usage, cost)
- [ ] Input line (prompt entry)

**Milestone**: `./haro` drops into interactive session. Type a prompt, see streaming response on canvas.

### Phase 4: Diff Viewer Plugin

**Goal**: Side-by-side diff viewer as a default plugin. Agent changes visible as diffs.

- [ ] `src/defaults/diff.ms` — parse git diff into structured hunks
- [ ] Side-by-side rendering on compositor (diff layer)
- [ ] `./haro diff` mode
- [ ] `./haro diff HEAD~1` — specific commit
- [ ] Diff-specific nav (jump between hunks with `{/}`)

**Milestone**: `./haro diff` shows side-by-side diff with syntax highlighting.

### Phase 5: Annotation Plugin (bidirectional)

**Goal**: Human↔Agent annotation on diffs. Both sides can annotate, annotations persist, tagged by author.

- [ ] `src/defaults/annotate.ms` — annotation types, persistence (JSONL)
- [ ] Annotate selection/hunk/file (press `i`)
- [ ] View all annotations (press `I`)
- [ ] Agent can pre-seed annotations (programmatically)
- [ ] Annotation gutter indicators (▍) on compositor
- [ ] Send annotations to agent as next prompt (press `s`)

**Milestone**: Agent makes changes, human opens diff, annotates feedback, agent reads and fixes.

### Phase 6: Raiser Plugin System

**Goal**: Third-party plugins via Raiser VM. `haro.*` API for buffers, events, agent, annotation.

- [ ] `src/plugin/host.ms` — plugin lifecycle, sandboxing
- [ ] `src/plugin/api.ms` — haro.* API surface
- [ ] Plugin discovery (`~/.haro/plugins/`, `.haro/plugins/`)
- [ ] Hot reload

**Blocked on**: Raiser VM readiness (verify API surface).

**Milestone**: Write a plugin that adds a custom tool or command.

### Phase 7: Session Persistence

- [ ] JSONL session format (tree structure, parentId branching)
- [ ] `/resume`, `/new`, `/tree` commands
- [ ] Compaction for long sessions
- [ ] Session export/import

### Phase 8: Multi-Provider

- [ ] OpenAI provider (openai-responses API)
- [ ] Google provider (google-generative-ai API)
- [ ] Model selector UI
- [ ] Cross-provider message transformation

### Phase 9: Advanced

- [ ] Tree-sitter syntax highlighting
- [ ] OAuth (Claude Pro, ChatGPT Plus)
- [ ] RPC mode for process integration
- [ ] More tools (grep, find, glob, ls)
- [ ] Skills (on-demand capability packages)
- [ ] Theme support

---

## Key Design Decisions

### 1. Free-canvas compositor (from Vimcraft)

Multi-layer compositor — each concern is a separate layer (base text, gutter, diff, annotation, cursor, overlay). Dirty flags per layer, only recomposite what changed.

**Why**: Not locked to "editor with lines of text." The canvas renders code, diffs, annotations, agent output, custom plugin UI. Plugins add layers — they don't fight for screen space.

### 2. Actor model for tools

Each tool is an actor — isolated state, crash-safe. The agent dispatches tool calls via message passing.

**Why**: In pi, tool crashes propagate through Promise chains and can kill the whole run. Actor isolation means a bash tool crash is recoverable.

### 3. `Promise<Result<T,E>>` for LLM calls

No throw/catch in async paths. LLM streaming returns typed results. Use `try await` to unwrap.

**Why**: Typed errors mean the compiler enforces error handling. No surprise rejections.

### 4. Raiser VM for plugins

Plugins in TypeScript, run on Raiser VM. Same model as Neovim's Lua, but TypeScript.

**Why**: We own MetaScript + Raiser — can fix any limitation. No external JS engine (Hermes), no C++ bridge. Plugins get native-grade performance.

### 5. Rendering in-core

Haro's rendering engine is ported from Vimcraft, living in `src/render/`.

**Why**: Haro needs a terminal-native compositor optimized for code review/diff/annotation. Vimcraft's multi-layer compositor is purpose-built for this — dirty flags per layer, cell-level diff, synchronized output. Terminal is a 2D grid, not a nested UI tree; no layout engine or reconciler needed.

---

## Open Design Questions

- **Raiser VM readiness**: is it stable enough to host plugins? Need to verify API surface before Phase 6.
- **Terminal raw I/O**: MetaScript stdlib needs termios bindings (raw mode, winsize). May need to contribute to recompiler stdlib.
- **SSE parsing**: provider streaming needs Server-Sent Events parser. Not in MetaScript stdlib yet.
- **Buffer data structure**: rope (like Vimcraft Zig). Decided — proven, O(log n) edits, refcounted node sharing for undo. See VIMCRAFT-DELTA.md for why DRC makes rope node sharing cheaper than Zig's manual refcounting.
- **Annotation persistence**: JSONL (simple) vs struct serialization (binary, faster).
- **Tool execution model**: start with simple async functions, promote to actors when isolation need arises.

---

## MetaScript stdlib availability

| Need | Status | Module |
|---|---|---|
| HTTP client (LLM API calls) | Ready | `std/http` — HttpClient, request, TLS, redirects |
| JSON parse/stringify | Ready | `std/core/json` — `JSON.parse<T>`, typed decode |
| File I/O (read/write/edit tools) | Ready | `std/fs` — readFile, writeFile, glob, path |
| Process exec (bash tool) | Ready | `std/process` — exec, spawn, capture stdout/stderr |
| WebSocket (some providers) | Ready | `std/core/websocket` — client, frames, handshake |
| Async streaming | Ready | `async/await`, `Promise<T>`, `spawn`, actors |
| Crypto (auth, hashing) | Ready | `std/crypto`, `std/hash` |
| Terminal raw I/O | **Missing** | Need: termios (raw mode), winsize query, non-blocking read |
| SSE parsing | **Missing** | Need: SSE event parser for provider streaming |

**Gaps**: Terminal raw I/O and SSE parsing need to be built (either in haro or contributed to MetaScript stdlib).

---

## Vimcraft Delta: What MetaScript Changes

See [`docs/VIMCRAFT-DELTA.md`](./VIMCRAFT-DELTA.md) for the full analysis. Summary:

- **JSI bridge disappears**: No Hermes, no C++ bridge, no HostObject, no StaticStringMap. Raiser VM runs MetaScript natively. ~4000 LOC glue code eliminated.
- **Allocators disappear**: DRC handles memory. `struct Cell` is stack-allocated, zero RC overhead on the rendering hot path.
- **Closures replace function pointers**: Event handlers, renderers, callbacks are arrow functions with natural scope capture — no context structs.
- **Macros enable compile-time generation**: Tool schemas, system prompt assembly, session serialization — all baked into the binary at compile time.
- **Actors give tool isolation for free**: Crash-safe tools via built-in actor model (impossible in Zig without building a runtime).
- **`Promise<Result<T,E>>` gives typed async errors**: Compiler-enforced, no throw/catch in async paths.

The algorithms (compositor, diff, rope, ANSI optimization) port directly. What changes is everything around them.
