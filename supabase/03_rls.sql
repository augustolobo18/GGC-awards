-- GGC Awards — 03: RLS, grants, storage e realtime (idempotente)

-- ------------------------------------------------------------------ RLS
alter table public.contas         enable row level security;
alter table public.categorias     enable row level security;
alter table public.eleicao        enable row level security;
alter table public.comparecimento enable row level security;
alter table public.votos          enable row level security;
alter table public.edicoes        enable row level security;
alter table public.apuracoes      enable row level security;

-- contas: propria linha OU admin; escrita so admin (trigger proteger_contas faz o resto)
drop policy if exists contas_select on public.contas;
create policy contas_select on public.contas for select to authenticated
  using (user_id = (select auth.uid()) or (select public.e_admin()));

drop policy if exists contas_insert on public.contas;
create policy contas_insert on public.contas for insert to authenticated
  with check ((select public.e_admin()));

drop policy if exists contas_update on public.contas;
create policy contas_update on public.contas for update to authenticated
  using ((select public.e_admin())) with check ((select public.e_admin()));

drop policy if exists contas_delete on public.contas;
create policy contas_delete on public.contas for delete to authenticated
  using ((select public.e_admin()));

-- leitura para o hook Before User Created
drop policy if exists contas_hook_auth on public.contas;
create policy contas_hook_auth on public.contas for select to supabase_auth_admin
  using (true);

-- categorias: todo logado le; escrita admin (trigger trava com votacao aberta)
drop policy if exists categorias_select on public.categorias;
create policy categorias_select on public.categorias for select to authenticated
  using (true);

drop policy if exists categorias_insert on public.categorias;
create policy categorias_insert on public.categorias for insert to authenticated
  with check ((select public.e_admin()));

drop policy if exists categorias_update on public.categorias;
create policy categorias_update on public.categorias for update to authenticated
  using ((select public.e_admin())) with check ((select public.e_admin()));

drop policy if exists categorias_delete on public.categorias;
create policy categorias_delete on public.categorias for delete to authenticated
  using ((select public.e_admin()));

-- eleicao: leitura para logados; escrita so via RPC
drop policy if exists eleicao_select on public.eleicao;
create policy eleicao_select on public.eleicao for select to authenticated
  using (true);

-- comparecimento: propria linha OU admin; escrita so via votar()
drop policy if exists comparecimento_select on public.comparecimento;
create policy comparecimento_select on public.comparecimento for select to authenticated
  using (user_id = (select auth.uid()) or (select public.e_admin()));

-- votos / edicoes / apuracoes: leitura so admin; escrita so via funcoes
drop policy if exists votos_select on public.votos;
create policy votos_select on public.votos for select to authenticated
  using ((select public.e_admin()));

drop policy if exists edicoes_select on public.edicoes;
create policy edicoes_select on public.edicoes for select to authenticated
  using ((select public.e_admin()));

drop policy if exists apuracoes_select on public.apuracoes;
create policy apuracoes_select on public.apuracoes for select to authenticated
  using ((select public.e_admin()));

-- ---------------------------------------------------------------- grants
revoke all on all tables in schema public from anon;
revoke truncate, references, trigger on all tables in schema public from authenticated;
revoke insert, update, delete on
  public.eleicao, public.comparecimento, public.votos, public.edicoes, public.apuracoes
  from authenticated;
grant select on public.apuracao to authenticated;

-- --------------------------------------------------------------- storage
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fotos', 'fotos', true, 5242880, array['image/*'])
on conflict (id) do nothing;

-- leitura publica vem do bucket publico (URL publica); as policies abaixo sao so de escrita
drop policy if exists fotos_admin_select on storage.objects;
create policy fotos_admin_select on storage.objects for select to authenticated
  using (bucket_id = 'fotos' and (select public.e_admin()));

drop policy if exists fotos_admin_insert on storage.objects;
create policy fotos_admin_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'fotos' and (select public.e_admin()));

drop policy if exists fotos_admin_update on storage.objects;
create policy fotos_admin_update on storage.objects for update to authenticated
  using (bucket_id = 'fotos' and (select public.e_admin()))
  with check (bucket_id = 'fotos' and (select public.e_admin()));

drop policy if exists fotos_admin_delete on storage.objects;
create policy fotos_admin_delete on storage.objects for delete to authenticated
  using (bucket_id = 'fotos' and (select public.e_admin()));

-- -------------------------------------------------------------- realtime
do $$
declare
  t text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  foreach t in array array['eleicao', 'comparecimento'] loop
    if not exists (
      select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
