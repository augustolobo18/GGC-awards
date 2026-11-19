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

## Ajustes rápidos

- **Som:** mude a constante `SOM_LIGADO` para `false` para desligar os bipes.
- **Cores:** ficam nas variáveis CSS do `:root`, no topo do `<style>`.
- **Textos do cabeçalho:** o título "Hora de votar" e a instrução ficam direto no HTML.
