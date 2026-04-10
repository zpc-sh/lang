# Merkin Wasm Bridge

**Status**: `Mulsp.Merkin.Wasm` is a stub today. This document defines the
end-to-end path and what remains to be done.

---

## What merkin/api builds to today

```
merkin/api/        — wasm export surface (bloom + tree + hash only)
merkin/wasm_entry/ — is-main entry point that re-exports api functions
```

```sh
cd merkin
moon build --target wasm-gc --release --package nocsi/merkin/wasm_entry
# Output: _build/wasm-gc/release/build/wasm_entry/wasm_entry.wasm
```

The wasm-gc binary builds cleanly. Size is small (~59B release stub) because
MoonBit's GC runtime is loaded separately by the host. The binary exports
`_start` plus all `pub fn` in the entry package. The host runtime (Popcorn or
wasmex) is responsible for wiring the calling convention.

### Why only bloom + tree + hash?

`model/` (yata_addressing, yata, yata_lineage, imprint) has 79 type errors —
all `Expr Type Mismatch` from a recent MoonBit version bump. These packages are
not needed for mulsp's core operations. Fixing them is tracked separately.

### What the API exports

| Function | Signature | Description |
|---|---|---|
| `bloom_add` | `(token: String) -> Unit` | Register routing token |
| `bloom_check` | `(token: String) -> Bool` | Probabilistic membership test |
| `bloom_serialize` | `() -> String` | Hex-encoded bit array for DC transfer |
| `bloom_popcount` | `() -> Int` | Approximate population count |
| `tree_ingest` | `(envelope_id: String, tokens_csv: String) -> String` | Ingest envelope, return root hash |
| `tree_sparse` | `(tokens_csv: String) -> String` | Filtered tree projection, returns `node_count=N\nroot=<hash>` |
| `tree_seal` | `() -> String` | Freeze epoch, return root hash |
| `tree_epoch` | `() -> Int` | Current epoch counter |
| `tree_node_count` | `() -> Int` | Live node count |
| `hash_bytes` | `(hex_input: String) -> String` | Content-address a byte string |
| `reset` | `() -> Unit` | Clear tree and bloom for session reuse |

State is module-level: one tree + one bloom per loaded wasm instance. mulsp
spawns one instance per LSP session (Popcorn handles lifecycle on AtomVM;
wasmex handles it on standard BEAM).

---

## Path A: Popcorn (AtomVM + wasm-gc)

**This is the correct long-term path.** Popcorn (Software Mansion) runs
MoonBit's wasm-gc modules inside AtomVM, giving mulsp wasm execution on
ESP32/RPi Pico/bare metal without a system Erlang installation.

### How Popcorn works

Popcorn wraps AtomVM's wasm-gc runtime (via ExAtomVM) and provides an Elixir
API for calling MoonBit exports:

```elixir
{:ok, instance} = Popcorn.load(wasm_binary)
{:ok, result}   = Popcorn.call(instance, :bloom_check, ["security"])
# result :: boolean
```

MoonBit's `pub fn` declarations in the `is-main` package are accessible via
Popcorn's FFI. Popcorn handles the wasm-gc type mapping (MoonBit structs →
Erlang terms).

### Integration steps

1. Copy the wasm binary into mulsp's priv directory:

   ```sh
   cd merkin
   moon build --target wasm-gc --release --package nocsi/merkin/wasm_entry
   cp _build/wasm-gc/release/build/wasm_entry/wasm_entry.wasm \
      ../lang/mulsp/priv/merkin.wasm
   ```

2. Add `popcorn` to `mulsp/mix.exs` (AtomVM-compatible, git dep):

   ```elixir
   {:popcorn, github: "software-mansion/popcorn", only: [:dev, :prod]}
   ```

3. In `Mulsp.Merkin.Wasm`, replace the stub with:

   ```elixir
   defp load_wasm(path) do
     wasm_binary = File.read!(path)
     {:ok, instance} = Popcorn.load(wasm_binary)
     {:ok, instance}
   end

   def handle_call({:bloom_check, token}, _from, %{mode: :wasm, instance: inst} = state) do
     {:ok, result} = Popcorn.call(inst, :bloom_check, [token])
     {:reply, {:ok, result}, state}
   end
   ```

### Open questions on Popcorn

- **Exact calling convention**: Popcorn's public API is still evolving. The
  `Popcorn.call/3` signature above is a reasonable guess based on the
  README; verify against the actual library before shipping.
- **wasm-gc export names**: Confirm that MoonBit's `pub fn bloom_check` in an
  `is-main` package is accessible as `:bloom_check` via Popcorn (not mangled).
- **AtomVM wasm-gc support version**: Requires AtomVM >= 0.7 with the
  wasm-gc proposal enabled at build time. Check your ESP32 AtomVM build.
- **String marshaling**: MoonBit strings are wasm-gc reference types. Popcorn
  may need a shim to convert Erlang binaries to MoonBit strings. If so, add
  a `bytes_to_string` / `string_to_bytes` export in `merkin/api/api.mbt`.

---

## Path B: wasmex NIF (standard BEAM, no AtomVM)

For mulsp running on a full BEAM node (not AtomVM), `wasmex` provides wasm
execution via a Rust NIF (Wasmtime under the hood). This is production-grade
on x86/ARM Linux/macOS.

### Add wasmex

```elixir
# mulsp/mix.exs — BEAM-only, skip in AtomVM builds
{:wasmex, "~> 0.9", runtime: Mix.env() != :atomvm}
```

### Bridge implementation

```elixir
def handle_call({:bloom_check, token}, _from, %{mode: :wasm, store: store, instance: inst} = state) do
  {:ok, [result]} = Wasmex.call_function(store, instance, "bloom_check", [token])
  {:reply, {:ok, result == 1}, state}
end
```

wasmex uses standard wasm (not wasm-gc). **If you use wasmex you need the
`--target wasm` build**, not `wasm-gc`:

```sh
moon build --target wasm --release --package nocsi/merkin/wasm_entry
```

The `--target wasm` build uses linear memory instead of GC refs. String
arguments become pointer + length pairs. Add export helpers in `api.mbt` if
needed:

```moonbit
// For linear memory (wasm, not wasm-gc):
pub fn alloc(size : Int) -> Int { /* ... */ }
pub fn bloom_check_ptr(ptr : Int, len : Int) -> Int { /* ... */ }
```

Decide on one target:
- Use `wasm-gc` when the primary deployment is AtomVM + Popcorn
- Use `wasm` when the primary deployment is standard BEAM + wasmex

Both targets build cleanly from the same `merkin/api` source with minor
additions.

---

## Path C: Port (works today, no wasm)

The CLI binary in `merkin/cmd/main/` can be built natively (once the
`model/` type errors are fixed) and spoken to over stdio. This is the
fallback path and useful for development before the wasm bridge is wired up.

### Build native CLI

```sh
cd merkin
moon build --target native --package nocsi/merkin/cmd/main
# Output: _build/native/release/build/cmd/main/main
```

(Requires fixing the 79 type errors in model/ first.)

### Port bridge in Mulsp.Merkin.Wasm

```elixir
defp open_port(binary_path) do
  Port.open({:spawn_executable, binary_path}, [
    :binary, :use_stdio,
    args: ["daemon"]
  ])
end

# Send: "bloom_check security\n"
# Recv: "result=true\n"
```

The CLI already handles `--action sparse`, `--action diff`, etc. The port
bridge wraps these as synchronous calls with a simple line protocol.

**Limitation**: Port requires a native binary. Can't use on AtomVM.

---

## Model layer type errors

79 errors, all in `model/`:

| File | Errors | Root cause |
|---|---|---|
| `model/yata_addressing.mbt` | 58 | `Expr Type Mismatch` across most methods |
| `model/yata.mbt` | 15 | Same pattern — likely a MoonBit API break |
| `model/yata_lineage.mbt` | 15 | `is_ready(self)` gets wrong `self` type |
| `model/imprint.mbt` | 8 | Type mismatch in field operations |
| `model/yata_protocol.mbt` | 1 | Deprecated `.to_int()` → `.reinterpret_as_int()` |

The `yata_protocol.mbt` warning is trivial to fix (one-liner). The others
look like a MoonBit version broke the implicit `self` receiver type in some
method chains. The fix is mechanical — run `moon check` on each file in
isolation and address the `Expr Type Mismatch` errors. None of them block the
wasm bridge since mulsp only needs bloom + tree + hash.

Fixing them does unlock the daemon layer (DaemonNode, ConversationHost,
YataGraph) which is the richer API. That's a separate task.

---

## Build pipeline (target state)

```makefile
# merkin/Makefile (to create)
.PHONY: wasm wasm-gc priv

wasm-gc:
	moon build --target wasm-gc --release --package nocsi/merkin/wasm_entry

wasm:
	moon build --target wasm --release --package nocsi/merkin/wasm_entry

priv: wasm-gc
	cp _build/wasm-gc/release/build/wasm_entry/wasm_entry.wasm \
	   ../lang/mulsp/priv/merkin.wasm
	cp _build/wasm-gc/release/build/wasm_entry/wasm_entry.wasm \
	   ../lang/muyata/priv/merkin.wasm
```

Then in Lang:

```elixir
# lang/mix.exs — run merkin build before lang compile
{:dep_that_runs_make, ...}
# Or: a mix task that shells out to `make -C ../merkin priv`
```

---

## Current state of Mulsp.Merkin.Wasm

```
Mode: :stub
bloom_check → always false (safe: causes DC to skip bloom filtering, accept everything)
sparse_tree → returns empty stub
ingest      → returns :stub_ingested
```

This is safe for development — mulsp works without merkin, just loses
bloom-based pruning and tree diffing.

The next concrete step: wire Path B (wasmex) since it requires no AtomVM and
works on standard BEAM today. Path A (Popcorn) is the AtomVM packbeam story
and is worth a focused spike once the wasmex bridge is working.
