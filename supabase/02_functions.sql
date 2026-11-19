-- GGC Awards — 02: helpers, RPCs, view, triggers e hook (idempotente)
-- Todas as funcoes security definer usam search_path vazio e nomes qualificados.

-- ---------------------------------------------------------------- helpers
create or replace function public.minha_conta()
returns uuid language sql stable security definer set search_path = '' as $$
  select id from public.contas where user_id = auth.uid()
$$;

create or replace function public.minha_role()
returns text language sql stable security definer set search_path = '' as $$
  select role from public.contas where user_id = auth.uid()
$$;

create or replace function public.e_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.minha_role() in ('admin', 'dev'), false)
$$;

-- Candidatos da urna: contas com numero, exceto a do proprio eleitor, so campos publicos
create or replace function public.candidatos_urna()
returns table (id uuid, numero text, nome text, apelido text, foto_url text)
language sql stable security definer set search_path = '' as $$
  select c.id, c.numero, c.nome, c.apelido, c.foto_url
    from public.contas c
   where c.numero is not null
     and public.minha_conta() is not null
     and c.id <> public.minha_conta()
   order by c.nome
$$;

create or replace function public.ja_votei()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.comparecimento p
      join public.eleicao e on e.id = 1 and e.ano = p.ano
     where p.user_id = auth.uid()
  )
$$;

-- ------------------------------------------------------------------ votar
-- p_votos: [{categoria_id, numero|null, branco bool}], exatamente uma entrada por categoria.
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

  -- n entradas cobrindo as n categorias = exatamente uma por categoria
  if jsonb_array_length(p_votos) <> v_n
     or (select count(*) from public.categorias c
          where exists (select 1 from jsonb_array_elements(p_votos) x(v)
                         where x.v ->> 'categoria_id' = c.id::text)) <> v_n then
    raise exception 'É preciso um voto (ou branco) para cada categoria';
  end if;

  -- presenca primeiro: a PK (ano, user_id) impede o segundo voto
  insert into public.comparecimento (ano, user_id) values (v_ano, v_uid)
  on conflict do nothing;
  get diagnostics v_linhas = row_count;
  if v_linhas = 0 then
    raise exception 'Você já votou';
  end if;

  -- numero -> conta no servidor; inexistente ou o proprio numero -> nulo
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
           on t.numero = b.numero and t.id <> v_conta and not b.branco
   order by random();
end;
$$;

-- ------------------------------------------------------------ admin / RPCs
create or replace function public.qtd_que_votaram()
returns int language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.e_admin() then
    raise exception 'Apenas admin' using errcode = '42501';
  end if;
  return (select count(*)::int from public.comparecimento p
            join public.eleicao e on e.id = 1 and e.ano = p.ano);
end;
$$;

create or replace function public.abrir_votacao()
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.e_admin() then
    raise exception 'Apenas admin' using errcode = '42501';
  end if;
  update public.eleicao set status = 'aberta', atualizado_em = now()
   where id = 1 and status = 'fechada';
  if not found then
    raise exception 'A votação só pode ser aberta quando está fechada';
  end if;
end;
$$;

create or replace function public.encerrar_votacao()
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_ano int;
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

create or replace function public.definir_ano(p_ano int)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.e_admin() then
    raise exception 'Apenas admin' using errcode = '42501';
  end if;
  if p_ano is null or p_ano < 2000 or p_ano > 2100 then
    raise exception 'Ano inválido';
  end if;
  if (select status from public.eleicao where id = 1) = 'aberta' then
    raise exception 'Encerre a votação antes de mudar o ano';
  end if;
  if exists (select 1 from public.edicoes where ano = p_ano) then
    raise exception 'O ano % já foi encerrado', p_ano;
  end if;
  update public.eleicao set ano = p_ano, status = 'fechada', atualizado_em = now() where id = 1;
end;
$$;

create or replace function public.remover_conta(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid;
begin
  if not public.e_admin() then
    raise exception 'Apenas admin' using errcode = '42501';
  end if;
  select user_id into v_user from public.contas where id = p_id;
  if not found then
    raise exception 'Participante não encontrado';
  end if;
  -- o trigger proteger_contas valida dev, si mesmo, ultimo admin e votacao aberta
  delete from public.contas where id = p_id;
  if v_user is not null then
    delete from auth.users where id = v_user;
  end if;
end;
$$;

-- ------------------------------------------------------------------- view
create or replace view public.apuracao with (security_invoker = true) as
  select v.categoria_id, v.conta_id, v.tipo, count(*)::int as votos
    from public.votos v
    join public.eleicao e on e.id = 1 and e.ano = v.ano
   group by v.categoria_id, v.conta_id, v.tipo;

-- --------------------------------------------------------------- triggers
-- Protecoes de contas (SQL direto / service role, sem auth.uid(), passam livre)
create or replace function public.proteger_contas()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_uid     uuid := auth.uid();
  v_status  text;
  v_outros  int;
begin
  if v_uid is null then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  select status into v_status from public.eleicao where id = 1;

  if tg_op = 'INSERT' then
    if new.role = 'dev' then
      raise exception 'Não é possível criar um dev pela aplicação';
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

  else -- DELETE
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

drop trigger if exists proteger_contas on public.contas;
create trigger proteger_contas
  before insert or update or delete on public.contas
  for each row execute function public.proteger_contas();

create or replace function public.travar_categorias_durante_votacao()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (select status from public.eleicao where id = 1) = 'aberta' then
    raise exception 'As categorias não podem ser alteradas com a votação aberta';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists travar_categorias_durante_votacao on public.categorias;
create trigger travar_categorias_durante_votacao
  before insert or update or delete on public.categorias
  for each row execute function public.travar_categorias_durante_votacao();

-- Marcar uma categoria como principal desmarca a anterior na mesma operacao
create or replace function public.categoria_unica_principal()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.principal then
    update public.categorias set principal = false
     where principal and id <> new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists unica_principal on public.categorias;
create trigger unica_principal
  before insert or update of principal on public.categorias
  for each row execute function public.categoria_unica_principal();

-- Liga o cadastro (auth.users) a linha convidada em contas, pelo e-mail
create or replace function public.ligar_conta()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.contas set user_id = new.id
   where email = lower(new.email) and user_id is null;
  return new;
end;
$$;

drop trigger if exists ligar_conta on auth.users;
create trigger ligar_conta
  after insert on auth.users
  for each row execute function public.ligar_conta();

-- ------------------------------------------------- hook Before User Created
-- Ligar no dashboard: Authentication > Hooks > Before User Created > Postgres function
-- > public.hook_so_convidados
create or replace function public.hook_so_convidados(event jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if exists (
    select 1 from public.contas
     where email = lower(event -> 'user' ->> 'email')
  ) then
    return '{}'::jsonb;
  end if;
  return jsonb_build_object('error', jsonb_build_object(
    'http_code', 403,
    'message', 'Esse e-mail não está na lista'
  ));
end;
$$;

-- Alternativa se o hook nao puder ser ligado (descomente; nao use junto com o hook):
-- create or replace function public.bloquear_nao_convidados() returns trigger
-- language plpgsql security definer set search_path = '' as $f$
-- begin
--   if not exists (select 1 from public.contas where email = lower(new.email)) then
--     raise exception 'Esse e-mail não está na lista';
--   end if;
--   return new;
-- end;
-- $f$;
-- drop trigger if exists bloquear_nao_convidados on auth.users;
-- create trigger bloquear_nao_convidados before insert on auth.users
--   for each row execute function public.bloquear_nao_convidados();

-- ----------------------------------------------------------------- grants
-- RPCs/helpers chamados pelo front: so authenticated
do $$
declare
  f text;
begin
  foreach f in array array[
    'public.minha_conta()', 'public.minha_role()', 'public.e_admin()',
    'public.candidatos_urna()', 'public.ja_votei()', 'public.votar(jsonb)',
    'public.qtd_que_votaram()', 'public.abrir_votacao()', 'public.encerrar_votacao()',
    'public.definir_ano(int)', 'public.remover_conta(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;

  -- funcoes de trigger: ninguem chama direto
  foreach f in array array[
    'public.proteger_contas()', 'public.travar_categorias_durante_votacao()',
    'public.categoria_unica_principal()', 'public.ligar_conta()'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
end $$;

-- hook: somente o servico de auth
revoke all on function public.hook_so_convidados(jsonb) from public, anon, authenticated;
grant usage on schema public to supabase_auth_admin;
grant execute on function public.hook_so_convidados(jsonb) to supabase_auth_admin;
grant select on public.contas to supabase_auth_admin;
