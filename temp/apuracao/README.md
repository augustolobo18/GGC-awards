# Urna da Galera

Tela de votação no estilo da urna eletrônica brasileira, para o grupo de amigos eleger os "prêmios" de cada categoria (membro mais palestrinha, melhor no volante etc.).

O arquivo `urna-eletronica.html` traz tudo junto: HTML, CSS e JavaScript puro, sem framework e sem build. Para ver funcionando, é só abrir no navegador.

## Como funciona a votação

1. Para cada categoria a tela mostra **SEU VOTO PARA**, o nome da categoria e dois quadradinhos para o número.
2. O eleitor digita os **2 números** do candidato no teclado da urna, ou toca no nome dele na lista à direita.
   - Se o número existir, aparecem a foto, o nome e o apelido do candidato.
   - Se não existir, aparece **NÚMERO ERRADO / VOTO NULO**.
3. Teclas:
   - **BRANCO**: registra voto em branco. Só funciona com o campo vazio, como na urna real.
   - **CORRIGE**: apaga o que foi digitado.
   - **CONFIRMA**: grava o voto e passa para a próxima categoria.
4. Depois da última categoria toca o som de fim e a tela mostra **FIM / VOTOU**. O botão **Próximo eleitor** reinicia a urna para a próxima pessoa.

Atalhos no teclado do computador (com a urna em foco): números digitam, `Enter` confirma, `Backspace`/`Esc` corrige e `B` vota em branco.

A lista à direita é rolável, tem busca por nome, apelido ou número e destaca o candidato que corresponde ao número digitado.

## Dados

Por enquanto a tela usa dados de exemplo, que ficam no topo do `<script>`:

- `CANDIDATOS_MOCK`: lista de `{ numero, nome, apelido, foto_url }`
- `CATEGORIAS_MOCK`: lista de `{ id, titulo, descricao }`

Se o candidato não tiver `foto_url`, aparecem as iniciais do nome num círculo colorido.

## Tabelas sugeridas no Supabase

| Tabela | Colunas |
|---|---|
| `candidatos` | `numero` (text, 2 dígitos, único), `nome`, `apelido`, `foto_url` (pode ser nulo) |
| `categorias` | `id`, `ordem`, `titulo`, `descricao` |
| `votos` | `id`, `eleitor_id`, `categoria_id`, `numero` (pode ser nulo), `tipo` (`nominal` / `branco` / `nulo`), `created_at` |

## Integração: o que trocar

Só duas funções no script precisam mudar (o código pronto está em comentário logo acima de cada uma):

- **`carregarDados()`**: trocar o retorno dos dados de exemplo por um `select` nas tabelas `candidatos` e `categorias`. A ordem das categorias vem da coluna `ordem`.
- **`enviarVotos(votos)`**: trocar o `console.log` por um `insert` na tabela `votos`. A função é chamada uma vez, no FIM, com todos os votos do eleitor. Cada voto vem no formato `{ categoria_id, numero, tipo }`.

**Ainda falta definir:**

- **Quem é o eleitor (`eleitor_id`):** a tela não sabe quem está votando. Precisa vir de um login ou de outro jeito de identificar a pessoa.
- **Voto único:** se cada pessoa só puder votar uma vez, isso precisa ser garantido no banco, por exemplo com uma chave única em (`eleitor_id`, `categoria_id`).

## Tela de login (`login.html`)

Card de vidro fosco sobre um fundo azul animado, com e-mail, senha (botão de olho para mostrar ou esconder), "Lembrar de mim" e "Esqueci a senha". Quando o login dá certo, aparece um botão que leva para `urna-eletronica.html` (o destino fica na constante `URL_URNA`).

- **Hoje (exemplo):** qualquer senha com 4 ou mais caracteres entra.
- **Supabase:** trocar o corpo de `autenticar(email, senha)` por `supabase.auth.signInWithPassword` (o código está em comentário no script). Para "Esqueci a senha", usar `supabase.auth.resetPasswordForEmail`.
- **Eleitor:** o id do usuário logado (`supabase.auth.getUser()`) é o `eleitor_id` que a urna precisa para gravar os votos.

## Papéis (roles)

Cada conta tem um papel: **votante** ou **admin**.

- **Votante:** só vê `login.html` e `urna-eletronica.html`.
- **Admin:** vê também todas as telas `admin-*.html`.

Sugestão no Supabase:

- Tabela `perfis` com `id` (o mesmo de `auth.users`) e `role` (`votante` | `admin`).
- Depois do login, ler a role e mandar o votante para a urna e o admin para o painel.
- **Proteger no banco com RLS, não só escondendo a tela:**
  - `candidatos` e `categorias`: todo mundo logado pode ler; só admin cria, edita e exclui.
  - `votos`: o votante só insere os próprios votos (`eleitor_id = auth.uid()`); só admin lê todos.
  - Storage `fotos`: leitura pública; só admin envia e apaga arquivos.

## Admin: candidatos (`admin-candidatos.html`)

CRUD completo da tabela `candidatos`, com o mesmo visual das telas da urna (cinza claro, cards brancos, fontes Inter e Space Grotesk).

- **Lista:** foto, nome, apelido e número. Busca por nome, apelido ou número; "Ordenar por" número ou nome. O topo mostra quantos estão na disputa e quantos números estão livres.
- **Novo / Editar:** janela com o número em dois quadradinhos estilo urna, nome, apelido e foto, mais uma prévia de como o candidato aparece na urna.
- **Validação:** número com 2 dígitos e sem dono ("O 22 já é de Felipe Andrade."); nome obrigatório.
- **Foto:** é arquivo, não link. No celular o botão abre a galeria ou a câmera. Só imagem, até 5 MB (constante `FOTO_MAX_MB`).
- **Excluir:** pede confirmação. Esc ou clique fora fecham as janelas.

**Integração:** trocar as funções do objeto `api` no script (o código pronto está em comentário em cada uma):

| Função | Supabase |
|---|---|
| `listar()` | `select` em `candidatos` |
| `criar(c)` | `insert` |
| `atualizar(numeroOriginal, c)` | `update ... eq('numero', numeroOriginal)` (permite trocar o número) |
| `remover(numero)` | `delete ... eq('numero', numero)` |
| `enviarFoto(arquivo, numero)` | `upload` no bucket `fotos` e devolve a URL pública, que vai para `foto_url` |

**Atenção:** se um candidato que já recebeu votos mudar de número ou for excluído, os votos antigos ficam apontando para um número que não existe mais. Vale decidir se isso deve ser bloqueado depois que a votação começar.

## Admin: contas (`admin-contas.html`)

Lista de **e-mails autorizados** e o papel de cada um. Só quem está nessa lista consegue criar conta.

- **Status:** **Ativo** quando a pessoa já criou a conta (`user_id` preenchido); **Aguardando cadastro** quando ainda não criou.
- **Adicionar e-mails:** cola vários de uma vez (por linha ou vírgula) e escolhe se entram como Votante ou Admin. Antes de confirmar, cada e-mail aparece marcado como novo, já na lista, repetido ou inválido.
- **Mudar papel:** switch Votante / Admin em cada linha, com **Desfazer** por 5 segundos.
- **Remover:** pede confirmação. Para conta ativa: perde o acesso, os votos continuam. Para convite: sai da lista.
- **Proteções:** o admin logado não muda o próprio papel nem se remove; o último admin não pode ser rebaixado nem removido.
- Busca por nome ou e-mail e filtros Todas / Admins / Votantes / Aguardando.

**Tabela `contas`:** `email` (text, único, minúsculo), `nome` (pode ser nulo), `role` (`votante` | `admin`), `user_id` (uuid, nulo até a pessoa se cadastrar), `criado_em`. Essa tabela substitui a `perfis` sugerida antes: a role do usuário logado vem daqui.

**Bloquear cadastro de quem não está na lista:** o SQL pronto está no comentário do topo do script:

- gatilho **antes** de inserir em `auth.users`: recusa o e-mail se ele não estiver em `contas`;
- gatilho **depois** de inserir: grava o `user_id` (e o nome, se veio no cadastro) na linha da pessoa.

**Integração:** trocar as funções do objeto `api` (código pronto em comentário):

| Função | Supabase |
|---|---|
| `meuEmail()` | `supabase.auth.getUser()` |
| `listar()` | `select` em `contas` |
| `adicionar(emails, role)` | `insert` de várias linhas |
| `mudarPapel(email, role)` | `update ... eq('email', email)` |
| `remover(email, user_id)` | `delete` na tabela e, se tinha conta, apagar o login numa **Edge Function** com a service role (`auth.admin.deleteUser`) — isso não pode rodar no navegador |

**RLS:** só admin lê e altera `contas`; cada usuário pode ler a própria linha (para descobrir a role depois do login).

**Falta na tela de login:** um "Primeiro acesso? Criar conta" (nome, e-mail e senha via `supabase.auth.signUp`, mandando o nome em `options.data.nome`), com a mensagem "Esse e-mail não está na lista" quando o gatilho recusar.

## Admin: apuração (`admin-apuracao.html`)

Resultado ao vivo da votação.

- **Topo:** "Ao vivo · atualizado às …" com botão **Atualizar**. Atualiza sozinha a cada 15 s (`ATUALIZAR_A_CADA_S`), só com a aba visível. Abaixo, o comparecimento: quantos eleitores já votaram, com barra e "faltam N pessoas".
- **GGC Of The Year (destaque):** bloco marinho com título amarelo. Mostra quem lidera (foto grande, número, nome, apelido e % dos votos válidos), o ranking com até 6 posições e os válidos, brancos e nulos.
- **Categorias:** um card por categoria com o líder, o top 3 com barras e os brancos e nulos. Empate fica amarelo e mostra os empatados juntos.
- **Busca e filtros (barra fixa ao rolar):** busca pelo nome da categoria **ou** de um candidato; filtros Todas / Empates / Com líder / Sem votos, com contagem; "Mostrando X de Y"; botão para limpar quando nada aparece.
- Porcentagens sempre sobre os **votos válidos**, como na apuração oficial.

**Mudança no banco:** a tabela `categorias` ganha a coluna `principal` (boolean, padrão `false`). O GGC Of The Year é a categoria com `principal = true`, e também precisa entrar na urna (sugestão: como a última, igual ao voto para presidente).

**Integração:** trocar `api.carregar()`; a consulta completa está em comentário no script. Usa:

- a view `apuracao` (`categoria_id, numero, tipo, count(*) as votos`, agrupada);
- a função `qtd_que_votaram()` (conta `eleitor_id` distintos em `votos`);
- `contas` com `user_id` preenchido como total de eleitores.

O SQL das duas está no topo do script. Libere a view e a função **só para admin**. Opcional: trocar o intervalo por tempo real com `supabase.channel(...).on('postgres_changes', …)`.

## Ajustes rápidos

- **Som:** mude a constante `SOM_LIGADO` para `false` para desligar os bipes.
- **Cores:** ficam nas variáveis CSS do `:root`, no topo do `<style>`.
- **Textos do cabeçalho:** o título "Hora de votar" e a instrução ficam direto no HTML.
