# Identidade do app da Vinha

Regra do responsável pelo produto: **o app da Vinha não pode ficar igual a nenhum app de mercado (em especial o InChurch).**
Aplicativos de outras empresas servem só para entender **o que** o membro precisa conseguir fazer. Textos, organização das telas,
componentes, ícones e visual são decisões da Vinha.

## Como aplicar em cada tela nova

1. **Nomes e textos próprios.** Não repetir títulos, rótulos de abas, perguntas de formulário ou mensagens de outro app.
   Exemplos já adotados: "Palavra e mensagens", "Avisos da igreja", "Minhas inscrições", "Carteirinha digital",
   "Conheça a igreja", "Para cuidarmos bem", "Seu próximo encontro".
2. **Estrutura própria.** Se a referência usa abas, considerar cartões em grade; se usa chaves liga/desliga, considerar etiquetas
   ou opções. A mesma função pode e deve ter outra forma.
3. **Linguagem visual da Vinha:** capa na cor da igreja com formas suaves, cartões com cantos de 20–24 px, etiquetas arredondadas,
   bloco de data (dia e mês), sobrelinha em caixa alta acima dos títulos de seção e ícones vetoriais próprios (`android-app/src/Icon.tsx`).
4. **Cores e tema vêm do painel:** cor principal e logo da igreja; tema claro ou escuro definido em Configurações (o membro não troca).
   Textos de destaque usam `accentOn` para manter contraste.
5. **Telas de todos os tamanhos:** área segura do sistema, conteúdo até 760 px centralizado em tablets e colunas que se ajustam.

Antes de publicar, comparar a tela nova com as referências e mudar o que estiver parecido em nome, ordem ou forma.
