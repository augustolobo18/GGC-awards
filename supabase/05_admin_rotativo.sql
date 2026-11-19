-- GGC Awards — 05: admin rotativo (idempotente)
-- Regra: o admin do ano é o vencedor do GGC Of The Year do ano anterior.
--  * O admin (e o vencedor do ano anterior) não pode ser votado no GGC Of The Year do ano vigente;
--    nas outras categorias ele concorre normalmente.
--  * Ao encerrar, o vencedor único do GGC Of The Year fica gravado em edicoes.vencedor_id.
--  * Empate: o dev escolhe o vencedor (desempatar) antes de começar o novo ano.
--  * Ao "Começar novo ano", o admin atual vira votante e o vencedor vira admin (dev continua dev).
--  * Troca manual de papel: só o dev.

alter table public.edicoes
  add column if not exists vencedor_id uuid references public.contas (id) on delete set null;

-- ------------------------------------------------------------ bloqueio
-- Quem não pode ser votado no GGC Of The Year agora: admins + vencedor do último ano encerrado
create or replace function public.bloqueados_principal()
returns setof uuid language sql stable security definer set search_path = '' as $$
  select id from public.contas where role = 'admin'
  union
  select d.vencedor_id
    from public.edicoes d
   where d.vencedor_id is not null
     and d.ano = (select max(x.ano) from public.edicoes x
                   where x.ano < (select e.ano from public.eleicao e where e.id = 1))
$$;

-- candidatos da urna agora dizem se estão bloqueados no GGC Of The Year
drop function if exists public.candidatos_urna();
create function public.candidatos_urna()
returns table (id uuid, numero text, nome text, apelido text, foto_url text, bloqueado_principal boolean)
language sql stable security definer set search_path = '' as $$
  select c.id, c.numero, c.nome, c.apelido, c.foto_url,
         c.id in (select public.bloqueados_principal()) as bloqueado_principal
    from public.contas c
   where c.numero is not null
     and public.minha_conta() is not null
     and c.id <> public.minha_conta()
   order by c.nome
$$;

-- ------------------------------------------------------------ votar
-- Igual ao 02, com mais uma regra: no GGC Of The Year, número de bloqueado vira nulo
create or replace function public.votar(p_votos jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid     uuid := auth.uid();
  v_conta   uuid;
  v_ano     int;
  v_status  text;
  v_n       int;
  v_linhas  int;
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
    raise exception 'É preciso um voto (ou branco) para cada categoria';
  end if;

  insert into public.comparecimento (ano, user_id) values (v_ano, v_uid)
  on conflict do nothing;
  get diagnostics v_linhas = row_count;
  if v_linhas = 0 then
    raise exception 'Você já votou';
  end if;

  insert into public.votos (ano, categoria_id, conta_id, tipo)
  select v_ano,
         c.id,
         case when b.branco then null else t.id end,
         case when b.branco then 'branco'
              when t.id is not null then 'nominal'
              else 'nulo' end
    from public.categorias c
    cross join lateral (
      select x.v as v from jsonb_array_elements(p_votos) x(v)
       where x.v ->> 'categoria_id' = c.id::text
       limit 1
    ) j
    cross join lateral (
      select coalesce((j.v ->> 'branco')::boolean, false) as branco,
             nullif(j.v ->> 'numero', '') as numero
    ) b
    left join public.contas t
           on t.numero = b.numero
          and t.id <> v_conta
          and not b.branco
          and not (c.principal and t.id in (select public.bloqueados_principal()))
   order by random();
end;
$$;

-- ------------------------------------------------------------ vencedor do GGC Of The Year
-- Candidatos empatados (ou o único) no topo do GGC Of The Year de um ano
create or replace function public.topo_principal(p_ano int)
returns table (conta_id uuid, votos int)
language sql stable security definer set search_path = '' as $$
  with contagem as (
    select v.conta_id, count(*)::int as votos
      from public.votos v
      join public.categorias c on c.id = v.categoria_id and c.principal
     where v.ano = p_ano and v.tipo = 'nominal' and v.conta_id is not null
     group by v.conta_id
  )
  select conta_id, votos from contagem
   where votos = (select max(votos) from contagem)
$$;

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

  -- vencedor só se for único; empate fica nulo até o dev desempatar
  if (select count(*) from public.topo_principal(v_ano)) = 1 then
    select conta_id into v_vencedor from public.topo_principal(v_ano);
  end if;

  insert into public.edicoes (ano, eleitores, votaram, vencedor_id)
  values (
    v_ano,
    (select count(*) from public.contas where user_id is not null),
    (select count(*) from public.comparecimento where ano = v_ano),
    v_vencedor
  );

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

-- Situação do GGC Of The Year do ano atual (para o card Edição do menu)
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
  select vencedor_id into v_venc from public.edicoes where ano = v_ano;
  return jsonb_build_object(
    'ano', v_ano,
    'vencedor', (select jsonb_build_object('id', c.id, 'nome', c.nome, 'apelido', c.apelido, 'numero', c.numero)
                   from public.contas c where c.id = v_venc),
    'empatados', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'nome', c.nome, 'apelido', c.apelido, 'numero', c.numero) order by c.nome)
                             from public.topo_principal(v_ano) t join public.contas c on c.id = t.conta_id), '[]'::jsonb)
  );
end;
$$;

-- Dev escolhe o vencedor quando o GGC Of The Year empatou
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
    raise exception 'Só dá para desempatar com a votação encerrada';
  end if;
  if (select vencedor_id from public.edicoes where ano = v_ano) is not null then
    raise exception 'O GGC Of The Year de % já tem vencedor', v_ano;
  end if;
  if not exists (select 1 from public.topo_principal(v_ano) where conta_id = p_conta) then
    raise exception 'Escolha um dos empatados';
  end if;
  update public.edicoes set vencedor_id = p_conta where ano = v_ano;
end;
$$;

-- ------------------------------------------------------------ novo ano + troca de admin
create or replace function public.definir_ano(p_ano int)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_atual   int;
  v_status  text;
  v_venc    uuid;
begin
  if not public.e_admin() then
    raise exception 'Apenas admin' using errcode = '42501';
  end if;
  if p_ano is null or p_ano < 2000 or p_ano > 2100 then
    raise exception 'Ano inválido';
  end if;
  select ano, status into v_atual, v_status from public.eleicao where id = 1;
  if v_status = 'aberta' then
    raise exception 'Encerre a votação antes de mudar o ano';
  end if;
  if exists (select 1 from public.edicoes where ano = p_ano) then
    raise exception 'O ano % já foi encerrado', p_ano;
  end if;

  -- Começar novo ano (depois de encerrar): o vencedor do GGC Of The Year vira o admin
  if v_status = 'encerrada' then
    select vencedor_id into v_venc from public.edicoes where ano = v_atual;
    if v_venc is null and exists (select 1 from public.topo_principal(v_atual)) then
      raise exception 'O GGC Of The Year de % empatou: o dev precisa escolher o vencedor antes de começar o novo ano', v_atual;
    end if;
    if v_venc is not null then
      perform set_config('ggc.troca_automatica', 'on', true);
      update public.contas set role = 'votante' where role = 'admin' and id <> v_venc;
      update public.contas set role = 'admin' where id = v_venc and role = 'votante';
      perform set_config('ggc.troca_automatica', 'off', true);
    end if;
  end if;

  update public.eleicao set ano = p_ano, status = 'fechada', atualizado_em = now() where id = 1;
end;
$$;

-- ------------------------------------------------------------ proteções de contas
create or replace function public.proteger_contas()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_uid     uuid := auth.uid();
  v_status  text;
  v_outros  int;
  v_dev     boolean;
begin
  -- SQL direto / service role e a troca automática do novo ano passam livre
  if v_uid is null or current_setting('ggc.troca_automatica', true) = 'on' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  select status into v_status from public.eleicao where id = 1;
  v_dev := public.minha_role() = 'dev';

  if tg_op = 'INSERT' then
    if new.role = 'dev' then
      raise exception 'Não é possível criar um dev pela aplicação';
    end if;
    if new.role = 'admin' and not v_dev then
      raise exception 'Só o dev define o admin. O admin muda sozinho a cada ano.';
    end if;
    if new.user_id is not null then
      raise exception 'user_id é preenchido só no cadastro da pessoa';
    end if;
    return new;

  elsif tg_op = 'UPDATE' then
    if new.user_id is distinct from old.user_id then
      raise exception 'user_id não pode ser alterado';
    end if;
    if old.user_id is not null and new.email is distinct from old.email then
      raise exception 'O e-mail de uma conta ativa não pode ser alterado';
    end if;
    if new.role is distinct from old.role then
      if old.role = 'dev' or new.role = 'dev' then
        raise exception 'O papel dev não pode ser alterado pela aplicação';
      end if;
      if not v_dev then
        raise exception 'Só o dev define o admin. O admin muda sozinho a cada ano.';
      end if;
      if old.user_id = v_uid then
        raise exception 'Você não pode mudar o próprio papel';
      end if;
      if old.role = 'admin' then
        select count(*) into v_outros from public.contas
         where role in ('admin', 'dev') and id <> old.id;
        if v_outros = 0 then
          raise exception 'Não é possível rebaixar o último admin';
        end if;
      end if;
    end if;
    if v_status = 'aberta' and new.numero is distinct from old.numero then
      raise exception 'Não é possível mudar o número com a votação aberta';
    end if;
    return new;

  else
    if old.role = 'dev' then
      raise exception 'Não é possível remover um dev pela aplicação';
    end if;
    if old.user_id = v_uid then
      raise exception 'Você não pode remover a si mesmo';
    end if;
    if old.role = 'admin' then
      select count(*) into v_outros from public.contas
       where role in ('admin', 'dev') and id <> old.id;
      if v_outros = 0 then
        raise exception 'Não é possível remover o último admin';
      end if;
    end if;
    if v_status = 'aberta' then
      raise exception 'Não é possível remover participantes com a votação aberta';
    end if;
    return old;
  end if;
end;
$$;

-- ------------------------------------------------------------ grants
do $$
declare
  f text;
begin
  foreach f in array array[
    'public.candidatos_urna()', 'public.votar(jsonb)', 'public.encerrar_votacao()',
    'public.definir_ano(int)', 'public.situacao_ggc()', 'public.desempatar(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  -- só uso interno (outras funções e policies)
  foreach f in array array['public.bloqueados_principal()', 'public.topo_principal(int)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
end $$;
