-- GGC Awards — 09: elegibilidade do GGC Of The Year (idempotente)
-- Regra: quem vence o GGC Of The Year só volta a concorrer 4 anos depois.
--   Venceu em 2026 -> fora em 2027, 2028 e 2029 -> concorre de novo em 2030.
--  * vencedores_ggc guarda o vencedor de cada ano, inclusive os anos anteriores ao site
--    (preenchidos via SQL, sem edição/apuração). Substitui edicoes.vencedor_id.
--  * O admin do ano continua fora do GGC Of The Year e o bastão continua indo para o
--    vencedor ao publicar (regras do 05/07, sem mudança).

-- ------------------------------------------------------------ tabela
create table if not exists public.vencedores_ggc (
  ano       int primary key check (ano between 2000 and 2100),
  conta_id  uuid references public.contas (id) on delete set null,
  nome      text not null   -- cópia: o histórico continua legível se a conta for removida
);

alter table public.vencedores_ggc enable row level security;
drop policy if exists vencedores_ggc_select on public.vencedores_ggc;
create policy vencedores_ggc_select on public.vencedores_ggc for select to authenticated
  using ((select public.e_admin()));
-- escrita só por encerrar_votacao() / desempatar() (security definer) ou SQL direto
revoke all on public.vencedores_ggc from anon;
revoke insert, update, delete, truncate, references, trigger on public.vencedores_ggc from authenticated;

-- traz o que já estiver em edicoes.vencedor_id e remove a coluna antiga
do $$
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'edicoes' and column_name = 'vencedor_id') then
    execute $q$
      insert into public.vencedores_ggc (ano, conta_id, nome)
      select d.ano, d.vencedor_id, c.nome
        from public.edicoes d join public.contas c on c.id = d.vencedor_id
      on conflict (ano) do nothing
    $q$;
    alter table public.edicoes drop column vencedor_id;
  end if;
end $$;

-- ------------------------------------------------------------ carência
-- Vencedores que ainda não podem concorrer no ano atual: venceram nos 3 anos anteriores
create or replace function public.vencedores_em_carencia()
returns table (conta_id uuid, ano int)
language sql stable security definer set search_path = '' as $$
  select v.conta_id, v.ano
    from public.vencedores_ggc v
    join public.eleicao e on e.id = 1
   where v.conta_id is not null
     and v.ano >= e.ano - 3
     and v.ano < e.ano
$$;

-- Quem não pode ser votado no GGC Of The Year agora: admins + vencedores em carência.
-- votar() e candidatos_urna() usam esta função (votar() do 06 não muda).
create or replace function public.bloqueados_principal()
returns setof uuid language sql stable security definer set search_path = '' as $$
  select id from public.contas where role = 'admin'
  union
  select conta_id from public.vencedores_em_carencia()
$$;

-- urna: venceu_em = último ano em que venceu, se ainda estiver em carência (para explicar o bloqueio)
drop function if exists public.candidatos_urna();
create function public.candidatos_urna()
returns table (id uuid, numero text, nome text, apelido text, foto_url text,
               bloqueado_principal boolean, venceu_em int)
language sql stable security definer set search_path = '' as $$
  select c.id, c.numero, c.nome, c.apelido, c.foto_url,
         c.id in (select public.bloqueados_principal()) as bloqueado_principal,
         (select max(x.ano) from public.vencedores_em_carencia() x where x.conta_id = c.id) as venceu_em
    from public.contas c
   where c.numero is not null
     and public.minha_conta() is not null
     and c.id <> public.minha_conta()
   order by c.nome
$$;

-- ------------------------------------------------------------ encerrar: vencedor vai para vencedores_ggc
create or replace function public.encerrar_votacao()
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_ano int;
  v_vencedor uuid;
begin
  if not public.e_admin() then
    raise exception 'Apenas admin' using errcode = '42501';
  end if;

  select ano into v_ano from public.eleicao where id = 1 and status = 'aberta';
  if v_ano is null then
    raise exception 'A votação não está aberta';
  end if;

  insert into public.edicoes (ano, eleitores, votaram)
  values (
    v_ano,
    (select count(*) from public.contas where user_id is not null),
    (select count(*) from public.comparecimento where ano = v_ano)
  );

  -- vencedor só se for único; empate fica sem linha até o dev desempatar
  if (select count(*) from public.topo_principal(v_ano)) = 1 then
    select conta_id into v_vencedor from public.topo_principal(v_ano);
    insert into public.vencedores_ggc (ano, conta_id, nome)
    select v_ano, c.id, c.nome from public.contas c where c.id = v_vencedor;
  end if;

  insert into public.apuracoes
    (ano, categoria_ordem, categoria_titulo, principal, tipo, numero, nome, apelido, foto_url, votos)
  select v_ano, c.ordem, c.titulo, c.principal, v.tipo,
         t.numero, t.nome, t.apelido, t.foto_url, count(*)::int
    from public.votos v
    join public.categorias c on c.id = v.categoria_id
    left join public.contas t on t.id = v.conta_id
   where v.ano = v_ano
   group by c.id, c.ordem, c.titulo, c.principal, v.tipo, t.id, t.numero, t.nome, t.apelido, t.foto_url;

  update public.eleicao set status = 'encerrada', atualizado_em = now() where id = 1;
end;
$$;

-- ------------------------------------------------------------ card Edição do menu
-- vencedor/empatados do ano atual (status encerrada) + quem está fora do GGC Of The Year agora
create or replace function public.situacao_ggc()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_ano int;
  v_venc uuid;
begin
  if not public.e_admin() then
    raise exception 'Apenas admin' using errcode = '42501';
  end if;
  select ano into v_ano from public.eleicao where id = 1;
  select conta_id into v_venc from public.vencedores_ggc where ano = v_ano;
  return jsonb_build_object(
    'ano', v_ano,
    'vencedor', (select jsonb_build_object('id', c.id, 'nome', c.nome, 'apelido', c.apelido, 'numero', c.numero)
                   from public.contas c where c.id = v_venc),
    'empatados', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.nome, 'apelido', c.apelido, 'numero', c.numero) order by c.nome)
                             from public.topo_principal(v_ano) t join public.contas c on c.id = t.conta_id), '[]'::jsonb),
    'fora', coalesce((select jsonb_agg(jsonb_build_object('nome', c.nome, 'apelido', c.apelido,
                                                          'admin', c.role = 'admin', 'venceu_em', x.ano)
                                       order by x.ano desc nulls first, c.nome)
                        from public.contas c
                        left join (select conta_id, max(ano) as ano from public.vencedores_em_carencia()
                                    group by conta_id) x on x.conta_id = c.id
                       where c.id in (select public.bloqueados_principal())), '[]'::jsonb)
  );
end;
$$;

-- ------------------------------------------------------------ desempate (só dev, antes de publicar)
create or replace function public.desempatar(p_conta uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_ano int;
begin
  if public.minha_role() is distinct from 'dev' then
    raise exception 'Só o dev pode desempatar' using errcode = '42501';
  end if;
  select ano into v_ano from public.eleicao where id = 1 and status = 'encerrada';
  if v_ano is null then
    raise exception 'Só dá para desempatar com a votação encerrada (antes de publicar)';
  end if;
  if exists (select 1 from public.vencedores_ggc where ano = v_ano) then
    raise exception 'O GGC Of The Year de % já tem vencedor', v_ano;
  end if;
  if not exists (select 1 from public.topo_principal(v_ano) where conta_id = p_conta) then
    raise exception 'Escolha um dos empatados';
  end if;
  insert into public.vencedores_ggc (ano, conta_id, nome)
  select v_ano, c.id, c.nome from public.contas c where c.id = p_conta;
end;
$$;

-- ------------------------------------------------------------ publicar + passar o bastão
create or replace function public.publicar_resultados()
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_ano  int;
  v_venc uuid;
begin
  if not public.e_admin() then
    raise exception 'Apenas admin' using errcode = '42501';
  end if;
  select ano into v_ano from public.eleicao where id = 1 and status = 'encerrada';
  if v_ano is null then
    raise exception 'Só dá para publicar com a votação encerrada';
  end if;

  select conta_id into v_venc from public.vencedores_ggc where ano = v_ano;
  if not found and exists (select 1 from public.topo_principal(v_ano)) then
    raise exception 'O GGC Of The Year de % empatou: o dev precisa escolher o vencedor antes de publicar', v_ano;
  end if;

  update public.edicoes set publicada_em = now() where ano = v_ano;

  -- bastão: vencedor vira admin, admin atual volta a votante (dev continua dev)
  if v_venc is not null then
    perform set_config('ggc.troca_automatica', 'on', true);
    update public.contas set role = 'votante' where role = 'admin' and id <> v_venc;
    update public.contas set role = 'admin' where id = v_venc and role = 'votante';
    perform set_config('ggc.troca_automatica', 'off', true);
  end if;

  update public.eleicao set status = 'publicada', atualizado_em = now() where id = 1;
end;
$$;

-- ------------------------------------------------------------ novo ano: não reusa ano com vencedor
create or replace function public.definir_ano(p_ano int, p_limpar_categorias boolean default false)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_status text;
begin
  if not public.e_admin() then
    raise exception 'Apenas admin' using errcode = '42501';
  end if;
  if p_ano is null or p_ano < 2000 or p_ano > 2100 then
    raise exception 'Ano inválido';
  end if;
  select status into v_status from public.eleicao where id = 1;
  if v_status = 'aberta' then
    raise exception 'Encerre a votação antes de mudar o ano';
  end if;
  if v_status = 'encerrada' then
    raise exception 'Publique os resultados antes de começar um novo ano';
  end if;
  if exists (select 1 from public.edicoes where ano = p_ano)
     or exists (select 1 from public.vencedores_ggc where ano = p_ano) then
    raise exception 'O ano % já foi encerrado', p_ano;
  end if;

  update public.eleicao set ano = p_ano, status = 'fechada', atualizado_em = now() where id = 1;

  if p_limpar_categorias then
    delete from public.categorias where true;
  end if;
end;
$$;

-- ------------------------------------------------------------ grants
do $$
declare
  f text;
begin
  foreach f in array array[
    'public.candidatos_urna()', 'public.encerrar_votacao()', 'public.situacao_ggc()',
    'public.desempatar(uuid)', 'public.publicar_resultados()', 'public.definir_ano(int, boolean)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  -- só uso interno (outras funções e policies)
  foreach f in array array['public.bloqueados_principal()', 'public.vencedores_em_carencia()'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
end $$;
