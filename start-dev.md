Inicie o desenvolvimento deste projeto Flutter no repositório:

https://github.com/AtanaelMendes/mobile-games.git

Atue como desenvolvedor Flutter sênior e implemente a primeira versão funcional. Analise os arquivos existentes e as instruções AGENTS.md antes de alterar o projeto. Se o repositório estiver vazio, crie a estrutura Flutter com suporte inicial a Android.

Não fique apenas no planejamento: implemente, valide e documente o que funcionar e eventuais limitações.

OBJETIVO

Criar uma plataforma de jogos de movimento para duas pessoas, usando a câmera de um único celular.

O celular ficará fixo na horizontal, próximo à TV, com a câmera apontada para os jogadores. A tela será espelhada na TV pelo recurso de espelhamento do próprio Android.

Todo o processamento deve ocorrer localmente. O funcionamento principal não deve exigir internet, login, servidor ou API paga.

Nome provisório do aplicativo: Mobile Games.
Nome do projeto Dart: mobile_games.

DIVISÃO DOS JOGADORES — REGRA PRINCIPAL

Divida a área de captura em duas regiões verticais fixas:

- Metade esquerda da imagem exibida: Player 1.
- Metade direita da imagem exibida: Player 2.

A divisão deve corresponder à imagem final apresentada ao usuário, depois de aplicar rotação, espelhamento e ajuste de proporção.

Cada pessoa deve jogar dentro da sua metade. Não implemente troca automática de identidade quando alguém atravessar o centro.

Implemente duas regiões de interesse independentes, recortando cada metade para realizar a detecção de pose de cada jogador separadamente. Cada região deve aceitar no máximo uma pessoa.

Se a pessoa sair da sua região, suspenda suas colisões e indique que ela precisa retornar. Não transfira automaticamente seus pontos ou controles para o outro jogador.

Atribua identificadores fixos player1 e player2 conforme a região, sem depender da ordem dos resultados retornados pelo detector.

Use uma única captura da câmera e distribua seus quadros para os dois recortes. Não tente abrir a mesma câmera duas vezes.

Se houver mais de uma pessoa na mesma metade, não prometa identificar corretamente qual delas é o jogador. Documente essa limitação e instrua que apenas uma pessoa ocupe cada região.

ARQUITETURA

Utilize:

- Flutter e Dart para interface, navegação, configurações e estado.
- Flame para os jogos 2D, animações, atualização por tempo e colisões.
- MediaPipe Pose Landmarker na camada Android em Kotlin para o rastreamento corporal.

Antes de adicionar dependências, verifique a documentação oficial e a compatibilidade com o Flutter, Dart, Gradle e Android SDK disponíveis. Use versões compatíveis e fixe as dependências; não deixe latest.release na configuração final.

Integre Android e Flutter por canais de plataforma ou outro mecanismo adequado. Processe câmera e inferência fora da thread principal.

Mantenha os quadros e recortes na camada nativa sempre que possível. Envie ao Dart coordenadas, confiança, identificação da região e timestamps. Para exibir a câmera, utilize uma textura ou integração adequada, evitando enviar imagens completas continuamente pelos canais.

Organize o código em módulos claros, sem criar abstrações desnecessárias:

- Captura e gerenciamento da câmera.
- Detecção de pose.
- Transformação de coordenadas.
- Estado e calibração dos jogadores.
- Menu e configurações.
- Jogo dos balões.
- Futuro jogo de corrida.

Crie uma interface para a fonte de poses, permitindo alternar entre câmera real e entrada simulada para desenvolvimento.

COORDENADAS E EXIBIÇÃO

Mantenha um sistema explícito de transformação entre:

1. Imagem original da câmera.
2. Imagem orientada corretamente.
3. Região recortada de cada jogador.
4. Coordenadas normalizadas locais da região.
5. Coordenadas finais do jogo.

Ao converter o resultado do recorte direito para a tela completa, considere o deslocamento horizontal dessa região.

Aplique o mesmo espelhamento ao vídeo, aos pontos corporais e às colisões. Não faça os ajustes de espelhamento em lugares diferentes sem uma transformação centralizada.

Evite cortar partes do corpo silenciosamente para preencher a tela. Prefira preservar o enquadramento com margens quando necessário.

Na primeira versão, mostre a imagem completa da câmera ao fundo, com os elementos do jogo sobrepostos. Não implemente remoção do fundo nesta etapa.

TELAS INICIAIS

Implemente:

1. Menu principal com “Balões”, “Corrida” e “Configurações”.
2. Preparação dos jogadores e enquadramento.
3. Calibração.
4. Partida.
5. Resultado com pontuação individual e opção de jogar novamente.

O botão Corrida pode aparecer como “Em breve”, sem iniciar uma tela incompleta.

Na preparação, mostre:

- Linha central dividindo os jogadores.
- Identificação e cor de cada jogador.
- Orientação para manter corpo e mãos dentro da própria região.
- Estado individual: procurando, detectado, pronto ou fora da área.
- Pontos corporais em uma opção de depuração.

Permita selecionar câmera frontal ou traseira, conforme disponibilidade, e configurar o espelhamento. Trate permissão negada, câmera indisponível e retorno do aplicativo após ficar em segundo plano.

PRIMEIRO JOGO — BALÕES

Implemente primeiro o jogo dos balões:

- Partida de 60 segundos por padrão.
- Balões nascendo no topo e caindo.
- Cada metade possui seus próprios balões.
- Player 1 interage somente com balões da esquerda.
- Player 2 interage somente com balões da direita.
- A cabeça e as duas mãos podem estourar balões.
- Cada balão vale um ponto.
- Cada balão só pode pontuar uma vez.
- Exibir placares individuais e tempo restante.
- Mostrar animação e efeito sonoro ao estourar.
- Permitir desligar o som.
- Exibir vencedor ou empate ao terminar.

Modele cabeça e mãos com áreas circulares de colisão. Estime o centro da cabeça pelos pontos faciais disponíveis e as mãos pelos punhos e demais pontos disponíveis na pose. Não adicione rastreamento detalhado de dedos nesta etapa.

Ajuste o tamanho dessas áreas conforme o tamanho aparente do jogador, com limites configuráveis. Ignore pontos com confiança insuficiente.

Suavize as coordenadas sem introduzir atraso excessivo e descarte resultados antigos. Considere colisão ao longo do trajeto entre posições recentes para reduzir falhas quando a mão se mover rapidamente, sem conectar trajetos após perda de rastreamento.

Faça os balões surgirem em áreas alcançáveis. Na calibração, obtenha uma estimativa simples da altura e alcance dos jogadores para adaptar a distribuição.

Se um jogador perder o rastreamento por um período curto, desative suas colisões. Se a perda persistir, pause a partida para ambos e solicite reposicionamento, preservando o placar e o tempo.

Use velocidade inicial baixa e dificuldade progressiva configurável.

DESEMPENHO

O celular processará câmera, duas regiões de pose, jogo e espelhamento simultaneamente.

- Use fila limitada e priorize quadros recentes.
- Não acumule quadros aguardando inferência.
- Não exija que a detecção rode na mesma frequência da renderização.
- Avalie resolução reduzida de inferência e modelo leve.
- Se necessário, alterne o processamento das regiões, mantendo timestamps individuais.
- Não presuma que duas instâncias simultâneas do detector serão mais rápidas: meça antes de escolher.
- Libere câmera, detectores, texturas e recursos ao encerrar.

Adicione uma sobreposição de depuração opcional com frequência de detecção por jogador, tempo de processamento e idade do último resultado. Não prometa desempenho antes de medir em aparelho físico.

ESPELHAMENTO NA TV

Nesta primeira versão, o espelhamento será iniciado manualmente nas configurações do celular.

Não implemente um protocolo próprio de Miracast, descoberta de TVs ou streaming de vídeo.

O aplicativo deve funcionar também diretamente na tela do celular.

Documente que a compatibilidade e o atraso do espelhamento dependem do celular e da TV. Não afirme que Chromecast e Miracast são equivalentes.

FUTURO JOGO — CORRIDA COM OBSTÁCULOS

Prepare a arquitetura para adicionar posteriormente:

- Cenário deslocando da direita para a esquerda.
- Uma pista ou área visual independente para cada jogador.
- Salto físico controlando o salto de um personagem.
- Calibração da posição em pé.
- Detecção combinando deslocamento dos quadris, pés e estado de aterrissagem.
- Proteção contra contar vários saltos em um único movimento.

Nesta etapa, implemente somente o ponto de extensão e documente as regras. Priorize concluir o jogo dos balões.

VALIDAÇÃO

Execute os comandos disponíveis e adequados ao ambiente:

- flutter pub get
- flutter analyze
- flutter test
- Compilação Android debug, se o SDK estiver disponível.

Crie testes úteis para:

- Conversão das coordenadas das duas regiões.
- Espelhamento e rotação.
- Isolamento das pontuações.
- Pontuação única por balão.
- Desativação de colisões com rastreamento perdido.

Disponibilize um modo de desenvolvimento com movimentos simulados para validar a lógica sem câmera. Identifique esse modo claramente e não o apresente como rastreamento real.

Se o ambiente não permitir testar câmera, desempenho ou espelhamento em aparelho físico, informe exatamente o que ficou sem validação.

ENTREGA E DOCUMENTAÇÃO

Crie um README em português contendo:

- Preparação do ambiente.
- Como executar no Android.
- Como gerar o APK debug.
- Posicionamento do celular e dos jogadores.
- Seleção da câmera e espelhamento.
- Calibração.
- Como ativar a depuração e o modo simulado.
- Limitações conhecidas.
- Checklist de teste em aparelho físico e TV.

Não crie nem execute GitHub Actions.
Não faça push, merge ou publicação sem solicitação.
Não substitua arquivos existentes sem antes avaliar seu conteúdo.
Não inclua segredos ou caminhos absolutos específicos da sua máquina.

Comece inspecionando o repositório e o ambiente. Depois implemente a estrutura, a captura com duas regiões independentes e o jogo dos balões. Ao terminar, apresente o que foi implementado, os comandos executados e o que ainda precisa ser validado no celular.