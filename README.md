# Isleto para iOS

App iOS do **Isleto**, um tracker de vida (produtividade, saúde e rotina). A versão de desktop
(Windows, Rust + Slint) fica em outro repositório. Este app usa o **mesmo esquema de banco**
do desktop, para a sincronização futura ser direta.

Tudo é gratuito: não há Mac. O código é editado no Windows, compilado no GitHub Actions
(`macos-latest`) e instalado no iPhone pelo **iloader**, com um Apple ID gratuito.

> O Sideloadly gratuito instala o app, mas **não concede o App Group** (só a opção paga
> "custom entitlements" faria isso). Sem App Group, o app e o widget não compartilham dados.
> Por isso a instalação usa o iloader.

## Estado atual: marco 1, teste de viabilidade

O app atual é só um teste. Ele deve provar três coisas:

1. O app compila sem Mac (na CI).
2. O app assina e instala com um Apple ID gratuito.
3. O app e o widget compartilham dados pelo App Group depois do sideload.

O que existe:

- **App**: um contador gravado no banco SQLite dentro do App Group, uma prévia do widget,
  botões para iniciar e encerrar uma Live Activity e um bloco de diagnóstico.
- **Widget** (pequeno): mostra o contador e tem um botão **+1** (App Intent).
- **Live Activity**: um timer na Dynamic Island e na tela bloqueada.

## Estrutura

| Caminho | Conteúdo |
| --- | --- |
| `project.yml` | Projeto do Xcode, no formato do XcodeGen. O `.xcodeproj` é gerado na CI. |
| `App/` | App SwiftUI e `Isleto.entitlements`. |
| `Widgets/` | Extensão única com o widget e a Live Activity, e `IsletoWidgets.entitlements`. |
| `Shared/` | Código compilado no app e na extensão (App Intent, dados da Live Activity, acesso ao banco). |
| `Packages/IsletoCore/` | Swift Package com a lógica (esquema, contador, sequência de hábitos, timer) e os testes. |
| `scripts/ci/` | Scripts usados pelo workflow. |
| `.github/workflows/ci.yml` | Workflow do GitHub Actions. |

### Decisões técnicas

- **Banco**: SQLite (GRDB) no container do App Group, arquivo `isleto.db`. As migrações são
  as mesmas do desktop, com o mesmo controle por `PRAGMA user_version`. O contador de teste
  fica na tabela `settings` do desktop (chave `probe_counter`), então o iOS não cria nenhuma
  tabela que o desktop não tenha. Se uma migração mudar, ela muda nos dois repositórios.
- **Sequência de hábitos**: conta dias seguidos. Se hoje ainda não foi marcado, a sequência de
  ontem continua valendo até o fim do dia. A regra é a mesma do desktop, com os mesmos testes.
- **Sem push (APNs)**: a conta gratuita não tem push. A Live Activity só se atualiza sozinha com
  timers do sistema (`Text(timerInterval:)` e `ProgressView(timerInterval:)`). Contadores só
  atualizam com o app aberto ou por um botão com App Intent.
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
   - `01-app-inicio.png`: a tela inicial. A seção **App Group** deve mostrar **OK** em verde.
   - `02-contador-somado.png`: o contador depois de três somas.
   - `03-previa-do-widget.png`: a prévia do widget.
   - `04-live-activity-iniciada.png`: a mensagem "Timer de 25 min iniciado.".
   - `05-dynamic-island.png`: o timer na Dynamic Island, fora do app.
   - `06-diagnostico-escuro.png`: o bloco de diagnóstico, no modo escuro.
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

1. Abra o **Isleto**. Na seção **App Group** deve aparecer **OK** em verde, com um grupo que
   começa com `group.app.isleto.ios` (o final com o Team ID é normal), e "isleto.db, esquema v4".
2. Toque em **+1** três vezes. O contador mostra **3**.
3. Na Tela de Início, toque e segure num espaço vazio, toque em **+** (ou **Editar >
   Adicionar Widget**), procure **Isleto** e adicione o **Contador de teste**. Ele deve
   mostrar **3**.
4. Toque em **+1** no widget. O widget mostra **4**.
5. Abra o app. O contador mostra **4**. *(Prova que o widget grava e o app lê.)*
6. Toque em **+1** no app (**5**) e volte à Tela de Início. O widget mostra **5**.
   *(Prova que o app grava e o widget lê.)*
7. No app, toque em **1 min**. Saia do app: o timer aparece na Dynamic Island.
   Toque e segure a ilha para ver a versão expandida.
8. Feche o app de vez (deslize para cima no seletor de apps) e bloqueie a tela.
   O timer continua contando na tela bloqueada e chega a 0:00.
9. Abra o app e toque em **Encerrar**. A Live Activity some.
10. Feche e abra o app de novo. O contador mantém o valor.

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
feat(widgets): adiciona widget do contador e Live Activity do timer
fix(core): corrige a sequência de hábitos na virada do ano
docs: explica como renovar o app a cada 7 dias
```

## Licença

[MIT](LICENSE).
