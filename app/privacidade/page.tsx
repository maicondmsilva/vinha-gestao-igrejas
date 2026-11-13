import '../legal.css';

export const metadata = {title: 'Política de privacidade · Vinha'};

/** Política de privacidade pública do painel Vinha e dos aplicativos das igrejas (exigida pelas lojas de aplicativos). */
export default function PrivacyPage() {
  return (
    <main className="legal">
      <h1>Política de privacidade</h1>
      <p className="legal-date">Vale para o painel Vinha e para os aplicativos das igrejas que usam a Vinha. Última atualização: 13/11/2026.</p>

      <h2>Quem cuida dos seus dados</h2>
      <p>
        A sua igreja decide quais dados pede e para que usa: ela é a controladora dos dados, como prevê a Lei Geral de Proteção de Dados
        (Lei 13.709/2018). A Vinha fornece o sistema e trata os dados em nome da igreja, como operadora, seguindo as instruções dela e esta
        política.
      </p>

      <h2>Quais dados usamos</h2>
      <ul>
        <li>Cadastro: nome, e-mail, celular, data de nascimento, gênero, estado civil, endereço, CPF quando a igreja pedir, e foto, se você enviar.</li>
        <li>Vida na igreja: igreja local, células, ministérios, escalas, inscrições em eventos, tickets e carteirinhas.</li>
        <li>Família e Kids: vínculos familiares, crianças sob sua responsabilidade e as informações de cuidado que você informar (alergias, restrições e autorização de fotos).</li>
        <li>Contribuições: valor, finalidade e situação do pagamento. Os dados do cartão ficam com o provedor de pagamento e não são guardados pela Vinha.</li>
        <li>Uso do aplicativo: vídeos assistidos e ponto onde parou, favoritos, anotações, pedidos de oração e testemunhos que você enviar.</li>
        <li>Dispositivo: identificador para notificações e registros técnicos de acesso, para segurança.</li>
      </ul>

      <h2>Para que usamos</h2>
      <ul>
        <li>Manter seu cadastro na igreja e permitir que a equipe autorizada acompanhe você.</li>
        <li>Inscrições, entrada em eventos, escalas, células, Kids e comunicação da igreja.</li>
        <li>Registrar contribuições e emitir comprovantes.</li>
        <li>Enviar avisos e notificações que você pode desativar a qualquer momento.</li>
        <li>Proteger a conta, evitar fraudes e cumprir obrigações legais.</li>
      </ul>

      <h2>Quem vê seus dados</h2>
      <p>
        Somente pessoas da sua igreja com permissão para aquela área (por exemplo, a secretaria, os pastores, o líder da sua célula ou a equipe
        Kids), cada uma limitada ao que precisa. Pedidos de oração e testemunhos só são publicados com a sua autorização. A Vinha não vende
        dados. Usamos fornecedores que hospedam o sistema, enviam e-mails e notificações e processam pagamentos, todos com obrigação de
        sigilo.
      </p>

      <h2>Seus direitos</h2>
      <p>
        Você pode consultar, corrigir e atualizar seus dados pelo aplicativo, pedir informações sobre o uso, revogar autorizações e pedir a
        exclusão da conta. A exclusão pode ser feita no aplicativo (menu Mais) ou em <a href="/conta/excluir">app.vinhaigrejas.com.br/conta/excluir</a>.
        Alguns registros, como contribuições, podem ser guardados pelo prazo exigido em lei.
      </p>

      <h2>Crianças</h2>
      <p>Dados de crianças são informados e controlados pelo responsável e acessados apenas pela equipe Kids autorizada da igreja.</p>

      <h2>Segurança e guarda</h2>
      <p>
        Os dados ficam em servidores com acesso restrito e criptografia na transmissão. Guardamos as informações enquanto você tiver vínculo
        com a igreja ou pelo prazo necessário para cumprir obrigações legais.
      </p>

      <h2>Contato</h2>
      <p>
        Para exercer seus direitos, fale com a secretaria da sua igreja. Se preferir, use o atendimento da Vinha dentro do painel ou do
        aplicativo. Esta política pode ser atualizada; a data no início da página mostra a versão em vigor.
      </p>
    </main>
  );
}
