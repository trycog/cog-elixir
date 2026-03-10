<div align="center">

# cog-elixir

**Elixir language extension for [Cog](https://github.com/trycog/cog-cli).**

SCIP-based code intelligence and DAP debugging for Elixir projects.

[Installation](#installation) · [Code Intelligence](#code-intelligence) · [Debugging](#debugging) · [How It Works](#how-it-works) · [Development](#development)

</div>

---

## Installation

### Prerequisites

- [Elixir 1.14+](https://elixir-lang.org/install.html) (with Erlang/OTP)
- [Cog](https://github.com/trycog/cog-cli) CLI installed

### Install

```sh
cog install https://github.com/trycog/cog-elixir.git
```

This clones the repo, builds with `mix escript.build`, and installs to `~/.config/cog/extensions/cog-elixir/`.

---

## Code Intelligence

Add index patterns to your project's `.cog/settings.json`:

```json
{
  "code": {
    "index": [
      "lib/**/*.ex",
      "test/**/*.exs",
      "mix.exs"
    ]
  }
}
```

Then index your project:

```sh
cog code:index
```

Once indexed, AI agents query symbols through Cog's MCP tools:

- `cog_code_explore` — Find symbols by name, returns full definition bodies and references
- `cog_code_query` — Low-level queries: find definitions, references, or list symbols in a file
- `cog_code_status` — Check index availability and coverage

The index is stored at `.cog/index.scip` and automatically kept up-to-date by Cog's file watcher after the initial build.

| File Type | Capabilities |
|-----------|--------------|
| `.ex` | Go-to-definition, find references, symbol search, project structure |
| `.exs` | Same capabilities (config, test, and script files) |

### Indexing Features

The SCIP indexer supports:

- Modules (`defmodule`) with nested module tracking
- Functions (`def`/`defp`) with arity, parameters, and multi-clause deduplication
- Macros (`defmacro`/`defmacrop`, `defguard`/`defguardp`)
- Delegated functions (`defdelegate`)
- Struct fields (`defstruct`)
- Protocols (`defprotocol`) and implementations (`defimpl`)
- Type specifications (`@type`/`@typep`/`@opaque`)
- Callbacks (`@callback`/`@macrocallback`)
- Custom module attributes (`@attr value`)
- Import references (`alias`, `import`, `use`, `require`, `@behaviour`)
- Documentation attachment (`@doc`, `@moduledoc`)
- Scope tracking with `enclosing_symbol` for nested definitions

---

## Debugging

Cog's debug daemon manages debug sessions through the DAP (Debug Adapter Protocol). AI agents interact with debugging through MCP tools — `cog_debug_launch`, `cog_debug_breakpoint`, `cog_debug_run`, `cog_debug_inspect`, `cog_debug_stacktrace`, and others.

### Daemon commands

```sh
cog debug:serve       # Start the debug daemon
cog debug:status      # Check daemon health and active sessions
cog debug:dashboard   # Live session monitoring TUI
cog debug:kill        # Stop the daemon
```

### Configuration

| Setting | Value |
|---------|-------|
| Debugger type | `dap` — Debug Adapter Protocol via ElixirLS |
| Transport | `stdio` |
| Boundary markers | `:erlang.apply`, `:elixir_compiler`, `:elixir_dispatch` |

Boundary markers filter Elixir/Erlang runtime internals from stack traces so agents only see your code.

**Prerequisite:** [ElixirLS](https://github.com/elixir-lsp/elixir-ls) must be installed and available as `elixir_ls` in your `$PATH`.

---

## How It Works

Cog invokes `cog-elixir` once per extension group. It expands the matched file
paths directly onto argv, and the binary distributes parsing work internally
across concurrent tasks. Individual file failures are logged and converted into
empty documents so the rest of the batch still completes. As each task
finishes, `cog-elixir` emits structured progress events on stderr so Cog can
advance its progress UI file by file.

```
cog invokes:  bin/cog-elixir --output <output_path> <file_path> [file_path ...]
```

**Auto-discovery:**

| Step | Logic |
|------|-------|
| Workspace root | Walks up from each input file until a directory containing `mix.exs` is found (fallback: file parent directory). |
| Project name | Parsed from `mix.exs` `app: :name` field via regex. Falls back to workspace directory name. |
| Indexed target | Every file expanded from `{files}`; output is one SCIP protobuf containing one document per input file. |

### Architecture

```
lib/
├── cog_elixir.ex               # Entry point (escript main/1)
└── cog_elixir/
    ├── cli.ex                   # CLI argument parsing
    ├── workspace.ex             # Mix project discovery
    ├── analyzer.ex              # Elixir AST walker and symbol extraction
    ├── symbol.ex                # SCIP symbol string builder
    ├── scip.ex                  # SCIP protocol data structures
    └── protobuf.ex              # Protobuf wire format encoder
```

The indexer has zero Hex dependencies — parsing uses Elixir's built-in `Code.string_to_quoted/2` and protobuf encoding is implemented from scratch.

---

## Development

### Build from source

```sh
mix escript.build
```

Produces the `cog_elixir` escript. To install for Cog:

```sh
mkdir -p bin && cp cog_elixir bin/cog-elixir
```

### Test

```sh
mix test
```

Tests cover CLI parsing, workspace discovery, symbol string generation, protobuf encoding, and fixture-based indexing (simple modules, multi-module projects with alias/import, protocols with implementations).

### Manual verification

```sh
mix escript.build
./cog_elixir --output /tmp/index.scip /path/to/file.ex /path/to/other.ex
```

### Hang diagnostics

For hard-to-reproduce indexing hangs, enable structured debug logging and an
optional per-file timeout:

```sh
COG_ELIXIR_DEBUG=1 \
COG_ELIXIR_FILE_TIMEOUT_MS=30000 \
./cog_elixir --output /tmp/index.scip lib/app.ex lib/other.ex 2> /tmp/cog-elixir-debug.log
```

With `COG_ELIXIR_DEBUG=1`, the indexer emits newline-delimited JSON debug events
to stderr for each file/stage, including timing, BEAM memory snapshots, task
memory, reductions, queue length, and periodic `file_still_running` watchdog
events while a file is hung.

---

<div align="center">
<sub>Built with <a href="https://elixir-lang.org">Elixir</a></sub>
</div>
