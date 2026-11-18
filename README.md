# Isleto para iOS

App iOS do **Isleto**, um tracker de vida (produtividade, saúde e rotina). A versão de desktop
(Windows, Rust + Slint) fica em outro repositório. Este app usa o **mesmo esquema de banco**
do desktop, para a sincronização futura ser direta.

Tudo é gratuito: não há Mac. O código é editado no Windows, compilado no GitHub Actions
(`macos-latest`) e instalado no iPhone pelo **iloader**, com um Apple ID gratuito.

> O Sideloadly gratuito instala o app, mas **não concede o App Group** (só a opção paga
> "custom entitlements" faria isso). Sem App Group, o app e o widget não compartilham dados.
> Por isso a instalação usa o iloader.

## Estado atual: aba Hábitos

- **Marco 1 (concluído em 17/11/2026)**: teste de viabilidade. O app compila sem Mac, instala
  com Apple ID gratuito (pelo iloader), e o app e o widget compartilham dados pelo App Group.
- **Marco 2**: aba **Hoje** com água (meta de 2000 ml, copo de 250 ml) e foco de 25 min, com
  Live Activity e notificação local.
- **Aba Hábitos (em teste)**:
  - Cartões com a grade das últimas semanas: cada coluna é uma semana (segunda em cima), e
    cada quadrado preenchido é um dia concluído. O botão do cartão registra hoje.
  - Tipos: **Criar** (marca o dia feito) e **Largar** (marca o dia da recaída; a sequência
    conta os dias desde a última).
  - Repetição: todos os dias, dias da semana, ou X vezes por semana (sequência em semanas).
  - Registro: Sim/Não, Contagem (cada toque soma 1 até a meta) ou Medida (valor com unidade).
  - Lembretes (até 3 horários, notificação local), categorias criadas por você, filtro,
    arquivar, apagar e reordenar.
  - Detalhe: mapa dos últimos meses, sequência, repetição e calendário do mês; tocar num dia
    marca, ou abre o valor de contagem e medida.
  - Widget médio "Hoje": a semana de até 4 hábitos, com toque para registrar hoje.
  - Ícone do app: o mascote do Isleto (`App/Assets.xcassets`, copiado de
    `assets/icon` do desktop). O mascote sem fundo fica guardado para uso futuro.

Treinos, pausas do pomodoro, timers avulsos e a sincronização com o desktop ficam para depois.

## Estrutura

| Caminho | Conteúdo |
| --- | --- |
| `project.yml` | Projeto do Xcode, no formato do XcodeGen. O `.xcodeproj` é gerado na CI. |
| `App/` | App SwiftUI e `Isleto.entitlements`. |
| `Widgets/` | Extensão única com o widget e a Live Activity, e `IsletoWidgets.entitlements`. |
| `Shared/` | Código compilado no app e na extensão (App Intent, dados da Live Activity, acesso ao banco). |
| `Packages/IsletoCore/` | Swift Package com a lógica (esquema, água, foco, hábitos, sequências, lembretes, App Group) e os testes. |
| `scripts/ci/` | Scripts usados pelo workflow. |
| `.github/workflows/ci.yml` | Workflow do GitHub Actions. |

### Decisões técnicas

- **Banco**: SQLite (GRDB) no container do App Group, arquivo `isleto.db`. As migrações são
  as mesmas do desktop, com o mesmo controle por `PRAGMA user_version`. Datas são gravadas como
  texto em hora local, no mesmo formato do desktop. A sessão de foco em andamento fica na tabela
  `settings` do desktop (chave `focus_active`). Se uma migração mudar, ela muda nos dois
  repositórios. A migração v5 (campos dos hábitos e categorias) só acrescenta colunas e tabelas,
  e existe igual no desktop; lá o painel mostra só os 4 primeiros hábitos visíveis (não
  arquivados, de Criar, do tipo Sim/Não), na ordem do iOS.
- **Sequência de hábitos**: conta dias seguidos. Se hoje ainda não foi marcado, a sequência de
  ontem continua valendo até o fim do dia. A regra é a mesma do desktop, com os mesmos testes.
- **Sem push (APNs)**: a conta gratuita não tem push. A Live Activity só se atualiza sozinha com
  timers do sistema (`Text(timerInterval:)` e `ProgressView(timerInterval:)`). Os números do
  widget só mudam com o app aberto, por um botão com App Intent, no fim de um foco ou à
  meia-noite. Notificações **locais** funcionam na conta gratuita.
- **Assinatura de mentira na CI**: sem assinatura real (`CODE_SIGNING_ALLOWED=NO`), o Xcode
  descarta os entitlements, como o App Group. Por isso a CI grava os entitlements em cada binário
  com `ldid -S` antes de montar o `.ipa`. A ferramenta de instalação lê esses entitlements para
  saber que deve pedir o App Group quando assina com o seu Apple ID.
- **Identificadores**: app `app.isleto.ios`, extensão `app.isleto.ios.widgets`, App Group
  `group.app.isleto.ios`. O App Group aparece em três lugares que precisam ser iguais:
  `project.yml` (`APP_GROUP_ID`), `App/Isleto.entitlements` e `Widgets/IsletoWidgets.entitlements`.
  A CI falha se eles divergirem.
- **Nomes trocados na assinatura**: com Apple ID gratuito, o iloader acrescenta o Team ID da
  conta aos nomes, por exemplo `app.isleto.ios.ABCDE12345` e `group.app.isleto.ios.ABCDE12345`.
  O app descobre o nome real do App Group no perfil de assinatura embutido
  (`embedded.mobileprovision`), e não por palpite. Também aceita a chave `ALTAppGroups`,
  que o AltStore e o SideStore gravam.

## O que a CI faz

A cada push na `main` (ou manualmente, em **Actions > CI > Run workflow**):

1. Instala XcodeGen e ldid.
2. Roda os testes do `IsletoCore` no macOS (`swift test`).
3. Gera o `Isleto.xcodeproj` (`xcodegen generate`).
4. Roda os mesmos testes no simulador do iOS.
5. Faz o `xcodebuild archive` sem assinatura, grava os entitlements com `ldid` e monta o
   `Isleto.ipa` (`Payload/Isleto.app`).
6. Abre o app no simulador e tira capturas de tela.
7. Publica três artefatos: **Isleto-ipa**, **capturas-de-tela** e **logs**.

Nenhum segredo é usado. Nunca coloque chave, token, senha, e-mail ou dado pessoal em arquivo,
commit ou workflow: o repositório é público.

## Passo a passo

### 1. Publicar o repositório (só na primeira vez)

1. No GitHub, crie um repositório **público** vazio chamado `isleto-ios`, sem README, sem
   licença e sem `.gitignore` (eles já existem aqui).
2. No terminal, dentro desta pasta, troque `SEU_USUARIO` pelo seu usuário do GitHub:

   ```bash
   git remote add origin https://github.com/SEU_USUARIO/isleto-ios.git
   ```

   ```bash
   git push -u origin main
   ```

3. Abra a aba **Actions** do repositório. O workflow **CI** começa sozinho. Ele leva de
   10 a 25 minutos.

### 2. Ver as capturas de tela

1. Em **Actions**, abra a execução mais recente do **CI**.
2. No fim da página, em **Artifacts**, baixe **capturas-de-tela** (vem em `.zip`).
3. Extraia. As imagens são:
   - `01-hoje-vazio.png` e `02-hoje-com-dados.png`: a aba Hoje.
   - `03-habitos.png`: a aba Hábitos com hábitos de exemplo e as grades.
   - `04-habito-detalhe.png`: o detalhe de um hábito, com mapa e calendário.
   - `05-novo-habito.png`: o formulário de novo hábito.
   - `06-foco-ativo.png` e `07-dynamic-island.png`: o foco no app e na Dynamic Island.
   - `08-diagnostico-e-widget.png`: o diagnóstico (App Group **OK**) e a prévia do widget.
   - `09-habitos-escuro.png` e `10-habito-detalhe-escuro.png`: o modo escuro.
   - `modo-de-build.txt`: como o app foi assinado para o simulador. Se disser "sem assinatura",
     um App Group com falha **nas capturas** não indica falha no iPhone.

### 3. Baixar o .ipa

1. Na mesma execução, em **Artifacts**, baixe **Isleto-ipa**.
2. Extraia o `.zip`. Dentro está o `Isleto.ipa`. Não renomeie nem extraia o `.ipa`.

### 4. Preparar o Windows (só na primeira vez)

1. Instale o **iTunes** baixado do site da Apple (`apple.com/itunes`), não o da Microsoft Store.
   Ele traz o driver USB que o Windows usa para falar com o iPhone.
2. Instale o **iloader** pelo instalador oficial indicado na documentação do SideStore
   (`docs.sidestore.io`): o arquivo `iloader-windows-x64.msi` da página de releases do iloader
   no GitHub.
3. Ligue o iPhone no PC pelo cabo. No iPhone, toque em **Confiar** e digite o código do aparelho.

### 5. Instalar com o iloader

1. Abra o iloader. Em **Apple ID**, entre com o seu Apple ID **secundário**. Se pedir, digite o
   código de verificação.
2. Em **iDevice**, clique no seu iPhone para selecioná-lo.
3. Em **Installers**, clique em **Import IPA** e escolha o `Isleto.ipa`.
4. Espere terminar. Se o app já estiver instalado, aceite a substituição: os dados ficam.

Se o login falhar com `finishMachineProvisioning` e `401 Unauthorized`, o problema não é a senha:
é o servidor "anisette" do iloader. Em **Settings**, escolha outro **Anisette Server** (o
"iloader" funcionou), clique em **Reset Anisette State** e tente de novo.

Se aparecer "Verification codes can't be sent to this phone number at this time", a Apple
bloqueou o SMS por excesso de tentativas. Pare de tentar e espere algumas horas.

### 6. Liberar o app no iPhone (só na primeira vez)

1. **Modo de Desenvolvedor** (iOS 16 ou mais novo): **Ajustes > Privacidade e Segurança >
   Modo de Desenvolvedor**, ative e reinicie. Depois do reinício, confirme em **Ativar**.
2. **Confiar no desenvolvedor**: **Ajustes > Geral > VPN e Gerenciamento de Dispositivos**,
   toque no seu Apple ID e em **Confiar**.

### 7. O que verificar no iPhone

Faça na ordem e anote o primeiro passo que falhar:

1. O ícone do app na Tela de Início é o mascote. Abra o **Isleto**. Na aba **Hoje**, toque no
   estetoscópio (**Diagnóstico**) e confira **App Group: OK** e "esquema v5". Feche com **OK**.
2. **Água e foco** (aba Hoje): **+250 ml** soma e **Desfazer** tira. **Iniciar foco** mostra o
   tempo na Dynamic Island; **Cancelar foco** tira.
3. **Hábito Sim/Não** (aba Hábitos, **+**): crie "Ler", escolha ícone e cor, **Salvar**. No
   cartão, toque no quadrado da direita: o quadrado de hoje na grade fica preenchido. Toque de
   novo: desmarca.
4. **Contagem**: crie "Copos", **Registro > Contagem**, meta 3. Toque no anel três vezes: ele
   enche e vira um check.
5. **Largar**: crie "Refrigerante", **Tipo > Largar**. A grade fica preenchida desde hoje (dia
   limpo). O botão marca a recaída de hoje: o quadrado esvazia e a sequência vai a 0.
6. **Dias da semana**: edite "Ler" (toque no cartão, lápis), **Repetição > Dias**, marque só
   alguns dias. O chip de repetição muda.
7. **Detalhe**: toque num cartão. No calendário, toque num dia passado: ele é marcado e a
   grade acompanha. Em "Copos", tocar num dia abre o valor.
8. **Categorias**: no formulário, crie "Saúde" e marque. Na lista aparece o filtro
   **Todos / Saúde**.
9. **Lembrete**: adicione um lembrete para daqui a 2 minutos e permita as notificações. Ela chega
   na hora.
10. **Arquivar e reordenar**: na engrenagem do detalhe, **Arquivar** tira o hábito da lista; no
    menu **…** da lista, **Arquivados** traz de volta e **Reordenar** muda a ordem.
11. **Widget**: remova o widget antigo e adicione de novo o **Hoje** (médio). Ele mostra a semana
    de até 4 hábitos; tocar numa linha registra hoje, e o app mostra a mudança.

### 8. Renovar a cada 7 dias

Com Apple ID gratuito, o app para de abrir 7 dias depois da instalação. Para renovar, repita o
passo 5 com o mesmo `.ipa` ou um mais novo. Instalar por cima mantém os dados.
A linha "Perfil expira" do Diagnóstico mostra a data.

## Como me reportar um erro

Abra uma issue neste repositório (ou me mande uma mensagem) com:

```text
Passo que falhou: (número do passo 7, ou "CI", ou "instalação")
O que aconteceu: (o que você viu, com o texto exato da mensagem de erro)
iPhone e iOS: (ex.: iPhone 15 Pro, iOS 18.1)
Ferramenta de instalação e versão: (ex.: iloader 2.4.1)
Execução da CI: (link da execução em Actions)
Diagnóstico do app: (no app, seção Diagnóstico > Copiar diagnóstico, e cole aqui)
```

Junte uma captura de tela, se ajudar. Se a CI falhou, baixe o artefato **logs** e anexe o
arquivo do passo que falhou (`archive.log`, `test-simulator.log` ou `sim-build.log`).

**Cuidado: a issue é pública.** Não cole seu Apple ID, e-mail, senha, código de verificação,
número de série ou UDID do iPhone. O diagnóstico do app não contém nenhum desses dados.

## Limites da conta gratuita

- O app expira em **7 dias**.
- No máximo **3 apps** instalados por sideload ao mesmo tempo.
- Cada target com bundle ID (o app e cada extensão) gasta um **App ID**. São no máximo
  **10 App IDs novos por semana**. O Isleto usa 2 (app e widgets). Não crie e apague targets à toa.
- Sem push (APNs), sem iCloud e sem CloudKit.

O que foi testado com Apple ID gratuito (novembro de 2026):

- **Sideloadly**: instala, mas não concede o App Group sem a opção paga.
- **AltServer para Windows**: falhou com "anisette data is invalid"; o iCloud de 2020 que ele
  exige não consegue mais entrar no Apple ID.
- **iloader**: instala e concede o App Group ao app e ao widget, com o nome renomeado.
- **SideStore**: instalado pelo iloader; renova pelo próprio iPhone com o LocalDevVPN ligado.
  A instalação do Isleto por ele ainda não foi testada.

## Regra de commits

Commits seguem o [Conventional Commits](https://www.conventionalcommits.org/pt-br/), em português:

- O **tipo** e o **escopo** ficam em inglês. A **descrição** fica em português.
- Formato: `tipo(escopo): descrição no imperativo, sem ponto final`.
- Tipos: `feat`, `fix`, `docs`, `test`, `refactor`, `perf`, `build`, `ci`, `chore`.
- Escopos usados: `core` (IsletoCore), `app`, `widgets`, `ci`.
- **Um commit por mudança lógica.**

Exemplos:

```text
feat(widgets): mostra a semana de cada hábito no widget
fix(core): corrige a sequência de hábitos na virada do ano
docs: explica como renovar o app a cada 7 dias
```

## Licença

[MIT](LICENSE).
