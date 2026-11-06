# Changelog

## 0.1.0 — unreleased standalone Tern package

- Extracted the native `beads.board` Luau host, scoped CSS and TypeScript bridge from beads-hud commit `aea263c8def2e91d7e670fa193bcba1cb9ba8bff`; preserved existing task behavior and plugin identity `beads`.
- Retained the core behavior suite, process-boundary bridge tests and native manual regression scenario. Real-bd smoke now exercises the compiled bridge rather than another host's service bundle.
- Added independent Node 24 build/typecheck/test/package scripts, locked build dependencies, checksum-verified bd 1.3.2 and commit-pinned Linux/macOS CI. Tag releases publish only the Tern tar.gz and SHA256SUMS.
- Documented supported download/checksum/extract/install flow, remote host execution, native API limitations, English/Russian installation, MIT licensing and the approved OMP-only roadmap.
- Ported Orca v0.1.2 navigation, horizontal columns, compact cards, sortable table, right drawer, modal creation, inline editing, comment cards and compact-window layout. Reused the exact Material Symbols SVG paths and retained their Apache-2.0 license.
- Added search and type/priority/assignee filters, selection-based dependency highlighting and UTF-16 text selection. Kept agent launch and handoff out of this release.
- Fixed background polling swallowing visible UI actions. Foreground requests remain serialized; a generation guard discards superseded background snapshots.
- Added real native screenshots and recorded Linux acceptance. Onest availability and split-pane compact behavior remain explicit visual-release gates; no fallback font or approximate pixel sizing is presented as 1:1 parity.
- No handoff or agent-launch features implemented. Historical multi-host release verification does not establish verification of this extraction.
