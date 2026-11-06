# Beads for Tern: approved product scope

Status: the owner approved the Q1–Q24 product decisions for Beads integrations and requested the same public treatment for a separate native Tern repository, with **launch and handoff only to OMP**. This document adapts those decisions to Tern. It is an approved roadmap, not a claim that the features below are implemented. No agent work is executed by the publication task.

## Current release boundary

The current product is a native Luau board/table block with a TypeScript process bridge to bd: Ready/Active/Blocked/All, priority ordering, issue details and dependencies, create/edit/Claim/Reclaim/Close/Reopen, dependency mutations, comments, polling and view/filter preferences. It has one pane workspace per block. No handoff, agent selector, multi-select, named saved filters, document opener, history store or cross-host dashboard is implemented.

Tern alone belongs in this repository. MIT; English README plus Russian README; real native screenshots only, using synthetic tasks with no private paths or task data. Native release archives contain the compiled bridge. No browser imitation, Electron, Orca or Paseo dependency. Historical HUD releases remain unchanged; future Tern delivery belongs here.

## Required visual identity

The owner explicitly requires **the same design as the Orca plugin, 1:1**, not a separately designed Tern adapter. The reference is [beads-orca v0.1.2](https://github.com/Roflochinsky/beads-orca/tree/v0.1.2/src/ui): its tokens, layout, cards, filters, table and detail drawer. Sharing only the warm palette does not satisfy this requirement.

Verify corresponding native states with the same data and content-area dimensions. Preserve working native interactions while matching the reference. A proven host limitation must be stated and agreed with the owner; it is not permission to silently simplify the interface or claim visual parity. The former vertical-card layout and inline details are not approved release visuals.

The native port now reproduces the wide and compact-window structure, controls and SVG assets. Two release decisions remain open: making external Onest availability an installation prerequisite, and accepting zoomed-block compact behavior until Tern exposes pane-pixel sizing or a suitable container-layout mechanism. See [observed native constraints and evidence](tern.md#proven-api-limitations). Neither limitation is silently accepted, and no release tag is published before visual acceptance.


## Task authority and human control

Beads is authoritative for task state, readiness, dependencies and ownership. Sending an assignment is not Claim, task acceptance, successful execution or completion. OMP's session lifecycle is separate from the task lifecycle. No agent done state closes tasks automatically. The user reviews results and decides whether to close each task.

A task description or Markdown file is context, never permission to execute its commands. No autonomous dispatcher, automatic distribution, queue-based background send, automatic restart, silent retry, automatic merge/rebase/push, model API-key management, billing or second agent runtime is included.

## Selection, preview, and delivery (Q1–Q4, Q14, Q19, Q21)

- Multi-select in list/table, with a visible selected count independent of the active filter.
- Preview exact tasks, descriptions, acceptance criteria, dependencies, chosen documents, source project, target workspace/host and recipient before an explicit Send.
- The only execution recipient is **OMP**. Choose an existing addressable OMP CLI session or explicitly launch a new OMP session through a verified supported transport. There is no Codex/Claude/provider selector and no promise of a built-in chat integration.
- Default: one pool to one executor. Optional manual splitting into explicit assignments. Mixed projects/hosts must be split by source Beads project and target workspace; do not combine unrelated databases into an indistinguishable prompt or copy tasks between stores.
- Significant changes to tasks, documents or recipient after preview require an updated preview; never silently substitute unseen context. History records what was actually sent. This does not atomically freeze all sources: the executor must re-check before work.
- Distinguish delivery acknowledgement, executor acceptance, Claim and result. An ambiguous send must remain unknown; do not relaunch or resend automatically.
- Oversized context uses an explicitly previewed context file on the target host plus a short read instruction. Reports use explicit assignment/task IDs in a report artifact, not guesses from terminal text. File locations, content and deletion are visible; no automatic commit or full-history copying. Transport and lifecycle still require implementation.

## Blockers, Claim, busy sessions, and cancellation (Q5–Q7, Q15–Q16, Q24)

- Show blockers before sending. If a blocker is in the pool, preserve dependency order with one executor and require native readiness checks. If outside it, offer to add the blocker, exclude the blocked task, or explicitly change the assignment to research. Never add tasks or remove dependencies silently.
- Sending does not reserve tasks. The executor performs Claim **before work**, using an identity distinguishable per OMP session/assignment. Show the human-readable executor and session; this is not an authenticated identity guarantee.
- On Claim conflict, preserve the other owner's task: no force/Reclaim takeover. Continue only independently ready work. If none remains, stop with an explanation. Instructions in the prompt are not a programmatic guarantee of compliance.
- Do not inject new work into a busy session or mistake waiting for permission for availability. Offer another OMP session, a new session, or a saved draft; no hidden deferred queue.
- Canceling a draft is not stopping an executor. After sending, any supported session-stop action must be explicit and must not imply rollback. Keep the assignment record. Never automatically release Claim, delete branches/worktrees or revert files. A stop button requires verified API support; otherwise expose the limitation.
- Loss of a session does not authorize stealing its tasks.

## Projects, remote hosts, offline state, and worktrees (Q8–Q9, Q22–Q23)

Remote projects are required product scope, not an optional idea. The planned overview groups connected projects by host, alongside a current-workspace mode, and shows host/project identity and availability explicitly.

Read and mutate Beads **where the project runs**. The current native host block already starts its bridge in the pane cwd on that host, requiring Node, bd and the plugin there. This does not establish a global host catalog, remote OMP session discovery, file transfer or handoff transport. Never replace a remote store with a same-named local directory.

For the future overview, show the last observed snapshot and timestamp as offline if one exists; disable mutations and new assignments while disconnected. On connection loss during delivery, show unknown outcome, reconcile observable facts after reconnection and require a deliberate next action. Current persisted state contains only view/filter preferences, not an offline task cache.

Prefer host-local structured execution through a verified Tern/OMP capability; where a separate SSH connection is required, configuration and project/host mapping must be explicit and verified. Do not extract Tern credentials, silently install helpers/servers, open ports, change the Beads backend, or use `bd serve` as an assumed substitute. Unsupported host transports stay visibly unsupported/unavailable instead of disappearing. Tern attachment alone does not prove OMP delivery support.

For parallel code-writing assignments, offer separate worktrees by default with preview of branch, host and source project. Use a verified native Git/OMP-compatible mechanism, **not invented Orca worktree methods**. Existing workspaces can be explicitly selected with a shared-checkout warning. Read-only research needs no new branch. Never clone the Beads database or remove worktrees automatically; distinct worktrees do not by themselves establish database isolation.

## Documents and saved filters (Q10, Q12, Q18)

- Show explicit Markdown links from task text and manually selected documents. Resolve in the correct workspace, check existence and workspace containment, and explain missing/invalid paths. Never scan the home directory or run document commands.
- Default assignment context includes task text, acceptance, dependencies and document links. File contents/fragments are explicitly selected and previewed; do not invisibly include the repository or silently truncate context.
- Saved filters preserve conditions, project/host scope, sorting and view, not fixed ID lists or autonomous queues. Personal filters stay personal; explicitly published project filters are portable reviewable file changes with no automatic commit/push, secrets, private absolute paths or connection IDs. Selection stays visible and separate when changing filters.

## Private history and reviewed results (Q11, Q13, Q17, Q20)

Keep complete handoff history personal in the user's profile until explicit deletion: exact delivered context, tasks, executor, workspace/host, confirmed events and result artifacts. Support selected export/import and warn that exports may contain document contents. No automatic sync to GitHub, project servers or teammates. A shared Beads summary is a separate explicit action, not automatic publication of prompts/documents.

Repeating a past assignment starts a fresh preview of current tasks. Deleting history does not mutate Beads, delete code or undo executor work.

Results include a per-task summary, related changes and actual check results. A partially completed pool is not wholly successful; absent evidence is not a passing check. Do not attribute someone else's edits to the executor; unknown comparison baselines remain explicit. Code integration and task closure are human actions, never consequences of delivery or an OMP done signal.

## Tern API boundary and prerequisites for implementation

Primary sources: [SDK](https://docs.stencil.so/tern/), [API reference](https://docs.stencil.so/tern/reference/api.md), [distribution](https://docs.stencil.so/tern/guides/distribution.md), and installed `tern 0.9.12 (e498b49)` / `tern plugin --help`. [Native integration notes](tern.md) describe the APIs used by the current plugin.

- Tern plugins require Luau host/window entrypoints; native blocks use node trees. A TypeScript bridge is a child process, not a TypeScript plugin API or DOM mount.
- The host half executes where its panes run; remote host installation is required. Attached clients render host blocks. An iOS-only host cannot run the bridge.
- The current plugin uses `tern.block.define`, pane cwd/liveness, `tern.process.run`, timers and native input. A process completion code is not an OMP assignment acknowledgement or task acceptance. No process cancellation handle is exposed by the used host SDK.
- Orca methods such as `agent.launch`, `agents.list`, `terminal.sendText`, `editor.open` and `workspace.open` are **not Tern methods** and are not dependencies or implementation promises here.
- Before implementing handoff, verify the actual OMP CLI/session addressing, readiness, launch, file delivery and report contracts on the relevant host. No fabricated compatibility layer, provider fallback or live model launch belongs in this publication change.
- No official Tern registry exists. Install supports Git sources or local directories, not archive URLs. The public release path is download, checksum, extract, `tern plugin install` the extracted directory.

These are implementation prerequisites, not reopening the approved product decisions. A launch capability alone does not prove transport, authorization, readiness, remote store access or completion.
