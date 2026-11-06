# Tern: native Beads plugin

Beads runs as a genuine **`beads.board` plugin block** inside Tern. It does not launch a browser, translate tasks into `TODO.md`, or rely on Tern's unrelated built-in Markdown board.

## Supported surface and implementation

The integration was authored against the installed **Tern 0.9.12 (`e498b49`)** CLI and the definitions emitted by `tern plugin types`. The minimum compatible API is the API shipped by that build; other versions need the checks below rather than an assumed compatibility guarantee.

- `integrations/tern/plugin.toml` is a schema-1 Tern manifest declaring host entry `host.luau` and block `board`.
- `host.luau` uses real `tern.block.define`, native node builders, native input events, `tern.process.run`, `tern.timer`, and the pane lifecycle API. The palette automatically offers **New Beads block**.
- `src/tern/bridge.ts` is the TypeScript process entry. It receives one RPC request on stdin, invokes this repository's `src/core/service.ts` handler, and emits one JSON envelope on stdout. Tern starts it with an argv array, not a shell command. No runtime code is imported from another repository.
- The workspace is the native block's `cx.cwd`. The bridge registers only `{id: "workspace", path: process.cwd()}`; RPC callers cannot select an arbitrary filesystem path. Open one Beads block per project. No project discovery or secret configuration is read by this adapter.
- Task data, readiness and blockers come from the shared core's actual `bd` commands. Successful mutations trigger an authoritative snapshot refresh. No speculative status updates, fake success messages or automatic issue closure are used.

### Features

Native horizontal board and sortable table, text search, type/priority/assignee filters, status navigation, dependency highlighting and a right detail drawer follow the Orca v0.1.2 design. Native actions cover create / edit / claim / reclaim / close / reopen / dependency link / unlink / add comment / read comments. Edit is inline and supports title, description, priority, assignee, notes, acceptance and design; status changes use explicit actions. Create is a modal with type and priority choices, description, assignee and labels. Comments display author, relative time and text, with raw JSON only for an unrecognized record.

Edit captures each field's initial value and submits only fields whose final value differs from that baseline. An unrelated title edit does not resend stale status, assignee, or other untouched fields; restoring a field to its baseline omits it, and saving an unchanged form sends no mutation. This is not atomic same-field conflict protection: if another actor changes a field that the user also edits, the native update may overwrite that actor's value.

All issues includes an **Other** board group for `pinned`, `hooked`, and custom statuses. Grouping keeps closed issues in Closed, then gives explicit `blocked` status or native `blockedIds` precedence over In progress and Deferred. Active and Blocked filters use that same classification. Ready uses only native `readyIds`; it is not inferred from status or missing blockers. Board, table, and `j`/`k` selection share the same filtered issue set.

A background snapshot starts every five seconds when no request of that kind is already running, and pauses while searching, editing a form or composing a comment. It does not lock local controls. Foreground requests remain serialized; starting one increments a generation, so an older background response cannot overwrite it. Successful mutations still trigger an authoritative foreground refresh. Closing the block stops further polling and ignores in-flight completions; an already-launched process may finish within its timeout. Plugin/daemon reload recreates the polling loop. Only layout/status-view preferences persist; tasks, errors and drafts are not cached to disk.

| Key | Action |
| --- | --- |
| `1`, `2`, `3` | Ready, Active, Blocked |
| `/` | Focus search |
| `j` / `k`, arrows | Select next / previous issue |
| `c` | Claim selected issue |
| `x` | Open close form, or reopen a closed issue |
| `n` | New issue |
| `r` | Refresh |
| `Escape` | Cancel form or deselect issue |
| `Tab`, `Shift Tab` | Next / previous form field |
| `Ctrl Enter` / `Cmd Enter` | Submit form |

Text fields support paste, IME text, UTF-16 caret movement, Home/End, Shift-selection, Ctrl/Cmd+A and deletion. Tern's **Native composer editing** preference additionally enables mouse selection and caret placement. Enter adds a newline in multiline fields and submits from a single-line field; Ctrl/Cmd+Enter submits from either. Arrow keys change a focused type/priority choice. Pending foreground operations disable actions, editing and issue selection; a background snapshot does not. A comments request keeps its selected issue until completion, and selecting another issue clears the old comments and unsaved edit form. Failures remain visible. After a timeout, refresh before retrying: the mutation might already have succeeded.

### Proven API limitations

These are native-host constraints, not a substituted browser implementation:

1. **No TypeScript plugin entry or DOM mount.** [Manifest reference](https://docs.stencil.so/tern/reference/manifest.html) requires `.luau` or `.lua` host/window entries. [Views](https://docs.stencil.so/tern/guides/views.md) are native node trees. The Luau host is necessary; Beads command semantics remain in this repository's TypeScript core.
2. **Onest must be available outside the plugin.** [Supported CSS, `@font-face`](https://docs.stencil.so/tern/styles/css.html#font-face) explicitly says plugins cannot load fonts. This plugin requests `font-family: Onest` only within its surface; it does not change Tern preferences. Onest resolved in a Linux test process with a private `FONTCONFIG_FILE`, without installing a user/system font. Without an available Onest family, the host substitutes sans. That fallback is not accepted as visual parity; the installation prerequisite remains an owner decision.
3. **A native host block has a pane workspace, not the browser application's multi-project shell.** Open it beside the project's shell. Remote panes require this plugin, Node and `bd` on the remote host. Attached desktop/web/iOS clients render the host block; executing the bridge on an iOS-only host is not supported (`tern.process.run` raises there).
4. **Headless `tern shot` and `tern serve` are not arbitrary-plugin acceptance tests.** [Scripts](https://docs.stencil.so/tern/scripts/index.md) states that headless sessions load no user plugins; `plugins fixtures` loads Tern's own fixtures. Use a normal `--control` window to exercise this package. A successful manifest-only `plugin list` without a daemon does not prove native execution.
5. **Compact CSS follows the window, not the split pane.** The [host `BlockCx`](https://docs.stencil.so/tern/reference/api-host.html#block-cx) exposes terminal columns/rows, not a pane pixel rectangle. In the actual 1400 px window, a 671 px Beads split retained a 240 px vertical rail. A 700 px content region in a narrow window correctly used horizontal navigation and a full-width drawer. Zooming the block avoids that mismatch; an arbitrary columns-to-pixels threshold is not a 1:1 fix. Split-pane parity remains unaccepted.

The port uses Orca's palette, dimensions and licensed Material Symbols SVG paths rather than a redesigned native theme. It does not claim browser drag/drop or hover event equivalence. The font and split-pane constraints above block an unconditional 1:1 release claim.

## Build and install

Prerequisites on the machine running the panes:

- Tern with the API above, available to the user (Tern is a closed beta).
- Node.js 24 or newer and `bd` 1.3.2 on the daemon's PATH.
- An initialized project with `.beads`; this plugin never initializes or migrates production projects.

The repository build copies the runtime files from `integrations/tern/` to **`dist/tern/`** and bundles `src/tern/bridge.ts` as ESM to **`dist/tern/bridge.mjs`**, including the core. No generated bridge belongs in `integrations/tern/`. There are no npm runtime dependencies.

For release installation, download and verify the archive, extract it, and install the extracted `tern/` directory as described in [README](../README.md#install). **A release archive URL is not a supported `tern plugin install` source:** HTTP(S) sources are cloned as Git repositories. The source checkout also needs a build before installation.

Run from the beads-tern repository root:

```sh
npm run build
tern plugin install "$PWD/dist/tern"
tern plugin list --json
```

Alternatively, explicitly authorize `tern plugin link "$PWD/dist/tern"` for development. Install/link changes Tern's plugin directory and automatically reloads plugins; do not run either against someone's host without approval. Use `tern plugin dir` to discover the actual destination, never assume `~/.config/tern`. Tern names an installed copy after manifest ID `beads`. Updating requires `tern plugin install "$PWD/dist/tern" --force`; this will not replace a linked package. Uninstall with `tern plugin remove beads` (or `tern plugin unlink beads` for a link). The standalone version sequence starts at 0.1.0; Tern does not compare version strings, so `--force` also migrates the historical HUD 0.1.2 package while retaining the same block identity.

Open a shell in the initialized project, then choose **New Beads block** in the command palette. No window entry, HTTP server, authentication token, port or browser executable is needed. If Node is not on the daemon PATH, set **`BEADS_TERN_NODE` to an absolute Node executable path before starting the daemon**. This is a program path, not a shell command; do not append arguments. Changes to the launching shell's environment do not modify an already-running daemon.

## Verification

The commands below run from this repository root. Automated checks cover the service and built bridge, not native rendering. Native UI acceptance requires an actual Tern window. No results from the former multi-host repository are presented as standalone-release passes.

### Recorded local verification

- TypeScript typecheck, build, all 13 behavior/boundary tests and the built-bridge smoke with real bd passed. Packaging produced only the native plugin directory and checksums, with no Electron, Orca or other host runtime.
- The checksummed archive was extracted and installed with native `tern plugin install ... --force` into an isolated Tern profile, not linked as a development package.
- A real Tern 0.9.12 X11 window displayed the eight-task synthetic fixture. Board/table transitions, issue selection, search, modal creation, inline editing, Unicode comment persistence and Claim → Close → Reopen were exercised. Beads CLI output independently confirmed mutations.
- UTF-16 selection and editing replaced a supplementary character correctly; Ctrl+A cleared the search. Active search remained editable across the five-second polling boundary.
- A native event probe reproduced a dropped click during background polling (`busy=true` although the drawn button was enabled). Separating background snapshots from foreground requests restored 12 consecutive board/table transitions across polling intervals. Temporary event logging was removed. A deliberately delayed stale-read race was not separately forced.
- Real captures cover board, table, drawer and create dialog at 1600×1000 content pixels, plus board and drawer at 700×900. README images are crops of those native captures, not HTML replicas or composites. They contain synthetic data only.
- Onest was available only to the isolated rendering process. A temporary sans override changed the measured 16 px/500-weight `beads` label from 45.64 px to 45.69 px; the override was removed. No global font or Tern theme preference was changed.
- `luau-lsp` was unavailable. Native reload exercised the Luau host, but no standalone Luau typecheck is claimed. macOS UI, remote-pane execution and exact split-pane visual parity have not been accepted.


### Type and boundary checks

```sh
npm run build
npm run typecheck
npm test
types_dir="$(mktemp -d)"
tern plugin types "$types_dir"
luau-lsp analyze --platform=standard --definitions="@tern=$types_dir/tern.d.luau" integrations/tern/host.luau
```

If `luau-lsp` is unavailable, report that prerequisite rather than installing it implicitly. `src/tern/bridge.test.ts` exercises the built process's public stdin/stdout boundary: host project identity, rejection of RPC-supplied paths, and malformed-request errors. `npm run smoke` exercises the same built bridge against an isolated real bd database. Native behavior is exercised by `integrations/tern/smoke.txt`, not mocked registration calls.

### Genuine native smoke

Use an **empty disposable Beads project**, never a production database. The integration owner should create it under their existing isolated fixture setup: unset inherited `BEADS_*` / `DOLT_*` database-routing variables, isolate HOME/XDG directories for `bd`, initialize a temporary git repository, and use the documented command:

```sh
bd init --prefix=smoke --non-interactive --skip-agents --skip-hooks
```

Run in the fixture directory, with the same clean environment for both initialization and the test daemon. No global/shared database flags. The installed `bd 1.3.2` documents embedded Dolt as the default and only supported storage backend; do not invent `--backend sqlite`.

Point Tern at an isolated config and daemon socket, install **the built package**, and open a real window in that fixture. For example, with absolute paths assigned to `TERN_CONFIG_DIR`, `TERN_DAEMON_SOCKET`, `STENCIL_LOG_DIR`, `FIXTURE`, `PACKAGE`, and `CONTROL` by the fixture owner:

```sh
export TERN_CONFIG_DIR TERN_DAEMON_SOCKET STENCIL_LOG_DIR
tern plugin install "$PACKAGE"
tern --control "$CONTROL" "$FIXTURE"
```

Run the following from another terminal with the same isolation environment:

```sh
tern plugin list --json
tern plugin reload beads --json
tern ctl --control "$CONTROL" --file integrations/tern/smoke.txt
tern ctl --control "$CONTROL" tree "[data-surface='plugin.beads.board']"
tern ctl --control "$CONTROL" state
```

The scenario opens the real palette block, waits for an authoritative empty snapshot, creates a real issue through native input, then claims, closes and reopens it. It asserts the corresponding live native surface text after each mutation. Retain raw CLI responses and daemon logs. Compare with `bd list --all --json` in the fixture and independently exercise two issues linked/unlinked through the native forms, checking Ready and Blocked after each. Test UTF-16 editing with non-ASCII and supplementary characters, narrow/wide panes, table selection, comments, invalid input, missing `bd`, and reload recovery. Check logs for `plugin handler failed` and `plugin style sheet has errors`.

If the isolated profile cannot open a window because the beta requires sign-in, report that runtime prerequisite rather than copying credentials or claiming a headless fixture run proved this plugin. `tern plugin list` alone is insufficient evidence. Closing the test window does not necessarily stop its daemon: the integration owner must manage the isolated daemon's lifetime.

### Correction regression assertions

The comments appended to `integrations/tern/smoke.txt` are a manual continuation, not executable assertions or recorded passes. In the isolated native window above, the integration owner should retain the native tree and fixture CLI output for each case:

1. **Untouched concurrent values:** select an open, unassigned issue A and open Edit. Change only its title. Before Save, use a second actor in the same disposable fixture to claim A and change its description, priority, notes, acceptance and design. Save in Tern, wait for the authoritative refresh, then inspect A through the native details and `bd show A --json` (substitute the fixture ID). The new title must coexist with the second actor's in-progress status, assignee and all other changed fields. The update boundary's expected input is exactly `{id: A, title: "<new title>"}`. Repeat after changing then restoring an unrelated field in the form; it must remain omitted. Saving an unchanged form must close the form without an update request.
2. **Comments stay with their issue:** create A and B with distinct comment text. Load A's comments and, while the request is visibly pending, attempt table row selection and activation of B, `j`/`k`, and (in board view on a repeated request) card/dependency navigation. The selected issue and details must remain A until completion. Only A's comment text may appear. After selecting B, no A comments may remain; requesting B's comments must show B's text. A run where the request completed before selection was attempted does not exercise the race.
3. **All includes every status:** seed separate unblocked `pinned`, `hooked`, and fixture-supported custom-status issues, plus an in-progress issue blocked by an open dependency and an explicit blocked issue. Choose All issues. The nonstandard statuses must appear in Other, and the blocked issues in Blocked, not In progress. Cycle through issues with `j`/`k` and verify each selected ID has a visible card; Table must expose the same IDs. Active must exclude the native-blocked in-progress issue; Blocked must include it and the explicit blocked issue. Compare Ready IDs with native `bd ready --json`, not an inferred open-status list. Do not alter production status configuration to prepare this case.
4. **Visible, scrollable surface:** capture the ordinary window with `tern ctl shot`, not just its element tree. The empty `.sf-layer` must remain transparent. At a normal window height, use the wheel over `.sf-main` to reveal a dependency below the fold and click it without resizing. Background and padding belong only to main/dock regions.
5. **Background refresh stays interactive:** while background reads run, switch Board/Table, focus search and select an issue. The action must not disappear behind an invisible `busy` guard. For the stale-read boundary, delay a real background response, perform a foreground action, then deliver that older response: it must not overwrite the newer state. Do not replace bd results with invented fixtures when claiming native acceptance.


## Discovery evidence (raw excerpts)

Source extraction baseline: beads-hud commit `aea263c8def2e91d7e670fa193bcba1cb9ba8bff`. The installed CLI was re-read for this extraction, without installing the plugin or launching an agent:

```text
$ tern --version
tern 0.9.12 (e498b49)

$ tern plugin --help
tern plugin list                          plugins, how they loaded, problems
tern plugin reload [ID]                   load every plugin again, or only ID
tern plugin dir                           where plugins are installed
tern plugin install SRC [--force]         from a git URL or a directory
tern plugin remove ID
tern plugin link DIR | unlink ID          use a plugin where it is
tern plugin types DIR                     writes DIR/tern.d.luau for luau-lsp
      every verb also takes [--json] [--window KEY]

$ bd --version
bd version 1.3.2 (9b65b9e19)
```

Official [distribution documentation](https://docs.stencil.so/tern/guides/distribution.md) confirms that `install` accepts a directory or a Git source, clones the default branch, and does not download/extract release archives. Download → checksum → extract → install directory is the supported artifact flow. There is no official registry; community discovery is optional and does not replace release verification.

Other primary sources: [SDK overview](https://docs.stencil.so/tern/), [block lifecycle and liveness](https://docs.stencil.so/tern/guides/blocks.md), [input/UTF-16 editing](https://docs.stencil.so/tern/elements/input.md), [API reference](https://docs.stencil.so/tern/reference/api.md), and [driving a real plugin window](https://docs.stencil.so/tern/guides/debugging.md#driving-a-window-from-a-script).
