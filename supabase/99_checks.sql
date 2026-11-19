-- GGC Awards — 99: checks (rode DEPOIS de 01-06; nada persiste)
-- Cada bloco falha com ASSERT se algo estiver errado.

-- ------------------------------------------------------------ 1. estaticos
do $$
declare
  v_n int;
  v_cols text[];
begin
  -- RLS ligado nas 7 tabelas
  select count(*) into v_n
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
     and c.relname in ('contas','categorias','eleicao','comparecimento','votos','edicoes','apuracoes');
  assert v_n = 7, format('RLS ligado em %s de 7 tabelas', v_n);

  -- votos: sem eleitor e sem timestamp
  select array_agg(column_name::text order by column_name) into v_cols
    from information_schema.columns where table_schema = 'public' and table_name = 'votos';
  assert v_cols = array['ano','categoria_id','conta_id','id','tipo'],
    format('colunas de votos inesperadas: %s', v_cols);

  -- exatamente uma categoria principal
  select count(*) into v_n from public.categorias where principal;
  assert v_n = 1, format('categorias principais: %s (esperado 1)', v_n);

  -- eleicao com 1 linha (id = 1)
  select count(*) into v_n from public.eleicao;
  assert v_n = 1, 'eleicao deve ter exatamente 1 linha';

  -- conta dev existe (placeholder ou e-mail real)
  assert exists (select 1 from public.contas where role = 'dev'), 'conta dev ausente';

  -- grants de funcoes
  assert not has_function_privilege('anon', 'public.votar(jsonb)', 'execute'), 'anon executa votar';
  assert has_function_privilege('authenticated', 'public.votar(jsonb)', 'execute'), 'authenticated nao executa votar';
  assert not has_function_privilege('anon', 'public.e_admin()', 'execute'), 'anon executa e_admin';
  assert has_function_privilege('supabase_auth_admin', 'public.hook_so_convidados(jsonb)', 'execute'), 'hook sem grant';
  assert not has_function_privilege('authenticated', 'public.hook_so_convidados(jsonb)', 'execute'), 'authenticated executa o hook';
  assert not has_function_privilege('anon', 'public.hook_so_convidados(jsonb)', 'execute'), 'anon executa o hook';
  assert has_table_privilege('supabase_auth_admin', 'public.contas', 'select'), 'supabase_auth_admin sem select em contas';

  -- storage e realtime
  assert exists (select 1 from storage.buckets where id = 'fotos' and public and file_size_limit = 5242880),
    'bucket fotos ausente ou mal configurado';
  select count(*) into v_n from pg_publication_tables
   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename in ('eleicao','comparecimento');
  assert v_n = 2, 'realtime deve publicar eleicao e comparecimento';

  raise notice 'checks estaticos OK';
end $$;

-- ------------------------------------------------ 2. comportamento (rollback)
-- Simula auth com request.jwt.claims + set local role. Tudo roda numa sub-transacao
-- que termina com uma excecao propositada, entao NADA persiste.
-- Pre-requisito: seed aplicado (>= 1 categoria) e votacao em qualquer estado.
do $$
declare
  v_a    uuid := gen_random_uuid();
  v_b    uuid := gen_random_uuid();
  v_adm  uuid := gen_random_uuid();
  v_payload jsonb;
  v_payload_b jsonb;
  v_n    int;
  v_base int;
  v_ok   boolean;
  v_cat  int;
  v_id_a uuid;
  v_id_b uuid;
begin
  begin
    -- ---- setup (como postgres, sem claims)
    select count(*) into v_cat from public.categorias;
    assert v_cat >= 1, 'rode 04_seed.sql antes (>= 1 categoria)';
    assert not exists (select 1 from public.contas where numero in ('91','92')),
      'numeros 91/92 ja usados; o teste precisa deles livres';

    update public.eleicao set status = 'fechada' where id = 1;
    insert into public.contas (email, nome, apelido, numero, role) values
      ('teste-a@ggc.invalid',   'Teste A',   'A',   '91', 'votante'),
      ('teste-b@ggc.invalid',   'Teste B',   'B',   '92', 'votante'),
      ('teste-adm@ggc.invalid', 'Teste Adm', 'Adm', null, 'admin');
    select id into v_id_a from public.contas where email = 'teste-a@ggc.invalid';
    select id into v_id_b from public.contas where email = 'teste-b@ggc.invalid';

    -- hook
    assert public.hook_so_convidados(jsonb_build_object('user', jsonb_build_object('email', 'Teste-A@GGC.invalid'))) = '{}'::jsonb,
      'hook deveria aceitar e-mail convidado (case-insensitive)';
    assert public.hook_so_convidados(jsonb_build_object('user', jsonb_build_object('email', 'intruso@ggc.invalid')))
             -> 'error' ->> 'http_code' = '403',
      'hook deveria recusar e-mail fora da lista com 403';

    -- trigger ligar_conta
    insert into auth.users (id, email) values
      (v_a, 'teste-a@ggc.invalid'), (v_b, 'teste-b@ggc.invalid'), (v_adm, 'teste-adm@ggc.invalid');
    assert (select user_id from public.contas where email = 'teste-a@ggc.invalid') = v_a, 'ligar_conta nao ligou A';
    assert (select user_id from public.contas where email = 'teste-adm@ggc.invalid') = v_adm, 'ligar_conta nao ligou Adm';

    update public.eleicao set status = 'aberta' where id = 1;

    -- sem branco/nulo: A vota em B (92) em todas; B vota em A (91) em todas
    select jsonb_agg(jsonb_build_object('categoria_id', id, 'numero', '92')) into v_payload from public.categorias;
    select jsonb_agg(jsonb_build_object('categoria_id', id, 'numero', '91')) into v_payload_b from public.categorias;

    select count(*) into v_base from public.votos;

    -- ---- votante A
    perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_a::text, true);
    set local role authenticated;

    assert not public.ja_votei(), 'A ainda nao votou';

    -- urna nao lista o proprio
    assert not exists (select 1 from public.candidatos_urna() where numero = '91'), 'urna lista o proprio eleitor';
    assert exists (select 1 from public.candidatos_urna() where numero = '92'), 'urna deveria listar B';

    -- votante nao encerra nem edita contas
    v_ok := false;
    begin perform public.encerrar_votacao(); exception when others then v_ok := true; end;
    assert v_ok, 'votante conseguiu chamar encerrar_votacao';
    update public.contas set role = 'admin' where user_id = v_a;
    get diagnostics v_n = row_count;
    assert v_n = 0, 'votante conseguiu editar contas';

    -- categoria faltando
    v_ok := false;
    begin perform public.votar(v_payload - 0); exception when others then v_ok := true; end;
    assert v_ok, 'votar aceitou voto sem uma categoria';
    -- proprio numero (91), numero inexistente (93) e branco sao recusados por inteiro
    v_ok := false;
    begin perform public.votar(v_payload_b); exception when others then v_ok := true; end;
    assert v_ok, 'votar aceitou o proprio numero';
    v_ok := false;
    begin perform public.votar((select jsonb_agg(jsonb_build_object('categoria_id', id, 'numero', '93')) from public.categorias)); exception when others then v_ok := true; end;
    assert v_ok, 'votar aceitou numero inexistente';
    v_ok := false;
    begin perform public.votar((select jsonb_agg(jsonb_build_object('categoria_id', id, 'numero', null, 'branco', true)) from public.categorias)); exception when others then v_ok := true; end;
    assert v_ok, 'votar aceitou branco';
    assert not public.ja_votei(), 'voto invalido nao pode registrar comparecimento';

    perform public.votar(v_payload);
    assert public.ja_votei(), 'A deveria constar como votou';

    -- segundo voto bloqueado
    v_ok := false;
    begin perform public.votar(v_payload); exception when others then v_ok := true; end;
    assert v_ok, 'A votou duas vezes';

    -- RLS: votante nao le votos e so ve a propria conta
    select count(*) into v_n from public.votos;
    assert v_n = 0, 'votante enxerga votos';
    select count(*) into v_n from public.contas;
    assert v_n = 1, format('votante enxerga %s contas (esperado 1)', v_n);
    v_ok := false;
    begin perform public.qtd_que_votaram(); exception when others then v_ok := true; end;
    assert v_ok, 'votante chamou qtd_que_votaram';

    -- ---- votante B (vota em A)
    perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_b::text, true);
    perform public.votar(v_payload_b);

    -- ---- admin
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);

    assert public.e_admin(), 'Adm deveria ser admin';
    assert public.qtd_que_votaram() >= 2, 'qtd_que_votaram deveria contar A e B';

    v_ok := false;
    begin update public.contas set role = 'votante' where role = 'dev'; exception when others then v_ok := true; end;
    assert v_ok, 'admin rebaixou o dev';
    v_ok := false;
    begin insert into public.contas (email, nome, role) values ('outro-dev@ggc.invalid', 'X', 'dev'); exception when others then v_ok := true; end;
    assert v_ok, 'admin criou um dev';
    v_ok := false;
    begin update public.contas set role = 'votante' where user_id = v_adm; exception when others then v_ok := true; end;
    assert v_ok, 'admin mudou o proprio papel';
    v_ok := false;
    begin update public.contas set numero = '93' where id = v_id_a; exception when others then v_ok := true; end;
    assert v_ok, 'numero mudou com a votacao aberta';
    v_ok := false;
    begin perform public.remover_conta(v_id_a); exception when others then v_ok := true; end;
    assert v_ok, 'participante removido com a votacao aberta';
    v_ok := false;
    begin insert into public.categorias (ordem, titulo) values (99, 'Nao pode'); exception when others then v_ok := true; end;
    assert v_ok, 'categoria criada com a votacao aberta';

    -- ---- resultado (como postgres, sem claims)
    reset role;
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);

    select count(*) into v_n from public.votos;
    assert v_n - v_base = 2 * v_cat, format('esperado %s votos novos, vieram %s', 2 * v_cat, v_n - v_base);
    -- cada um recebeu um voto por categoria (o do outro), e so existem votos em candidatos
    assert (select count(*) from public.votos where conta_id = v_id_a) = v_cat, 'A deveria ter um voto por categoria (os de B)';
    assert (select count(*) from public.votos where conta_id = v_id_b) = v_cat, 'B deveria ter um voto por categoria (os de A)';
    assert (select count(*) from public.votos where tipo <> 'nominal' or conta_id is null) = 0, 'voto sem candidato gravado';

    -- encerrar congela (como admin de novo)
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', v_adm::text, true);
    perform public.encerrar_votacao();
    assert (select status from public.eleicao where id = 1) = 'encerrada', 'status deveria ser encerrada';
    assert exists (select 1 from public.edicoes e where e.ano = (select ano from public.eleicao where id = 1)), 'edicao nao congelada';
    assert exists (select 1 from public.apuracoes a where a.nome = 'Teste A'), 'apuracao nao congelou nome';

    -- desfaz tudo
    raise exception '__ggc_rollback__';
  exception
    when raise_exception then
      if sqlerrm <> '__ggc_rollback__' then
        raise;
      end if;
  end;

  reset role;
  raise notice 'checks de comportamento OK (nada persistiu)';
end $$;

-- confirma que nada vazou
do $$
begin
  assert not exists (select 1 from public.contas where email like '%@ggc.invalid'), 'sobrou conta de teste';
  assert not exists (select 1 from auth.users where email like '%@ggc.invalid'), 'sobrou auth.users de teste';
end $$;
