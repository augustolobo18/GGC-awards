# GGC Awards

Site de votação anual da galera GGC: urna estilo brasileira (voto único e secreto), categorias com o grande prêmio **GGC Of The Year**, CRUDs de admin e apuração ao vivo com histórico por ano.

- Front: HTML + CSS + JavaScript puro (sem framework, sem build), em `public/`.
- Back: Supabase (Auth, Postgres com RLS e funções, Storage, Realtime), SQL em `supabase/`.
- Participantes = candidatos: uma conta só (`contas`) é votante e candidata. Quem tem número aparece na urna. Ninguém vota em si mesmo.

## Papéis

| Papel | Pode |
|-------|------|
| `votante` | Entrar, ver o início e votar na urna |
| `admin` | Tudo do votante + participantes, categorias, edição (ano, abrir/encerrar) e apuração |
| `dev` | Tudo do admin. Só existe via SQL: nenhum admin cria, rebaixa ou remove um `dev` |

## Setup do banco

O projeto Supabase é `cftzrevmsucsvkgnqpct`. Rode os arquivos de `supabase/` nesta ordem (SQL Editor, `supabase db push` ou via MCP com `apply_migration`):

1. `01_schema.sql` a `09_elegibilidade_ggc.sql`, na ordem dos números
2. `99_checks.sql` (verificações; roda com rollback)

Todos são idempotentes. O `04_seed.sql` cria a conta `dev` com o e-mail placeholder `SEU_EMAIL_AQUI`. Troque pelo seu e-mail real **só no banco** (nunca em arquivo versionado):

```sql
update public.contas set email = lower('seu@email.com') where email = lower('SEU_EMAIL_AQUI');
```

## Passos no dashboard do Supabase (manuais)

O SQL não configura o Auth. Faça uma vez:

1. **Authentication > Hooks > Before User Created**: ative, tipo *Postgres function*, função `public.hook_so_convidados`. Sem isso qualquer pessoa consegue criar conta (mesmo assim ela fica sem papel e o RLS nega tudo, mas ligue o hook). Se não puder ligar o hook, use o trigger alternativo comentado no fim de `02_functions.sql`.
2. **Authentication > Providers > Email**: desligue **Confirm email**. O cadastro devolve sessão na hora.
3. **Authentication > URL Configuration**:
   - **Site URL**: a URL da Vercel (ex.: `https://ggc-awards.vercel.app`); enquanto não houver deploy, `http://localhost:3000`.
   - **Redirect URLs**: adicione `http://localhost:3000/**` e `https://ggc-awards.vercel.app/**` (o `**` cobre o link de `nova-senha.html`).
4. Opcional: configure um SMTP próprio em **Authentication > SMTP Settings**. O SMTP padrão do Supabase tem limite baixo de e-mails e pode atrapalhar o "Esqueci a senha".

## Rodar local

Sem build. Sirva a pasta `public/`:

```bash
npx serve public
```

Abra `http://localhost:3000`. O `index.html` redireciona conforme a sessão: sem login vai para `login.html`, votante para `inicio.html`, admin/dev para `admin-menu.html`.

`public/js/config.js` tem a URL e a *publishable key* do projeto. Ela é pública por design (quem protege os dados é o RLS). **A service role key nunca entra no repositório.**

## Fluxo de uso

1. Admin cadastra cada pessoa em **Participantes** (e-mail, nome, apelido, número, foto, papel) e cria as **Categorias** (uma é a principal).
2. A pessoa abre o site, clica em "Primeiro acesso? Criar conta" e usa o e-mail cadastrado (e-mail fora da lista é recusado).
3. No card **Edição** do menu admin: define o ano e abre a votação. Categorias e números ficam travados.
   - Antes de abrir, escreva o recado do ano em **Boas-vindas**: o votante lê depois de "Começar a votar" e antes da urna (sem texto, a tela é pulada).
4. Cada votante vota uma vez na urna (tudo gravado de uma vez no FIM). A **Apuração** atualiza ao vivo.
5. Admin encerra: o resultado vira snapshot em `edicoes` + `apuracoes` e fica visível **só para admins** (cerimônia).
6. Admin **publica os resultados**: o ano fica visível para todos na tela de resultados e o bastão de admin passa para o vencedor do GGC Of The Year (o admin anterior volta a votante). No GGC Of The Year não podem ser votados o admin do ano e quem venceu nos 3 anos anteriores: o vencedor só volta a concorrer 4 anos depois (venceu em 2026, concorre de novo em 2030). Os vencedores ficam em `vencedores_ggc`, inclusive os anos anteriores ao site. Empate: o dev escolhe o vencedor no card Edição antes de publicar.
7. O **novo admin** clica em "Começar novo ano" e escolhe se limpa as categorias (montar do zero) ou mantém para editar. Também dá para limpar pelo botão "Limpar categorias".
8. Votantes veem os resultados pelo link no início; ano com votação em andamento, encerrada ou não publicada fica bloqueado para eles.

## Voto secreto: o que o sistema garante e o limite

- `votos` não tem eleitor nem timestamp e usa `id` aleatório; quem votou fica só em `comparecimento`.
- Não existe voto branco nem nulo: `votar()` só aceita número de candidato válido (existe, não é o próprio e, no GGC Of The Year, não é o admin do ano) e recusa o envio inteiro se algum for inválido.
- **Limite:** quem tem acesso de superusuário ao banco, ou um admin que acompanha a apuração ao vivo no instante em que alguém vota, pode inferir um voto por correlação. Para evitar, só consulte a apuração depois de encerrar.

## Publicar

Hospedado na **Vercel** (plano Hobby, gratuito, sem cartão). Site estático, sem build.

1. Em vercel.com, **Add New > Project** e importe este repositório do GitHub.
2. **Framework Preset**: Other. **Root Directory**: `./`.
3. **Build and Output Settings**: deixe os três toggles desligados. A Vercel publica `public/` sozinha, porque a pasta existe, e não há build nem install.
4. **Deploy**. Cada push na `main` publica de novo automaticamente.

Depois do primeiro deploy, ajuste **Site URL** e **Redirect URLs** no Supabase (passo 3 acima) com o domínio da Vercel.

## Estrutura

```text
public/    site estático (páginas + js/config.js, supabase.js, auth.js)
supabase/  SQL numerado + 99_checks.sql
```
