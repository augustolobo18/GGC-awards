# Timeline — GGC-awards
> Evolutionary history. 2 phases | Nov/2026.

## Phase 0: Initialization (Nov/2026)
- Commits: 269cdcf -> 269cdcf
- Repository created on GitHub with an MIT license
- Context documentation structure added (context/, plans/)

## Phase 1: Supabase integration (Nov/2026)
- Commits: 269cdcf -> uncommitted
- Mock designs in temp/ became a real site: static public/ wired to Supabase
- Participants and candidates merged into one table (`contas`); nobody votes for themselves
- Rules enforced in the database (RLS, RPCs, triggers), not only in the UI
- Closed years are frozen as snapshots, giving a per-year history

## Metrics Snapshot (2026-11-19)

| Metric | Value |
|--------|-------|
| Commits | ~1 |
| Source files | ~15 (HTML/JS) + 5 SQL |
| Languages | HTML, CSS, JS, SQL |
| Tests | SQL checks only; browser E2E pending |
