import '../legal.css';

export const metadata = {title: 'Termos de uso · Vinha'};

/** Termos de uso públicos do painel Vinha e dos aplicativos das igrejas. */
export default function TermsPage() {
  return (
    <main className="legal">
      <h1>Termos de uso</h1>
      <p className="legal-date">Vale para o painel Vinha e para os aplicativos das igrejas que usam a Vinha. Última atualização: 13/11/2026.</p>

      <h2>O serviço</h2>
      <p>
        A Vinha é um sistema de gestão para igrejas. Cada igreja usa a Vinha para cuidar do seu cadastro, da sua agenda, da sua comunicação e
        do seu aplicativo. O conteúdo publicado (avisos, vídeos, eventos e materiais) é de responsabilidade da igreja que o publicou.
      </p>

      <h2>Sua conta</h2>
      <ul>
        <li>Use informações verdadeiras e mantenha sua senha em sigilo.</li>
        <li>Sua conta é pessoal. Não compartilhe tickets, QR Codes ou carteirinhas com outras pessoas.</li>
        <li>A igreja pode revisar seu cadastro e definir o que você acessa conforme a sua função.</li>
      </ul>

      <h2>Uso adequado</h2>
      <p>
        Não envie conteúdo ofensivo, ilegal ou que exponha outras pessoas em pedidos de oração, testemunhos, anotações ou mensagens. A igreja
        pode recusar ou retirar conteúdos e suspender contas que descumpram estas regras.
      </p>

      <h2>Contribuições e eventos</h2>
      <p>
        Contribuições e compras são feitas com a igreja e processadas por provedores de pagamento. Regras de cancelamento, reembolso e entrada
        em eventos são definidas pela igreja e informadas em cada evento.
      </p>

      <h2>Vídeos de terceiros</h2>
      <p>Vídeos do YouTube ou do Vimeo são exibidos pelos players desses serviços e seguem também as regras deles.</p>

      <h2>Privacidade</h2>
      <p>
        O uso dos seus dados está descrito na <a href="/privacidade">Política de privacidade</a>. Você pode excluir sua conta a qualquer momento
        pelo aplicativo ou em <a href="/conta/excluir">app.vinhaigrejas.com.br/conta/excluir</a>.
      </p>

      <h2>Alterações</h2>
      <p>Estes termos podem ser atualizados. A data no início da página mostra a versão em vigor.</p>
    </main>
  );
}
