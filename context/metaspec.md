# MetaSpec — GGC-awards
> Context for AI agents. Version: 0.2 | Updated: 2026-11-19

## IDENTITY
- Name: GGC-awards
- Domain: yearly voting site for the GGC friend group (Brazilian-style voting booth)
- Purpose: secret, single vote per category plus the main prize "GGC Of The Year"; admin CRUDs; live tally; per-year history
- Target users: group members (voters) and admins/dev; UI language pt-BR
- License: MIT

## STACK
```
Front:    HTML + CSS + vanilla JS (no framework, no build), static hosting (Vercel or DO App Platform, TBD)
Client:   @supabase/supabase-js 2.45.4 via jsDelivr CDN (exact version pinned)
Backend:  Supabase project cftzrevmsucsvkgnqpct (Auth, Postgres + RLS + RPC, Storage, Realtime)
VCS:      git (main branch, GitHub origin)
```

## ARCHITECTURE
```
login -> (voter) inicio -> urna -> rpc votar -> inicio
login -> (admin/dev) admin-menu -> participantes | categorias | edicao | apuracao | urna
page -> GGC.exigirSessao({roles}) -> sb (supabase-js) -> RLS / security definer RPCs
```

| Layer | Directory | Responsibility |
|-------|-----------|----------------|
| Pages | public/ | Static screens; each has its own inline CSS/JS |
| Shared JS | public/js/ | config (public key), client, session guard by role |
| Database | supabase/ | Numbered idempotent SQL: schema, functions, RLS, seed, checks |
| Design refs | temp/ | Original mock designs; reference only, not published |
| Context docs | context/ | Tier 1/2 agent context |
| Plans | plans/ | Implementation plans |

## DATA
- `contas` is the single table of participants: every voter is also a candidate when `numero` is set
- `categorias`, `contas`, `eleicao` have no year; `comparecimento`, `votos`, `edicoes`, `apuracoes` carry `ano`
- Live tally: view `apuracao` (current year) + rpc `qtd_que_votaram()`; closed years: `edicoes` + `apuracoes` snapshots
- Photos: public bucket `fotos` (5 MB, image/*), admin-only writes
- Realtime publication: `eleicao`, `comparecimento`

## AUTH
| Aspect | Detail |
|--------|--------|
| Provider | Supabase Auth, email + password, "Confirm email" OFF |
| Sign-up gate | Hook Before User Created `public.hook_so_convidados`: only e-mails already in `contas` |
| Roles | `votante`, `admin`, `dev` in `contas.role`; `dev` exists only via SQL |
| Enforcement | RLS + `security definer` functions check role; hiding UI is UX only |
| Front key | Only the publishable key is in the repo; never the service role key |

## CRITICAL BUSINESS RULES
- Secret vote: `votos` has no voter and no timestamp; who voted lives only in `comparecimento`
- No self-vote: own name is absent from `candidatos_urna()`; `votar()` stores own number as `nulo`
- One vote per voter per year (PK on `comparecimento`); `votar()` is atomic and only while status is `aberta`
- Lock while `aberta`: categories and participant numbers/removal cannot change (triggers)
- No admin may create, demote or remove a `dev`, change own role, or drop the last admin (trigger `proteger_contas`)
- Closing (`encerrar_votacao`) freezes the result into `edicoes`/`apuracoes`; `definir_ano` starts a new year

## CURRENT STATE (v0.2 — 19/11/2026)
- Branch `main`; database applied and checked; front integrated, not yet exercised in a real browser
- Ready:
  - SQL (schema, functions, RLS, storage, seed, checks) applied to the Supabase project
  - Pages: login (sign-up, reset), nova-senha, inicio, urna (mobile layout), admin menu, participantes, categorias, apuracao
- Technical debt:
  - Dashboard Auth settings pending: enable the Before User Created hook, turn Confirm email off, set Site URL and Redirect URLs
  - E2E in browser (3 accounts, mobile) still to run; hosting not chosen or deployed
