-- GGC Awards — 07: publicar resultados (idempotente)
-- Fluxo: fechada -> aberta -> encerrada -> publicada -> (Começar novo ano) fechada
--  * encerrada: resultado congelado, visível só para admin/dev (cerimônia).
--  * publicar_resultados(): libera o ano para todos e passa o bastão de admin ao vencedor
--    do GGC Of The Year (empate precisa ser desempatado pelo dev antes).
--  * definir_ano() como "Começar novo ano" só depois de publicar; pode limpar as categorias.
--  * limpar_categorias(): admin apaga todas as categorias (fora da votação aberta).
--  * Votantes leem edicoes/apuracoes só de anos publicados.

-- status novo
alter table public.eleicao drop constraint if exists eleicao_status_check;
alter table public.eleicao add constraint eleicao_status_check
  check (status in ('fechada', 'aberta', 'encerrada', 'publicada'));

alter table public.edicoes add column if not exists publicada_em timestamptz;

-- ------------------------------------------------------------ visibilidade
drop policy if exists edicoes_select on public.edicoes;
create policy edicoes_select on public.edicoes for select to authenticated
  using ((select public.e_admin()) or publicada_em is not null);

drop policy if exists apuracoes_select on public.apuracoes;
create policy apuracoes_select on public.apuracoes for select to authenticated
  using (
    (select public.e_admin())
    or exists (select 1 from public.edicoes d where d.ano = apuracoes.ano and d.publicada_em is not null)
  );

-- ------------------------------------------------------------ abrir: precisa de categorias e de uma principal
create or replace function public.abrir_votacao()
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.e_admin() then
    raise exception 'Apenas admin' using errcode = '42501';
  end if;
  if not exists (select 1 from public.categorias) then
    raise exception 'Cadastre as categorias antes de abrir a votação';
  end if;
  if not exists (select 1 from public.categorias where principal) then
    raise exception 'Marque o GGC Of The Year (categoria principal) antes de abrir a votação';
  end if;
  update public.eleicao set status = 'aberta', atualizado_em = now()
   where id = 1 and status = 'fechada';
  if not found then
    raise exception 'A votação só pode ser aberta quando está fechada';
  end if;
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

  select vencedor_id into v_venc from public.edicoes where ano = v_ano;
  if v_venc is null and exists (select 1 from public.topo_principal(v_ano)) then
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

-- ------------------------------------------------------------ desempate: só antes de publicar
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
  if (select vencedor_id from public.edicoes where ano = v_ano) is not null then
    raise exception 'O GGC Of The Year de % já tem vencedor', v_ano;
  end if;
  if not exists (select 1 from public.topo_principal(v_ano) where conta_id = p_conta) then
    raise exception 'Escolha um dos empatados';
  end if;
  update public.edicoes set vencedor_id = p_conta where ano = v_ano;
end;
$$;

-- ------------------------------------------------------------ limpar categorias
create or replace function public.limpar_categorias()
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.e_admin() then
    raise exception 'Apenas admin' using errcode = '42501';
  end if;
  if (select status from public.eleicao where id = 1) = 'aberta' then
    raise exception 'As categorias não podem ser alteradas com a votação aberta';
  end if;
  -- votos antigos ficam com categoria_id nulo; o histórico está congelado em apuracoes
  delete from public.categorias where true;
end;
$$;

-- ------------------------------------------------------------ novo ano (sem troca de admin; ela é na publicação)
drop function if exists public.definir_ano(int);
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
  if exists (select 1 from public.edicoes where ano = p_ano) then
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
    'public.abrir_votacao()', 'public.publicar_resultados()', 'public.desempatar(uuid)',
    'public.limpar_categorias()', 'public.definir_ano(int, boolean)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
