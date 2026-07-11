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
│   ├── render/                  ← Terminal rendering engine (ported from Vimcraft)
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

### Layer model (from Vimcraft)

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
# Build native binary
msc build src/main.ms --target=c --output=haro

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

- **Vimcraft** ([github.com/vimcraft-labs/vimcraft](https://github.com/vimcraft-labs/vimcraft)): the Zig + Hermes predecessor. Rendering engine, compositor, buffer ops are ported from here. Local reference at `~/metascript/vimcraft`.
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

## Open Design Questions

- **Raiser VM readiness**: is it stable enough to host plugins? Need to verify API surface before Phase 6.
- **Terminal raw I/O**: MetaScript stdlib needs termios bindings (raw mode, winsize). May need to contribute to recompiler stdlib.
- **SSE parsing**: provider streaming needs Server-Sent Events parser. Not in MetaScript stdlib yet.
- **Buffer data structure**: rope (like Vimcraft Zig) or gap buffer or piece table? Rope is proven but complex.
- **Annotation persistence**: JSONL (simple) vs struct serialization (binary, faster).

## Git Rules

NEVER use `git stash`, `git reset`, `git checkout .`, `git restore`, or any command that discards working tree state.

## Conversational Style

- Short, direct answers
- No emojis in commits or code
- Answer questions before making edits
- Technical prose only
