-- GGC Awards — 01: schema (idempotente)
-- Tabelas unicas (sem ano): contas, categorias, eleicao.
-- Tabelas com ano: comparecimento, votos, edicoes, apuracoes.

create extension if not exists pgcrypto;

-- Participantes = votantes = candidatos
create table if not exists public.contas (
  id         uuid primary key default gen_random_uuid(),
  email      text not null unique check (email = lower(email)),
  nome       text not null,
  apelido    text,
  numero     text unique check (numero ~ '^\d{2}$'),
  foto_url   text,
  role       text not null default 'votante' check (role in ('votante', 'admin', 'dev')),
  user_id    uuid unique references auth.users (id) on delete set null,
  criado_em  timestamptz not null default now()
);

create table if not exists public.categorias (
  id         uuid primary key default gen_random_uuid(),
  ordem      int not null default 0,
  titulo     text not null,
  descricao  text,
  principal  boolean not null default false
);

-- so uma categoria principal (GGC Of The Year)
create unique index if not exists categorias_uma_principal
  on public.categorias (principal) where principal;

-- linha unica de estado da eleicao
create table if not exists public.eleicao (
  id             int primary key check (id = 1),
  ano            int not null,
  status         text not null default 'fechada' check (status in ('fechada', 'aberta', 'encerrada')),
  atualizado_em  timestamptz not null default now()
);

-- QUEM votou (sem dizer em quem)
create table if not exists public.comparecimento (
  ano      int not null,
  user_id  uuid not null,
  primary key (ano, user_id)
);

-- O QUE foi votado: sem eleitor, sem timestamp, id aleatorio
create table if not exists public.votos (
  id            uuid primary key default gen_random_uuid(),
  ano           int not null,
  categoria_id  uuid references public.categorias (id) on delete set null,
  conta_id      uuid references public.contas (id) on delete set null,
  tipo          text not null check (tipo in ('nominal', 'branco', 'nulo'))
);
create index if not exists votos_ano_categoria on public.votos (ano, categoria_id);

-- Historico congelado por ano
create table if not exists public.edicoes (
  ano           int primary key,
  eleitores     int not null,
  votaram       int not null,
  encerrada_em  timestamptz not null default now()
);

create table if not exists public.apuracoes (
  id                uuid primary key default gen_random_uuid(),
  ano               int not null references public.edicoes (ano) on delete cascade,
  categoria_ordem   int not null,
  categoria_titulo  text not null,
  principal         boolean not null default false,
  tipo              text not null check (tipo in ('nominal', 'branco', 'nulo')),
  numero            text,
  nome              text,
  apelido           text,
  foto_url          text,
  votos             int not null
);
create index if not exists apuracoes_ano on public.apuracoes (ano);
