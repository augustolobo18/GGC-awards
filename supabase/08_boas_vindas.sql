-- GGC Awards — 08: mensagem de boas-vindas da votação (idempotente)
-- Título + texto mostrados ao votante entre "Começar a votar" e a urna.
-- Ficam na linha única de "eleicao" (todo logado lê); só admin/dev altera, via RPC.
-- Formatação simples no texto: **negrito**, *itálico*, quebras de linha.

alter table public.eleicao add column if not exists boas_vindas_titulo text;
alter table public.eleicao add column if not exists boas_vindas_texto text;

create or replace function public.salvar_boas_vindas(p_titulo text, p_texto text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.e_admin() then
    raise exception 'Apenas admin' using errcode = '42501';
  end if;
  if length(coalesce(p_titulo, '')) > 200 then
    raise exception 'Título muito longo (máx. 200 caracteres)';
  end if;
  if length(coalesce(p_texto, '')) > 8000 then
    raise exception 'Texto muito longo (máx. 8000 caracteres)';
  end if;
  update public.eleicao
     set boas_vindas_titulo = nullif(btrim(p_titulo), ''),
         boas_vindas_texto  = nullif(btrim(p_texto), ''),
         atualizado_em = now()
   where id = 1;
end;
$$;

revoke all on function public.salvar_boas_vindas(text, text) from public, anon;
grant execute on function public.salvar_boas_vindas(text, text) to authenticated;
