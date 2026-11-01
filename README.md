# Mobile Games

Primeira versão Android de uma plataforma local de jogos de movimento para duas pessoas. O jogo **Balões** usa uma câmera do celular, duas regiões fixas de pose e a tela do aparelho ou seu espelhamento manual na TV. Não exige conta, servidor ou internet durante a partida.

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

Fixe o celular na horizontal próximo à TV, com a câmera enquadrando as duas pessoas inteiras. O Jogador 1 ocupa a metade esquerda da **imagem exibida** e o Jogador 2 a metade direita. Cada pessoa deve manter corpo e mãos dentro de sua metade. Deixe somente uma pessoa em cada região. Não há troca automática de jogador ao atravessar a linha central.

No menu, entre em **Configurações** para ajustar o espelhamento. Na preparação ou calibração, toque em **Escolher câmera e zoom** para ver as câmeras que o Android expõe ao aplicativo, com ângulo horizontal estimado e faixa de zoom. Selecione uma lente e ajuste o zoom; **Voltar a 1×** restaura o enquadramento mais aberto dessa lente. A traseira principal em 1× vem selecionada. Ative o espelhamento da tela para TV nas configurações do próprio Android; o aplicativo não descobre TVs e não implementa transmissão. A compatibilidade e o atraso dependem do celular, da TV e do método de espelhamento. Chromecast e Miracast não são equivalentes.

Abra **Balões**, conceda a permissão de câmera, alinhe os dois jogadores com a linha central e toque em **Calibrar**. Na calibração, erga e mova as mãos; a estimativa simples de alcance adapta a altura inicial dos balões. Quando ambos estiverem **Pronto**, inicie a partida. A rodada dura 60 segundos, mostra placares separados e pausa após perda persistente de rastreamento. Reposicione os dois jogadores para continuar. Cada balão vale um ponto para a pessoa de sua metade. É possível desligar o som e ajustar a dificuldade nas configurações.

Ative **Depuração** para mostrar pontos usados para colisão, frequência de detecção, tempo de processamento e idade do último resultado por jogador. Os dados são estimativas e precisam ser medidos em aparelho real. **Corrida** aparece como “Em breve”.

## Organização técnica

- `lib/pose`: interface `PoseSource`, entrada nativa ou simulada e transformações de coordenadas.
- `lib/game`: estado da partida, colisões de cabeça e punhos, pontuação e renderização dos balões com Flame.
- `lib/ui`: menu, configurações, preparação, calibração, partida e resultado.
- `android/app/src/main/kotlin`: CameraX com prévia e análise preferencialmente em 16:9, `PreviewView` em `FIT_CENTER` e composição `COMPATIBLE` para manter os controles sobre o vídeo, uma captura, `ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST`, rotação e espelhamento antes de dois recortes verticais. A análise prefere 640×360 para reduzir o custo de inferência; o aparelho pode selecionar outra resolução compatível. Um detector MediaPipe leve processa cada recorte de forma sequencial, com uma pose máxima por recorte. Só coordenadas, confiança e métricas seguem pelo canal; os quadros ficam no Android.

A transformação é: imagem bruta → imagem orientada → espelhamento configurado → recortes esquerdo/direito → coordenadas locais normalizadas → imagem exibida → área visível do jogo. O recorte direito acrescenta o deslocamento horizontal de meia imagem. A câmera inteira usa ajuste proporcional com margens em vez de cortar o corpo. A fonte simulada implementa a mesma interface da fonte real.

O ponto de extensão para **Corrida** é a fonte comum de poses e os identificadores fixos `player1`/`player2`. A implementação futura deve manter pistas independentes, cenário da direita para a esquerda e calibrar posição em pé. O salto deve combinar deslocamento de quadris e pés com estado de aterrissagem e uma trava para impedir vários saltos no mesmo movimento.

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
5. Testar movimentos rápidos de punho, colisão única por balão, placares independentes, som ligado/desligado e resultado após 60 segundos.
6. Colocar o app em segundo plano e voltar; conferir liberação e retomada da câmera.
7. Espelhar manualmente na TV, observar enquadramento, latência e legibilidade dos placares. Medir fps e tempo de inferência na depuração.

Fontes de implementação: [MediaPipe Pose Landmarker Android](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker/android), [modelo lite](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker/index), [CameraX ImageAnalysis](https://developer.android.com/media/camera/camerax/analyze) e [Flame](https://pub.dev/packages/flame).
