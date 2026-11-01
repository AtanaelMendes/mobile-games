# Mobile Games

Plataforma Android de jogos de movimento para uma ou duas pessoas. **Balões**, **Avatar** e **Desvio de obstáculos** usam uma câmera do celular e a tela do aparelho ou seu espelhamento manual na TV. Não exige conta, servidor ou internet durante a partida.

## Preparação

- Flutter 3.47.8 e Dart 3.13.7 (versões usadas no desenvolvimento).
- Android SDK 36, JDK 17 e um celular Android com câmera (Android 7.0 / API 24 ou superior).
- Na raiz do projeto: `flutter pub get`.
- O modelo leve MediaPipe está incluído em `android/app/src/main/assets/pose_landmarker_lite.task`; a compilação baixa dependências, mas o app instalado não baixa o modelo.

## Executar e gerar APK

Conecte o aparelho com depuração USB, confirme `flutter devices` e rode:

```sh
flutter run -d <id-do-aparelho>
flutter build apk --debug
```

O APK fica em `build/app/outputs/flutter-apk/app-debug.apk`. Para validar a lógica sem câmera, abra **Configurações**, ative **Modo simulado** e entre em **Balões**. Esse modo produz movimentos artificiais; não mede a câmera nem a inferência real.

## Posicionamento e partida

Fixe o celular na horizontal próximo à TV, com a câmera enquadrando as pessoas inteiras. Ao escolher um jogo, selecione **1 jogador** para usar a imagem e a tela inteiras, ou **2 jogadores** para dividir a imagem exibida: Jogador 1 à esquerda, Jogador 2 à direita. No modo de dois jogadores, cada pessoa deve permanecer em sua metade. Deixe somente uma pessoa em cada região. Não há troca automática de jogador ao atravessar a linha central.

No menu, entre em **Configurações** para ajustar o espelhamento. Na preparação ou calibração, toque em **Escolher câmera e zoom** para ver as câmeras que o Android expõe ao aplicativo, com ângulo horizontal estimado e faixa de zoom. Selecione uma lente e ajuste o zoom; **Voltar a 1×** restaura o enquadramento mais aberto dessa lente. A traseira principal em 1× vem selecionada. Ative o espelhamento da tela para TV nas configurações do próprio Android; o aplicativo não descobre TVs e não implementa transmissão. A compatibilidade e o atraso dependem do celular, da TV e do método de espelhamento. Chromecast e Miracast não são equivalentes.

Abra **Balões**, escolha a quantidade de jogadores, conceda a permissão de câmera e toque em **Calibrar**. Na calibração, erga e mova as mãos; a estimativa simples de alcance adapta a altura inicial dos balões. Quando os participantes estiverem **Pronto**, inicie a partida. A rodada dura 60 segundos e pausa após perda persistente de rastreamento. Cada balão vale um ponto. É possível desligar o som e ajustar a dificuldade nas configurações.

Em **Avatar**, cada pessoa controla um boneco pequeno ao deslocar o corpo para a esquerda ou direita. Em dupla, cada boneco permanece na própria metade; sozinho, usa a tela inteira. A câmera continua capturando os movimentos, mas a imagem não aparece: o jogo usa um fundo cinza como no modo simulado. O centro do corpo usa principalmente os quadris, com os ombros como alternativa. Os balões que atingem o boneco dão **+1 ponto**; bombas que o atingem tiram **3 pontos**, inclusive quando o placar fica negativo. A chuva acelera e fica mais frequente durante os 60 segundos. As bombas têm animação e som próprios; a opção **Som** também as silencia. Na calibração, mova o corpo lateralmente para conferir o controle antes de começar.

Em **Desvio de obstáculos**, inspirado no visual dos jogos LCD de blocos, mova o corpo lateralmente para conduzir um carrinho pixelado e desviar dos blocos que descem. A câmera captura o movimento sem aparecer atrás da pista. Cada obstáculo ultrapassado dá **+1 ponto**; uma colisão tira **2 pontos**. A partida dura **2 minutos**, aceita um ou dois jogadores e aumenta gradualmente a velocidade. No modo individual, a pista usa a tela inteira. A detecção de posição usa os quadris e, quando necessário, os ombros.

Ative **Depuração** para mostrar pontos usados para colisão, frequência de detecção, tempo de processamento e idade do último resultado por jogador. Os dados são estimativas e precisam ser medidos em aparelho real.

## Organização técnica

- `lib/pose`: interface `PoseSource`, entrada nativa ou simulada e transformações de coordenadas.
- `lib/game`: estado das partidas, colisões de cabeça e punhos no modo Balões, colisões do boneco com balões e bombas no modo Avatar, desvio de blocos, pontuação e renderização com Flame.
- `lib/ui`: menu, configurações, preparação, calibração, partida e resultado.
- `android/app/src/main/kotlin`: CameraX com prévia e análise preferencialmente em 16:9, `PreviewView` em `FIT_CENTER` e composição `COMPATIBLE` para manter os controles sobre o vídeo, uma captura, `ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST`, rotação e espelhamento. Em partida individual, o detector recebe a imagem inteira; em dupla, processa dois recortes verticais sequencialmente. A análise prefere 640×360 para reduzir o custo de inferência; o aparelho pode selecionar outra resolução compatível. Só coordenadas, confiança e métricas seguem pelo canal; os quadros ficam no Android.

A transformação é: imagem bruta → imagem orientada → espelhamento configurado → recortes esquerdo/direito → coordenadas locais normalizadas → imagem exibida → área visível do jogo. O recorte direito acrescenta o deslocamento horizontal de meia imagem. A câmera inteira usa ajuste proporcional com margens em vez de cortar o corpo. A fonte simulada implementa a mesma interface da fonte real.

O antigo botão **Corrida** foi substituído pelo jogo de desvio de obstáculos conforme a nova regra do projeto.

## Limitações conhecidas

- O detector aceita no máximo uma pose por metade. Se duas pessoas ocuparem a mesma região, não há garantia de qual será detectada.
- A calibração de alcance é simples, acumulada durante a sessão, e não mede distância física. A cabeça usa o nariz como centro aproximado; as mãos usam os punhos, sem rastreamento de dedos.
- A inferência sequencial de duas regiões pode ter baixa frequência em aparelhos modestos. Não há meta de desempenho garantida; use a sobreposição de depuração para medir.
- A detecção e o espelhamento ainda precisam ser confirmados em celular físico, incluindo alinhamento da prévia com as colisões nas duas câmeras e rotações de paisagem.
- A lente 0,6× pode existir no aplicativo de câmera do fabricante sem estar disponível a aplicativos de terceiros. No Redmi 2312DRA50G testado, o Android expôs ao jogo somente as câmeras ID 0 (traseira, zoom 1–10×) e ID 1 (frontal, zoom 1–10×). Portanto, o jogo não consegue ativar a lente 0,6× nesse aparelho pelas APIs públicas testadas.
- Configurações não são persistidas entre execuções. O som nativo funciona no Android; o modo simulado foi feito para validar a lógica e não reproduz som.

## Validação

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

No emulador Android API 37, foram verificados a abertura do menu, a partida em modo simulado, a solicitação de permissão e a prévia da câmera virtual com os controles sobrepostos. Isso não valida detecção de duas pessoas nem taxa de quadros em celular físico.

Checklist em aparelho físico e TV:

1. Conceder, negar e depois conceder permissão da câmera; confirmar mensagem e recuperação.
2. Selecionar câmera frontal e traseira, com espelhamento ligado e desligado. Comparar movimento da mão na imagem e no ponto de depuração.
3. Verificar a linha central, margens do vídeo e colisões nos quatro cantos de cada metade, em ambas as orientações horizontais.
4. Retirar uma pessoa da própria metade e confirmar que ela deixa de pontuar. Testar pausa após perda prolongada e retomada com placares e tempo preservados.
5. Testar os três jogos em 1 e 2 jogadores. No modo individual, confirmar rastreamento e objetos por toda a largura. No modo Avatar, pegar balões (+1) e atingir bombas (-3). Em Desvio de obstáculos, ultrapassar blocos (+1), colidir (-2) e confirmar o fim após 2 minutos. Conferir colisões únicas, placares independentes, aumento da velocidade e pausa por perda de rastreamento.
6. Colocar o app em segundo plano e voltar; conferir liberação e retomada da câmera.
7. Espelhar manualmente na TV, observar enquadramento, latência e legibilidade dos placares. Medir fps e tempo de inferência na depuração.

Fontes de implementação: [MediaPipe Pose Landmarker Android](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker/android), [modelo lite](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker/index), [CameraX ImageAnalysis](https://developer.android.com/media/camera/camerax/analyze) e [Flame](https://pub.dev/packages/flame).
