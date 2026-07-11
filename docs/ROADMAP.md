# Haro Roadmap

## Context

Haro is a coding agent built in MetaScript. The reference project is [pi](https://github.com/earendil-works/pi-mono) (~128K LOC TypeScript, 5 packages). We are NOT doing a 1:1 port — we're redesigning around MetaScript's unique capabilities.

### What pi has that we adapt

| pi package | LOC | What it does | Haro equivalent |
|---|---|---|---|
| `pi-ai` | ~39K | 30+ LLM providers, auth, streaming | `provider/` — Anthropic first, std/http direct |
| `pi-agent-core` | ~10K | agent loop, tool exec, streaming | `agent.ms` — AgentActor |
| `pi-coding-agent` | ~55K | CLI, tools, sessions, extensions | `tools/`, `session.ms`, `main.ms` |
| `pi-tui` | ~19K | terminal UI, differential render | Neon terminal backend |
| `orchestrator` | ~3.5K | multi-agent coordination | Future |

### What we do differently

| Aspect | pi (TypeScript) | Haro (MetaScript) |
|---|---|---|
| Distribution | npm install + Node.js | Single binary, zero deps |
| Memory | V8 GC | DRC deterministic |
| Tool execution | Promise.all, shared state | Actor isolation, message passing |
| Error handling | throw/catch, untyped | `Promise<Result<T,E>>`, typed |
| Provider SDKs | 30+ npm packages | std/http direct, hand-written |
| TUI | pi-tui (custom string[] renderer) | Neon terminal backend (in design) |

---

## Phase Plan

### Phase 0: Foundation (current)

**Goal**: Set up project, define types, prove the architecture works end-to-end.

- [x] Project repo, git, AGENTS.md
- [ ] `provider/types.ms` — core types (Model, Context, Message, ToolCall, ToolResult, StreamEvent)
- [ ] `provider/anthropic.ms` — Anthropic streaming API client via std/http
- [ ] `agent.ms` — AgentActor: conversation loop, LLM stream consumption, tool dispatch
- [ ] `tools/read.ms` — file read tool
- [ ] `tools/bash.ms` — subprocess execution tool
- [ ] `tools/write.ms` — file write tool
- [ ] `tools/edit.ms` — find-replace edit tool
- [ ] `main.ms` — CLI entry, simple stdin/stdout REPL (no TUI yet)
- [ ] `system-prompt.ms` — AGENTS.md loader, basic prompt builder

**Milestone**: `./haro -p "list files in src/"` works end-to-end. LLM can read files and run bash.

### Phase 1: Terminal UI

**Goal**: Interactive TUI with streaming output, editor, message history.

**Blocked on**: Neon terminal backend design decision (see below).

- [ ] Neon terminal backend implemented
- [ ] Message list component (scrollable, markdown)
- [ ] Editor component (multi-line, autocomplete)
- [ ] Footer (model, token usage, cost)
- [ ] Streaming text display (incremental render)

**Milestone**: `./haro` drops into an interactive session with streaming responses and tool output.

### Phase 2: Session Persistence

- [ ] JSONL session format
- [ ] Session tree with branching (parentId pointers)
- [ ] `/resume`, `/new`, `/tree` commands
- [ ] Compaction for long sessions

### Phase 3: Multi-Provider

- [ ] OpenAI provider (openai-responses API)
- [ ] Google provider (google-generative-ai API)
- [ ] Model selector UI
- [ ] Cross-provider message transformation

### Phase 4: Extensibility

- [ ] Extension system (custom tools, commands)
- [ ] Skills (on-demand capability packages)
- [ ] Prompt templates
- [ ] Theme support

### Phase 5: Advanced

- [ ] OAuth (Claude Pro, ChatGPT Plus)
- [ ] Session export/import
- [ ] RPC mode for editor integration
- [ ] More tools (grep, find, glob, ls)

---

## Key Design Decisions

### 1. Actor model for tools

Each tool is an actor — isolated state, crash-safe. The agent dispatches tool calls via message passing.

```
AgentActor
  ├── sends: { toolCallId, name, args }
  ├── receives: { toolCallId, result }
  └── tools run independently — one tool crashing doesn't crash the agent
```

**Why**: In pi, tool crashes propagate through Promise chains and can kill the whole run. Actor isolation means a bash tool crash is recoverable.

**Tradeoff**: More ceremony than a function call. Worth it for robustness.

### 2. `Promise<Result<T,E>>` for LLM calls

No throw/catch in async paths. LLM streaming returns `Promise<Result<StreamEvent, ProviderError>>`. Use `try await` to unwrap.

**Why**: Typed errors mean the compiler enforces error handling. No surprise rejections. `try await provider.stream(...)` either returns a value or early-returns a typed error.

### 3. std/http for provider APIs

No npm SDK packages. Provider implementations use `std/http` directly — build the request, parse SSE stream, emit events.

**Why**: Zero deps = single binary. Also, provider SDKs are thin wrappers over HTTP anyway. We control the streaming, error handling, and timeout behavior.

### 4. Neon for TUI

UI lives in Neon (`~/metascript/neon`), not in haro. haro imports Neon components.

**Why**: Neon already has reactivity (signals, effects), VNode tree, reconciler, and Host abstraction. Adding a terminal backend to Neon benefits all Neon users, not just haro.

---

## Open Design Questions

### Terminal backend for Neon

**The big question**: How does Neon render to terminal?

Neon's 3-layer model:
- Layer A (Reconcile): VNode tree → host node mutations — **Neon owns, already built**
- Layer B (Paint): host nodes → pixels/characters — **platform-specific**
- Layer C (GPU/output): actual rendering — **platform-specific**

For terminal, Layer B+C = "host node tree → ANSI string[] → stdout".

Three approaches under consideration:

| | A: VNode-first (Host adapter) | B: Reactive string[] (pi-tui style) | C: Hybrid |
|---|---|---|---|
| **Throughput** | JSX → VNode → reconcile → TerminalNode → paint → string[] | signal → effect → component.render(width) → string[] | mixed |
| **Code sharing** | Max — same JSX for browser + terminal | Min — terminal UI code is separate | Partial |
| **Layout** | Needs terminal layout engine | Each component wraps manually | VNode for simple, manual for complex |
| **Terminal fit** | Poor — terminal has no real nesting/GPU | Good — string[] is native terminal output | Medium |
| **Complexity** | High — layout engine, reconcile in terminal | Low — proven by pi-tui | Medium |
| **Reactivity** | Neon reconciler drives updates | Neon signals drive re-render | Both |

**Status**: Brainstorming. Need to decide before Phase 1.

**Key insight**: Haro's UI components (MessageList, Editor, Footer, SelectList) are very terminal-specific. Editor and SelectList are hard to express as generic VNodes. This favors B or C.

**Key counter-insight**: If Neon wants terminal as a first-class platform (not just for haro), the VNode-first approach (A) gives the most long-term value — same code runs on browser, iOS, terminal.

### Tool execution model

**Question**: Actors (Erlang-style, message passing) vs spawn (thread pool, Promise-based)?

Both are available in MetaScript. Actors give isolation + supervision but add message-passing overhead. spawn is simpler but shares process state.

**Leaning**: Actors for tools (isolation is valuable), spawn for internal parallelism (e.g., concurrent file reads within a single tool).

**Status**: Defer until Phase 0 proves the basic loop works. Start with simple async functions, promote to actors when we hit the isolation need.

### Session format

**Question**: JSONL (pi-compatible) vs MetaScript struct serialization (binary)?

JSONL is human-readable, pi-compatible, easy to debug. Struct serialization is faster but opaque.

**Leaning**: JSONL first (debugging + pi compat), consider binary later if performance matters.

---

## Reference: pi's Architecture

For context when designing haro's counterparts.

### pi message flow

```
User types prompt
  → coding-agent sends to agent
    → agent sends to ai provider
      → ai calls LLM API (streaming SSE)
        → LLM returns text + tool calls
      → ai parses stream into events
    → agent dispatches tool calls
      → tools execute (read/write/bash/edit)
    → agent collects tool results
    → agent sends results back to LLM
  → coding-agent renders output to TUI
```

### pi's tool execution

```
AgentMessage[] → transformContext() → convertToLlm() → Message[] → LLM
```

Events: `agent_start` → `turn_start` → `message_start` → `message_update` (streaming) → `message_end` → `tool_execution_start` → `tool_execution_end` → `turn_end` → `agent_end`

### pi's TUI approach

Each component implements `render(width: number): string[]`. Differential rendering compares line arrays frame-to-frame, only outputs changed lines. Synchronized output (`\x1b[?2026h ... \x1b[?2026l`) for flicker-free updates.

This is **Option B** (reactive string[]) in our terminal backend question — pi-tui already proves it works.

---

## MetaScript stdlib availability

What we need vs what exists:

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
