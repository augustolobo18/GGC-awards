-- GGC Awards — 06: sem voto branco e sem voto nulo (idempotente)
-- Todo voto é em um candidato válido. votar() recusa o envio inteiro (nada é gravado) se algum
-- número não existir, for o do próprio eleitor ou, no GGC Of The Year, for de um bloqueado (admin do ano).

-- só voto em candidato
alter table public.votos drop constraint if exists votos_tipo_check;
alter table public.votos add constraint votos_tipo_check check (tipo = 'nominal');
alter table public.apuracoes drop constraint if exists apuracoes_tipo_check;
alter table public.apuracoes add constraint apuracoes_tipo_check check (tipo = 'nominal');

-- p_votos: [{categoria_id, numero}], exatamente uma entrada por categoria
create or replace function public.votar(p_votos jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid       uuid := auth.uid();
  v_conta     uuid;
  v_ano       int;
  v_status    text;
  v_n         int;
  v_linhas    int;
  v_invalido  record;
begin
  if v_uid is null then
    raise exception 'Faça login para votar' using errcode = '28000';
  end if;

  select id into v_conta from public.contas where user_id = v_uid;
  if v_conta is null then
    raise exception 'Sua conta não está autorizada a votar' using errcode = '42501';
  end if;

  select ano, status into v_ano, v_status from public.eleicao where id = 1;
  if v_status is distinct from 'aberta' then
    raise exception 'A votação não está aberta';
  end if;

  if p_votos is null or jsonb_typeof(p_votos) <> 'array' then
    raise exception 'Formato de votos inválido';
  end if;

  select count(*) into v_n from public.categorias;
  if v_n = 0 then
    raise exception 'Não há categorias para votar';
  end if;

  if jsonb_array_length(p_votos) <> v_n
     or (select count(*) from public.categorias c
          where exists (select 1 from jsonb_array_elements(p_votos) x(v)
                         where x.v ->> 'categoria_id' = c.id::text)) <> v_n then
    raise exception 'É preciso um voto para cada categoria';
  end if;

  -- cada número precisa ser de um candidato válido naquela categoria
  select c.titulo, j.v ->> 'numero' as numero into v_invalido
    from public.categorias c
    cross join lateral (
      select x.v as v from jsonb_array_elements(p_votos) x(v)
       where x.v ->> 'categoria_id' = c.id::text
       limit 1
    ) j
    left join public.contas t
           on t.numero = (j.v ->> 'numero')
          and t.id <> v_conta
          and not (c.principal and t.id in (select public.bloqueados_principal()))
   where t.id is null
   limit 1;
  if found then
    raise exception 'Número % inválido em %: escolha um candidato da lista', coalesce(v_invalido.numero, '(vazio)'), v_invalido.titulo;
  end if;

  insert into public.comparecimento (ano, user_id) values (v_ano, v_uid)
  on conflict do nothing;
  get diagnostics v_linhas = row_count;
  if v_linhas = 0 then
    raise exception 'Você já votou';
  end if;

  insert into public.votos (ano, categoria_id, conta_id, tipo)
  select v_ano, c.id, t.id, 'nominal'
    from public.categorias c
    cross join lateral (
      select x.v as v from jsonb_array_elements(p_votos) x(v)
       where x.v ->> 'categoria_id' = c.id::text
       limit 1
    ) j
    join public.contas t on t.numero = (j.v ->> 'numero')
   order by random();
end;
$$;

revoke all on function public.votar(jsonb) from public, anon;
grant execute on function public.votar(jsonb) to authenticated;
