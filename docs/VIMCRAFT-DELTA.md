# Vimcraft → Haro: MetaScript Delta

What changes when porting Vimcraft's architecture from Zig to MetaScript. Two layers: **what disappears** (JSI bridge, allocator plumbing) and **what MetaScript enables** that Zig couldn't do.

---

## 1. JSI → Raiser: The Bridge Disappears

Vimcraft's biggest complexity center is the **Hermes JSI bridge** — a C++ layer connecting the Zig core to the Hermes JavaScript engine for plugin/config support.

### What Vimcraft built

| Component | LOC estimate | Purpose |
|-----------|-------------|---------|
| `hermes_c_api.cpp` | ~500+ lines C++ | C++ bridge between Zig and Hermes C API |
| `host_object_builder.zig` | ~300 lines | HostObject pattern for zero-copy JS↔native calls |
| `StaticStringMap` dispatch | ~100 lines | O(1) property dispatch via compile-time perfect hash (168ns/call) |
| 40+ `*_api.zig` files | ~3000+ lines total | API surface registration (`motion_api`, `config_api`, `buffer_api`, `layer_api`, etc.) |
| Vendor Hermes binaries | 287 MB | Prebuilt JS engine (DO NOT TOUCH) |

**Total**: ~4000 lines of glue code + 287 MB vendored binary, just to let plugins call native code.

### Why Haro doesn't need any of it

MetaScript IS the language. Raiser VM runs MetaScript natively. There is no "two-language problem":

```
Vimcraft:  Zig core ←C++ bridge← Hermes JS engine ←JS→ plugin code
Haro:      MetaScript core ←direct call→ Raiser VM ←MetaScript→ plugin code
```

| Vimcraft concern | Haro equivalent | Status |
|-----------------|----------------|--------|
| Hermes JS engine | Raiser VM (built into MetaScript runtime) | Gone — no vendored binary |
| C++ bridge (`hermes_c_api.cpp`) | Not needed — same language | Gone |
| HostObject pattern | Direct function calls | Gone |
| StaticStringMap O(1) dispatch | Compile-time monomorphization (calls are direct C functions after codegen) | Gone — zero dispatch overhead |
| 40+ API registration files | `haro.*` is just a MetaScript module with exports | ~1 file, no registration boilerplate |
| Serialization across language boundary | Same types, same memory layout | Gone |

### What this means for the `haro.*` API

Vimcraft's plugin API requires each method to be individually registered as a JSI HostObject property, with manual marshaling of arguments and return values across the Zig↔JS boundary.

Haro's API is just:

```typescript
// src/plugin/api.ms — this IS the entire API surface
export namespace haro {
    export function bufferOpen(path: string): Result<Buffer, string> { ... }
    export function agentOnToolCall(cb: (tool: string, args: unknown) => void): void { ... }
    export function annotateAdd(ann: Annotation): void { ... }
    // ...
}
```

Plugins import and call directly. No registration, no marshaling, no HostObject, no perfect hash. The compiler handles everything at compile time.

---

## 2. Allocators → DRC: Memory Management Simplified

### Vimcraft (Zig)

Every function that allocates memory takes an `allocator: std.mem.Allocator` parameter. Buffer, rope, grid, compositor, layer — all require explicit allocator threading:

```zig
pub fn init(allocator: std.mem.Allocator) !ScreenGrid { ... }
pub fn composite(self: *Compositor, allocator: std.mem.Allocator) !void { ... }
```

This is verbose and error-prone. Wrong allocator = use-after-free or double-free.

### Haro (MetaScript)

DRC (Deterministic Reference Counting) handles everything automatically:

- **`interface` / `class`** → heap-allocated, reference-counted, automatic lifecycle
- **`struct`** → stack-allocated value type, zero RC overhead, for hot-path cells
- **`move`** → zero-cost ownership transfer when you need it
- **`defer`** → scope-exit cleanup for non-RC resources (file handles, terminals)

No allocator parameter anywhere. The compiler inserts incref/decref/destroy calls automatically.

### Rendering grid — the sweet spot

The rendering grid's `Cell` is a perfect `struct` candidate — small, value-type, stack-allocated, no RC overhead:

```typescript
struct Cell {
    char: u21;
    fg: uint32;     // packed RGB
    bg: uint32;
    attrs: uint8;   // bold | italic | underline
    is_wide: boolean;
}

// ScreenGrid is just an array of structs — no heap per cell, no RC
struct ScreenGrid {
    width: int32;
    height: int32;
    cells: Cell[];      // current frame
    prev: Cell[];       // previous frame (for diff)
    offsets: int32[];   // line-offset indirection (O(1) scroll)
}
```

In Vimcraft, `Cell` is a heap-allocated Zig struct with manual alloc/free. In Haro, it's a stack value — the compiler auto-selects `const Cell*` (zero-copy) or `Cell` (value) based on size and mutation analysis.

---

## 3. Function Pointers → Closures

Zig has **no closures**. Every callback is a manual function-pointer-plus-context pattern:

```zig
// Vimcraft: callback registration
const RenderCallback = struct {
    fn: *const fn(ctx: *anyopaque, viewport: ViewportState) void,
    ctx: *anyopaque,
};
```

MetaScript has **native closures, arrow functions, and async/await**:

```typescript
// Haro: same thing, one line
type RenderCallback = (viewport: ViewportState) => void;

// And it captures scope naturally:
function registerDiffRenderer(compositor: Compositor): void {
    const baseLayer = compositor.getLayer(0);
    compositor.register(300, (vp: ViewportState) => {
        // baseLayer is captured — no manual context struct
        renderDiff(baseLayer, vp);
    });
}
```

This eliminates an entire class of boilerplate: context structs, vtable wiring, manual lifetime management for callback contexts.

### Event handling

Vimcraft's event system uses tagged unions + switch dispatch. Haro uses discriminated unions + match:

```typescript
type EditorEvent =
    | { kind: "cursor_moved"; row: int32; col: int32 }
    | { kind: "viewport_scrolled"; top: int32 }
    | { kind: "buffer_saved"; path: string }
    | { kind: "agent_response"; text: string };

function handleEvent(e: EditorEvent): void {
    match (e.kind) {
        "cursor_moved" => updateCursor(e.row, e.col),
        "viewport_scrolled" => compositor.markDirty(200),
        "buffer_saved" => gutter.updateSigns(e.path),
        "agent_response" => agentLayer.appendText(e.text),
    }
}
```

The compiler enforces exhaustiveness — missing an arm is a compile error. No runtime "unhandled event" bugs.

---

## 4. Macros: Compile-Time Code Generation

MetaScript macros run in the Raiser VM at compile time, manipulating the compiler's own typed AST. Three areas where this is powerful for Haro:

### 4a. Tool schema generation

Agent tools need JSON schemas for the LLM. Vimcraft would hand-write these. Haro can generate from type annotations at compile time:

```typescript
macro deriveToolSchema(toolDef: Node): Node {
    // Walk the function signature, generate JSON schema for parameters
    // Returns a const schema string baked into the binary
}

@deriveToolSchema
function readFile(path: string): Result<string, string> { ... }
// → generates: const readFileSchema = '{"name":"readFile","params":{...}}';
```

### 4b. System prompt assembly

System prompts are built from AGENTS.md + tool descriptions + context. This can be a compile-time assembly:

```typescript
const SYSTEM_PROMPT = @comptime {
    const agents = readFile("AGENTS.md");
    const tools = collectToolSchemas();
    return buildSystemPrompt(agents, tools);
};
```

Zero runtime cost — the prompt string is baked into the binary.

### 4c. Session serialization

Session format (JSONL with tree structure) has boilerplate per-line. A macro can generate the serialization/deserialization code from the message type:

```typescript
macro deriveSessionFormat(msgType: Node): Node {
    // Generate toJSON/fromJSON for the message type
}
```

---

## 5. Actors: Built-In Tool Isolation

Vimcraft has no actor model — tool crashes propagate through the call stack.

MetaScript has **first-class actors** with isolated state and message passing:

```typescript
actor BashTool {
    private cwd: string;

    exec(cmd: string): Promise<Result<string, ToolError>> {
        // Runs in isolation — crash doesn't kill the agent loop
        const result = try await Process.exec(cmd, { cwd: this.cwd });
        return Result.ok(result.stdout);
    }
}

// Agent loop dispatches via message passing
const bashTool = new BashTool();
const output = try await bashTool.exec("ls -la");
// If bashTool crashes, the agent loop survives — supervisor restarts the actor
```

This is design principle #6 (Actor model) from AGENTS.md, and it's **impossible in Zig** without building a full actor runtime from scratch. MetaScript gives it for free: supervision, restart strategies (OneForOne, OneForAll), links, monitors — all built-in.

---

## 6. `Promise<Result<T,E>>`: Typed Async Errors

Vimcraft uses Zig errors (error unions). Each call site must handle or propagate:

```zig
const result = try terminal.init(); // Zig error union
```

Haro uses `Promise<Result<T,E>>` — async errors are typed, and the compiler enforces handling:

```typescript
async function streamResponse(msg: Message): Promise<Result<string, ProviderError>> {
    // throw is BANNED in this function — compile error
    const resp = try await anthropic.stream(msg);  // unwrap or early-return error
    return Result.ok(resp.text);
}

// Caller:
const text = try await streamResponse(msg);  // unwrap or propagate
const text = try await streamResponse(msg) catch "fallback";  // unwrap with fallback
```

No untyped rejections. No surprise exceptions. The compiler enforces two rules:
1. **V1**: No `throw` inside async functions returning `Promise<Result<T,E>>`
2. **V2**: No bare `await` on plain `Promise<T>` without `try...catch` guard

---

## 7. String ↔ Bytes Zero-Copy

Terminal I/O and SSE parsing both need string↔bytes conversion. In most languages this is a copy. In MetaScript, `string` and `uint8[]` share identical memory layout — `.asBytes()` and `.asString()` are zero-cost bit-casts.

```typescript
// Terminal read → string processing, zero copy
const raw: uint8[] = terminal.read();
const text: string = raw.asString();  // bit-cast, 0 cycles

// SSE parsing
const chunk: uint8[] = await http.readChunk();
const events = parseSSE(chunk.asString());  // zero-copy into parser
```

This matters for the rendering pipeline — every frame reads terminal state and writes ANSI escape codes. Zero-copy string ops eliminate a per-frame allocation that Vimcraft doesn't have to worry about (Zig's `[]const u8` is already zero-copy) but that would be a real cost in any other language.

---

## 8. C Interop via Directives

MetaScript needs C bindings for termios (raw mode, terminal size). Instead of a separate build system, this is inline:

```typescript
@include("termios.h");
@passC("-D_POSIX_C_SOURCE=200809L");

extern function tcgetattr(fd: int32, termios: Ptr<Termios>): int32;
extern function tcsetattr(fd: int32, actions: int32, termios: Ptr<Termios>): int32;
extern function ioctl(fd: int32, request: uint64, ...args: unknown[]): int32 from "ioctl";
```

The directives emit `#include` and compiler flags directly into the generated C. No separate CMakeLists, no build.rs, no Makefile glue. Build config is `build.ms` — MetaScript evaluated by the Raiser VM.

---

## Summary: Porting Translation Table

| Vimcraft (Zig) | Haro (MetaScript) | Advantage |
|----------------|-------------------|-----------|
| Hermes JSI bridge (~4000 LOC) | Raiser VM (built-in) | -4000 LOC glue code, -287MB binary |
| `allocator: Allocator` everywhere | DRC automatic | No allocator threading |
| Heap-allocated Cell structs | `struct Cell` (value type, stack) | Zero RC overhead on hot path |
| Function pointer + context struct | Arrow function closures | Natural scope capture |
| Tagged union + switch | Discriminated union + match | Compile-time exhaustiveness |
| Hand-written tool schemas | `@deriveToolSchema` macro | Compile-time generation |
| Runtime system prompt assembly | `@comptime` prompt builder | Zero runtime cost |
| No isolation (crash propagation) | `actor Tool { ... }` | Built-in crash safety |
| Zig error unions | `Promise<Result<T,E>>` | Compiler-enforced typed errors |
| `[]const u8` string ops | `string ↔ uint8[]` zero-copy bit-cast | Same perf, TS syntax |
| Separate build system (build.zig) | `build.ms` + `@include`/`@compile` directives | Build config is MetaScript |

### What stays the same (the algorithm layer)

- Three-stage pipeline: compositor → diff → ANSI render
- Layer z-index ordering (0-900, Neovim-compatible)
- O(1) scroll via line-offset indirection
- Rope buffer (tree-based, leaf ~512 bytes)
- Dirty rect tracking per layer
- Double buffering (current/previous grid)
- Porter-Duff alpha compositing
- Helix-style ANSI optimization (adjacent skip, attribute dedup, synchronized updates)

The algorithms are language-agnostic. What changes is everything around them: less glue, less boilerplate, more compile-time safety, more language-level power.
