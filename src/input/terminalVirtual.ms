// Virtual terminal — the virtual runtime the whole methodology rests on.
// Pure MetaScript, no OS calls, compiled on every backend and every --os.
// A sim test injects bytes, drives the real pipeline, and reads captured output.

import { Terminal, TermSize } from "./terminal";

// The Terminal contract plus test-only controls (inject/captured/resize/isRaw).
export interface VirtualTerminal {
    enterRaw: () => Result<void, string>;
    restore: () => void;
    size: () => TermSize;
    read: () => string;
    write: (data: string) => void;

    inject: (s: string) => void;
    captured: () => string;
    resize: (cols: uint16, rows: uint16) => void;
    isRaw: () => boolean;
}

// Mutable state shared by every closure below — one heap record, captured once,
// mutated by field (never rebound: a rebased local would not be shared).
interface VState {
    out: string;
    inp: string;
    cols: uint16;
    rows: uint16;
    raw: boolean;
}

export function newVirtualTerminal(cols: uint16, rows: uint16): VirtualTerminal {
    const st: VState = { out: "", inp: "", cols: cols, rows: rows, raw: false };
    return {
        enterRaw: () => { st.raw = true; return Result.ok(null); },
        restore: () => { st.raw = false; },
        size: () => { return { rows: st.rows, cols: st.cols }; },
        read: () => { let d = ""; d = d + st.inp; st.inp = ""; return d; },
        write: (data: string) => { st.out = st.out + data; },

        inject: (s: string) => { st.inp = st.inp + s; },
        captured: () => { return st.out; },
        resize: (c: uint16, r: uint16) => { st.cols = c; st.rows = r; },
        isRaw: () => { return st.raw; },
    };
}

test "injected input round-trips through read" {
    const t = newVirtualTerminal(80, 24);
    t.inject("j");
    assert t.read() === "j";
}

test "read drains the input buffer" {
    const t = newVirtualTerminal(80, 24);
    t.inject("abc");
    t.read();
    assert t.read() === "";
}

test "write accumulates and is captured" {
    const t = newVirtualTerminal(80, 24);
    t.write("\x1b[2J");
    t.write("hi");
    assert t.captured() === "\x1b[2Jhi";
}

test "size reflects construction and resize" {
    const t = newVirtualTerminal(80, 24);
    assert (t.size().cols as number) === 80;
    assert (t.size().rows as number) === 24;
    t.resize(120, 40);
    assert (t.size().cols as number) === 120;
    assert (t.size().rows as number) === 40;
}

test "enterRaw toggles raw state, restore clears it" {
    const t = newVirtualTerminal(80, 24);
    assert t.isRaw() === false;
    const r = t.enterRaw();
    assert r.ok;
    assert t.isRaw() === true;
    t.restore();
    assert t.isRaw() === false;
}

test "virtual terminal is assignable to the Terminal seam" {
    const term: Terminal = newVirtualTerminal(80, 24);
    term.write("ok");
    assert (term.size().cols as number) === 80;
}
