# Haro — MetaScript Coding Agent

> "Haro Haro, build complete!"

A small, friendly coding agent built in MetaScript. Inspired by the Haro units from Gundam 00 — compact, capable, and chatty enough to never feel boring.

Not a clone of [pi](https://github.com/earendil-works/pi-mono) — redesigned around MetaScript's strengths: actor model, DRC memory, native binary, `Result<T,E>` error handling.

## Identity

**Name**: Haro (ガンダム00のハロ). Small, round, loyal companion robot. Says "Haro Haro!" a lot.

**What**: Interactive coding agent CLI — talk to an LLM, it reads/writes/runs code on your machine.

**Personality**: Friendly and talkative. Announces actions and completions with short, cheerful status lines ("Haro Haro, read 3 files!", "Haro thinks this needs a fix..."). Chatty to stay engaging, never spammy — one line per action, never walls of text.

**Target**: Single native binary, zero runtime dependencies. `scp haro server:~` and it works.

**Why MetaScript**: DRC (no GC pauses), actors (tool isolation), `Promise<Result<T,E>>` (typed errors), single-binary distribution.

## Architecture

```
haro/
├── src/
│   ├── main.ms              ← entry: parse args, boot AgentActor
│   ├── agent.ms             ← AgentActor: conversation loop, LLM calls, tool dispatch
│   ├── provider/
│   │   ├── types.ms         ← Model, Context, Message, ToolCall, ToolResult
│   │   └── anthropic.ms     ← Anthropic streaming API via std/http
│   ├── tools/
│   │   ├── read.ms          ← file read tool
│   │   ├── write.ms         ← file write tool
│   │   ├── bash.ms          ← subprocess execution tool
│   │   └── edit.ms          ← find-replace edit tool
│   ├── session.ms           ← JSONL session persistence
│   └── system-prompt.ms     ← AGENTS.md loader, prompt builder
├── AGENTS.md                ← this file
└── build.ms                 ← MetaScript build config
```

UI lives in Neon (`~/metascript/neon`), not here. haro imports Neon components for terminal rendering once the terminal backend is ready.

## Design Principles

1. **Actor model** — each tool is an actor (isolated state, crash-safe). The agent loop is an actor. Communication via message passing.

2. **`Promise<Result<T,E>>`** — LLM calls return typed errors. No throw/catch in async paths. Use `try await` to unwrap.

3. **Native binary first** — C backend is primary. JS backend is secondary (for testing/dev only).

4. **Thin layers** — provider/ knows HTTP + provider API. agent/ knows conversation loop. tools/ knows file/process I/O. No cross-layer leakage.

5. **No npm dependencies** — std/http for API calls, std/json for serialization, std/fs for files, std/process for bash tool.

## Provider Abstraction

```
Context { systemPrompt, messages[], tools[] }
    │
    ▼
provider.stream(model, context) → AsyncIterator<StreamEvent>
    │
    ▼
StreamEvent: text_delta | toolcall_start | toolcall_end | done | error
```

Phase 1: Anthropic only.
Phase 2: OpenAI, Google.
Phase 3: OAuth (Claude Pro, ChatGPT Plus).

## Tool Interface

```typescript
interface Tool {
    name: string;
    description: string;
    parameters: JsonSchema;
    execute: (args: unknown, signal: AbortSignal) => Promise<ToolResult>;
}

interface ToolResult {
    content: ContentBlock[];
    isError: boolean;
}
```

Tools are actors — `execute` is a CALL (request/reply). The agent dispatches tool calls, tools run in isolation.

## Build & Run

```bash
# Build native binary
msc build src/main.ms --target=c --output=haro

# Run
./haro                          # interactive mode
./haro -p "list files"          # print mode (non-interactive)

# Test
msc test src/
```

## Dependencies

- **MetaScript stdlib**: `std/http`, `std/json`, `std/fs`, `std/process`, `std/io`, `std/os`
- **Neon** (`~/metascript/neon`): UI components + terminal rendering (when available)
- **MetaScript compiler** (`~/metascript/recompiler`): invoked via `msc` CLI in `$PATH`

## Related Projects

- **pi** (`~/projects/pi`): the project being cloned/adapted. Reference for UX, tool design, provider patterns.
- **Neon** (`~/metascript/neon`): UI framework — haro's TUI layer. Terminal backend in design.
- **recompiler** (`~/metascript/recompiler`): the language and compiler. If haro hits a compiler limitation, fix it there.

## Session Format

JSONL with tree structure (like pi). Each line: `{ id, parentId, role, content, timestamp }`. Branching via parentId pointers — no file duplication.

## Phase Plan

| Phase | Goal | Status |
|-------|------|--------|
| 1 | Anthropic provider + 4 tools + REPL | Pending |
| 2 | Neon terminal UI | Blocked on terminal backend design |
| 3 | Session persistence, branching | Pending |
| 4 | More providers (OpenAI, Google) | Pending |
| 5 | Extensions, skills | Future |

## Open Design Questions

- **Terminal backend for Neon**: VNode-first (Host adapter) vs reactive string[] (pi-tui style) vs hybrid. See Neon brainstorm.
- **Tool execution model**: actors (Erlang-style) vs spawn (thread pool). Both are available in MetaScript.
- **Session format**: JSONL (pi-compatible) vs MetaScript struct serialization (binary, faster).

## Git Rules

NEVER use `git stash`, `git reset`, `git checkout .`, `git restore`, or any command that discards working tree state.

## Conversational Style

- Short, direct answers
- No emojis in commits or code
- Answer questions before making edits
- Technical prose only
