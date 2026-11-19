# Context Index — GGC-awards
> Artifact map. Updated: 2026-11-19

## Quick Navigation

| Artifact | Path | Description |
|----------|------|-------------|
| CONTEXT_SPEC | context/CONTEXT_SPEC.md | Canonical rules for context docs (immutable) |
| MetaSpec | context/metaspec.md | Identity, stack, architecture, current state |
| Index | context/index.md | This navigation map |
| Timeline | context/timeline.md | Evolutionary history by phase |

## Active Artifacts

### Analyses — context/analysis/
No artifacts.

### Walkthroughs — context/walkthroughs/
No artifacts.

### Plans — plans/

| File | Date | Description | Status |
|------|------|-------------|--------|
| 2026-11-17_GGC_Awards_Supabase_Integration.md | 2026-11-17 | Wire temp/ designs to Supabase (DB, front, admin) | Executed; E2E pending |

## Critical Files

### Root

| File | Responsibility |
|------|----------------|
| README.md | Setup, dashboard steps, local run, deploy, secrecy limits |
| LICENSE | MIT license |

### Database — supabase/

| File | Responsibility |
|------|----------------|
| 01_schema.sql | Tables and constraints |
| 02_functions.sql | RPCs (votar, abrir/encerrar, definir_ano), triggers, sign-up hook |
| 03_rls.sql | RLS policies, grants, storage bucket, realtime |
| 04_seed.sql | Election row, dev placeholder, sample categories |
| 99_checks.sql | Assertions (run with rollback) |

### Front — public/

| File | Responsibility |
|------|----------------|
| js/config.js | Supabase URL and publishable key (public by design) |
| js/auth.js | Session, role guard, sign-out, error messages (`window.GGC`) |
| urna-eletronica.html | Voting booth; calls rpc `votar` at the end |
| admin-contas.html | Participants CRUD (accounts = candidates), photo upload |
| admin-menu.html | Admin hub plus Edição card (year, open, close) |

### Reference — temp/

| File | Responsibility |
|------|----------------|
| temp/*/ | Original mock designs; do not edit |
