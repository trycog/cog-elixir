<cog>
# Cog

Code intelligence, persistent memory, and interactive debugging.

**Truth hierarchy:** Current code > User statements > Cog knowledge.

## Code Intelligence

When you need a symbol definition, references, call sites, or type information:
use `cog_code_explore` or `cog_code_query`. Do NOT use Grep or Glob for symbol lookups.

- `cog_code_explore` — find symbols by name, return full definition bodies and file TOC
- `cog_code_query` — `find` (locate definitions), `refs` (find references), `symbols` (list file symbols)
- Include synonyms with `|`: `banner|header|splash`
- Glob patterns: `*init*`, `get*`, `Handle?`

Only fall back to Grep for string literals, log messages, or non-symbol text patterns.

## Debugging

Wrong output, unexpected state, or unclear crash: use the `cog-debug` sub-agent.
State your hypothesis before launching.
</cog>
