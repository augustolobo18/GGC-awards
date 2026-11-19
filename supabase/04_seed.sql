-- GGC Awards — 04: seed (idempotente)

insert into public.eleicao (id, ano, status)
values (1, 2026, 'fechada')
on conflict (id) do nothing;

-- Conta dev. O e-mail e um PLACEHOLDER: o real entra so via execute_sql, nunca neste arquivo:
--   update public.contas set email = lower('<email real>') where email = lower('SEU_EMAIL_AQUI');
-- (a coluna exige e-mail minusculo, por isso lower(): fica gravado 'seu_email_aqui')
insert into public.contas (email, nome, apelido, numero, role)
values (lower('SEU_EMAIL_AQUI'), 'Dev', null, null, 'dev')
on conflict (email) do nothing;

-- Categorias de exemplo (so se ainda nao existir nenhuma)
insert into public.categorias (ordem, titulo, descricao, principal)
select v.ordem, v.titulo, v.descricao, v.principal
  from (values
    (1, 'Mais palestrinha',   'Quem mais marcou presença com a resenha do ano', false),
    (2, 'Melhor no volante',  'Quem dirige (ou joga) melhor do grupo',           false),
    (3, 'GGC Of The Year',    'O grande prêmio da galera',                       true)
  ) as v (ordem, titulo, descricao, principal)
 where not exists (select 1 from public.categorias);
