// The Terminal seam. Everything above it — compositor, diff, ANSI generation,
// key parsing — is platform-agnostic and never knows which OS it runs on.
//
// Implementations are constructor functions returning an object of closures over
// a shared state record; a class is deliberately NOT used (the compiler does not
// codegen a class assigned to an arrow-field interface). Wire data is carried as
// `string`, which in MetaScript is a UTF-8 byte buffer (same layout as uint8[]).

export struct TermSize {
    rows: uint16;
    cols: uint16;
}

export interface Terminal {
    // Raw mode: no echo, no line buffering, keys delivered as raw bytes.
    // Real backends can fail (not a tty); virtual never does.
    enterRaw: () => Result<void, string>;
    restore: () => void;
    size: () => TermSize;
    // Drain the input bytes currently available (may be empty).
    read: () => string;
    // Write bytes to the terminal (ANSI/VT escape codes + text).
    write: (data: string) => void;
}
