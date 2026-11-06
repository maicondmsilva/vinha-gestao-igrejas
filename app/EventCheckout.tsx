"use client";
import TicketQuestionField from "./TicketQuestionField";
import { useEffect, useState } from "react";
import QRCode from "qrcode";
import {
  ticketMoney,
  ticketState,
  type TicketCatalog,
  type TicketOrder,
  type TicketParticipant,
} from "../shared/event-tickets";
import "./event-tickets.css";
import EventOrderSupport from "./EventOrderSupport";
type Pix = { paymentId: string; qrCode: string; qrImage: string; ticketUrl: string; expiresAt: string };
type Order = TicketOrder & { paymentMessage?: string; pixAvailable?: boolean; pix?: Pix };
type Quote = { total: string; subtotal: string; discount: string; revision: number };
type Attempt = { id: string; proof: string; data?: unknown };
const newAttempt = (): Attempt => ({
  id: crypto.randomUUID(),
  proof: Array.from(crypto.getRandomValues(new Uint8Array(32)), (x) => x.toString(16).padStart(2, "0")).join(
    "",
  ),
});
const commonDomains: Record<string, string> = {
  "gmail.co": "gmail.com",
  "gmail.con": "gmail.com",
  "gmai.com": "gmail.com",
  "gmial.com": "gmail.com",
  "gamil.com": "gmail.com",
  "hotmail.co": "hotmail.com",
  "hotmail.con": "hotmail.com",
  "hotmal.com": "hotmail.com",
  "outlook.co": "outlook.com",
  "outlok.com": "outlook.com",
  "yahoo.com.b": "yahoo.com.br",
  "icloud.co": "icloud.com",
};
/** Suggests a fix for frequent typos, replacing the old "type your e-mail twice" field. */
export function emailHint(value: string) {
  const [user, domain] = value.trim().toLowerCase().split("@");
  return user && domain && commonDomains[domain] ? user + "@" + commonDomains[domain] : null;
}
async function command(event: string, attempt: Attempt, action: string, data: unknown = {}) {
  const r = await fetch("/api/event-orders", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ event, ...attempt, data, action }),
    }),
    d = (await r.json()) as Order & Quote & { error?: string };
  if (!r.ok) throw Error(d.error || "Pedido indisponível.");
  return d;
}
export default function EventCheckout({
  event,
  church,
  title,
}: {
  event: string;
  church: string;
  title: string;
}) {
  const [catalog, setCatalog] = useState<TicketCatalog | null>(null),
    [quantities, setQuantities] = useState<Record<string, number>>({}),
    [participants, setParticipants] = useState<TicketParticipant[]>([]),
    [step, setStep] = useState<"form" | "review">("form"),
    [buyer, setBuyer] = useState({
      buyerName: "",
      buyerEmail: "",
      buyerPhone: "",
      coupon: "",
      intent: "pay",
      emailConsent: false,
    }),
    [couponOpen, setCouponOpen] = useState(false),
    [quote, setQuote] = useState<Quote | null>(null),
    [attempt, setAttempt] = useState<Attempt | null>(null),
    [order, setOrder] = useState<Order | null>(null),
    [pix, setPix] = useState<Pix | null>(null),
    [copied, setCopied] = useState(false),
    [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  const storage = "vinha-event-order:" + event;
  useEffect(() => {
    let live = true;
    fetch("/api/event-tickets?event=" + event, { cache: "no-store" })
      .then(async (r) => {
        const d = (await r.json()) as TicketCatalog & { error?: string };
        if (!r.ok) throw Error(d.error);
        if (live) setCatalog(d);
      })
      .catch((e) => {
        if (live) setError(e.message);
      });
    try {
      const raw = localStorage.getItem(storage),
        requested = new URLSearchParams(location.search).get("pedido");
      if (raw || requested) {
        const a = raw ? (JSON.parse(raw) as Attempt) : { ...newAttempt(), id: requested! };
        if (/^[0-9a-f]{64}$/.test(a.proof) && a.id) {
          setAttempt(a);
          command(event, a, "status")
            .then((d) => {
              if (live) setOrder(d);
            })
            .catch(() => {
              if (live) setError("Há uma tentativa salva. Consulte o pedido antes de iniciar outro.");
            });
        }
      }
    } catch {
      /* Browsers may disable persistent storage. */
    }
    return () => {
      live = false;
    };
  }, [event]);
  // Same order, same Pix: the server derives the idempotency key from the order, so retrying never creates a second charge.
  async function requestPix(a: Attempt | null = attempt) {
    if (!a) return;
    setBusy(true);
    setError("");
    try {
      const d = await command(event, a, "pix");
      setOrder((current) => ({ ...d, paymentMessage: current?.paymentMessage }));
      if (d.pix) setPix(d.pix);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  async function copyPix() {
    if (!pix) return;
    try {
      await navigator.clipboard.writeText(pix.qrCode);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2500);
    } catch {
      setError("Não foi possível copiar. Selecione o código e copie manualmente.");
    }
  }
  async function run(action: string) {
    if (!attempt || busy) return;
    setBusy(true);
    setError("");
    try {
      const d = await command(event, attempt, action, action === "create" ? attempt.data : {});
      setOrder(d);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  // While the provider confirms, the order refreshes by itself; the webhook remains the only source of truth.
  useEffect(() => {
    if (!order || !attempt || !["holding", "payment_review"].includes(order.state)) return;
    const started = Date.now();
    const timer = window.setInterval(() => {
      if (document.visibilityState !== "visible") return;
      if (Date.now() - started > 15 * 60 * 1000) return window.clearInterval(timer);
      command(event, attempt, "status")
        .then((d) => setOrder((current) => (current ? { ...d, paymentMessage: current.paymentMessage } : d)))
        .catch(() => undefined);
    }, 6000);
    return () => window.clearInterval(timer);
  }, [order?.state, attempt, event]);
  if (!catalog)
    return (
      <section id="inscricoes" className="ve-card vt-checkout">
        <h2>Pedidos e inscrições</h2>
        <p role="status">{error || "Consultando ingressos…"}</p>
      </section>
    );
  if (!catalog.enabled && !order) return null;
  const sale = catalog.commerceMode === "sale";
  // The server contract keeps emailConfirmation; the page fills it so the buyer types the e-mail once.
  const payload = () => ({
    buyerName: buyer.buyerName.trim(),
    buyerEmail: buyer.buyerEmail.trim(),
    emailConfirmation: buyer.buyerEmail.trim(),
    coupon: buyer.coupon,
    intent: hasPaid ? "pay" : buyer.intent,
    emailConsent: buyer.emailConsent,
    items: participants.map((p, i) =>
      sale
        ? { ...p, name: buyer.buyerName.trim(), email: buyer.buyerEmail.trim(), phone: p.phone || buyer.buyerPhone }
        : {
            ...p,
            name: (p.name || (i === 0 ? buyer.buyerName : "")).trim(),
            email: p.email || (i === 0 ? buyer.buyerEmail.trim() : ""),
            phone: p.phone || (i === 0 ? buyer.buyerPhone : ""),
          },
    ),
  });
  const selected = (catalog.types || []).filter((t) => quantities[t.id] > 0),
    count = Object.values(quantities).reduce((a, b) => a + b, 0),
    hasPaid = selected.some((t) => t.mode === "paid"),
    hasReservation = selected.some((t) => t.mode === "reservation"),
    // Display only: the server quote decides the amount charged (coupons, availability, revisions).
    estimate = selected.reduce((sum, t) => sum + Number(t.price || 0) * (quantities[t.id] || 0), 0);
  // Participants follow the chosen quantities, so buyers fill one page instead of a separate step.
  function changeQuantity(type: string, n: number) {
    const next = { ...quantities, [type]: n };
    setQuantities(next);
    setParticipants((current) =>
      (catalog?.types || []).flatMap((t) => {
        const kept = current.filter((p) => p.type === t.id);
        return Array.from(
          { length: next[t.id] || 0 },
          (_, i) => kept[i] || { type: t.id, name: "", email: "", cpf: "", phone: "", answers: {} },
        );
      }),
    );
    setQuote(null);
  }
  function update(i: number, k: keyof TicketParticipant, value: string | Record<string, string>) {
    setParticipants((v) => v.map((p, j) => (j === i ? { ...p, [k]: value } : p)));
    setQuote(null);
  }
  return (
    <section id="inscricoes" className="ve-card vt-checkout">
      <div className="vt-heading">
        <div>
          <span className="ve-eyebrow">
            {sale ? "PRODUTOS DA SUA COMUNIDADE" : "SEU LUGAR NESTE ENCONTRO"}
          </span>
          <h2>{order ? "Seu pedido" : sale ? "Escolha seus produtos" : "Inscreva-se"}</h2>
        </div>
        <span>
          {order
            ? ticketState(order.state)
            : step === "form"
              ? "1 · Escolha e seus dados"
              : "2 · Confirmar"}
        </span>
      </div>
      {sale && catalog.pickupAt && (
        <p className="vt-pickup">
          <b>Retirada:</b> {new Date(catalog.pickupAt).toLocaleString("pt-BR")} até{" "}
          {catalog.pickupUntil ? new Date(catalog.pickupUntil).toLocaleString("pt-BR") : ""} ·{" "}
          {catalog.pickupLocation || "Consulte o local informado acima."}
        </p>
      )}
      {error && (
        <p role="alert" className="program-error">
          {error}
        </p>
      )}
      {!order && !catalog.authenticated && !catalog.allowGuests ? (
        <p>
          Entre na conta da sua igreja para se inscrever.{" "}
          <a href={"/membro/" + church}>Acessar minha conta →</a>
        </p>
      ) : order ? (
        <>
          <div className={"vt-order " + order.state}>
            <h3>{ticketState(order.state)}</h3>
            <p>
              Pedido {order.id.slice(0, 8).toUpperCase()} · {order.buyerName}
            </p>
            <div className="vt-total">
              <span>Total {ticketMoney(order.total)}</span>
              {Number(order.discount) > 0 && <small>Desconto aplicado: {ticketMoney(order.discount)}</small>}
            </div>
            {["holding", "reserved"].includes(order.state) && (
              <p>
                {sale ? "Estoque reservado até" : "Vaga mantida até"}{" "}
                {new Date(order.expires).toLocaleString("pt-BR")}. Após esse prazo, a disponibilidade será
                conferida novamente.
              </p>
            )}
            {order.paymentMessage && <p role="status">{order.paymentMessage}</p>}
            {order.state === "payment_review" && (
              <p>A organização precisa conferir o pagamento e a disponibilidade. Não pague novamente.</p>
            )}
            {order.state === "holding" && Number(order.total) > 0 && pix ? (
              <div className="vt-pix">
                <h3>Pague com Pix</h3>
                <p>Abra o app do seu banco, escolha Pix e leia o QR Code ou cole o código.</p>
                {/* eslint-disable-next-line @next/next/no-img-element -- data URI from the provider, not optimizable */}
                <img src={pix.qrImage} alt="QR Code Pix do pedido" width={220} height={220} />
                <label>
                  Pix copia e cola
                  <textarea readOnly rows={3} value={pix.qrCode} onFocus={(e) => e.currentTarget.select()} />
                </label>
                <button type="button" className="ve-primary" onClick={() => void copyPix()}>
                  {copied ? "Código copiado ✓" : "Copiar código Pix"}
                </button>
                <p className="vt-hint">
                  Válido até {new Date(pix.expiresAt).toLocaleString("pt-BR")}. Assim que o banco confirmar, esta página
                  mostra seu {sale ? "pedido" : "ingresso"} automaticamente.
                </p>
                {order.checkoutUrl && (
                  <p className="vt-hint">
                    Prefere cartão?{" "}
                    <a href={order.checkoutUrl} rel="noopener noreferrer">
                      Pagar com cartão
                    </a>{" "}
                    (use só um dos dois).
                  </p>
                )}
              </div>
            ) : (
              order.state === "holding" &&
              Number(order.total) > 0 &&
              order.checkoutUrl && (
                <div className="ve-actions">
                  <button type="button" className="ve-primary" disabled={busy} onClick={() => void requestPix()}>
                    {busy ? "Gerando Pix…" : "Pagar com Pix aqui"}
                  </button>
                  <a href={order.checkoutUrl} rel="noopener noreferrer">
                    Pagar com cartão
                  </a>
                </div>
              )
            )}
            <div className="ve-actions">
              {order.state === "reserved" && (
                <button type="button" disabled={busy} onClick={() => void run("pay")}>
                  Pagar esta reserva
                </button>
              )}
              {order.state === "holding" && !order.checkoutUrl && order.checkoutState === "reserved" && (
                <button type="button" disabled={busy} onClick={() => void run("pay")}>
                  Preparar pagamento
                </button>
              )}
              <button type="button" disabled={busy} onClick={() => void run("status")}>
                Atualizar situação
              </button>
              {(order.state === "reserved" ||
                (order.state === "confirmed" &&
                  Number(order.total) === 0 &&
                  !order.items.some((i) => i.checkedIn))) && (
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => {
                    if (window.confirm("Cancelar a inscrição e liberar as vagas?")) void run("cancel");
                  }}
                >
                  Cancelar inscrição / reserva
                </button>
              )}
            </div>
          </div>
          <div className="vt-grid">
            {order.items.map((i) => (
              <TicketReceipt key={i.id} item={i} title={title} sale={sale} />
            ))}
          </div>
          <EventOrderSupport event={event} order={order} proof={attempt?.proof || ""} />
          <p>
            Guarde este pedido neste navegador. A confirmação do pagamento vem da instituição recebedora; o
            retorno do checkout não confirma a entrada.
          </p>
          {!catalog.authenticated && (
            <p>
              Quer acompanhar a vida da sua igreja?{" "}
              <a href={"/membro/" + church}>Criar uma conta ou entrar →</a>. Sua inscrição permanece válida
              sem cadastro.
            </p>
          )}
          {["confirmed", "cancelled", "expired"].includes(order.state) && (
            <button
              type="button"
              disabled={busy}
              onClick={() => {
                localStorage.removeItem(storage);
                setOrder(null);
                setAttempt(null);
                setStep("form");
                setQuote(null);
              }}
            >
              {sale ? "Fazer outro pedido" : "Fazer outra inscrição"}
            </button>
          )}
        </>
      ) : (
        <>
          {step === "form" ? (
            <form
              className="vt-onepage"
              onSubmit={async (e) => {
                e.preventDefault();
                if (busy || count < 1) return;
                setBusy(true);
                setError("");
                try {
                  const a = attempt || newAttempt();
                  setAttempt(a);
                  const q = await command(event, a, "quote", payload());
                  setQuote(q);
                  setStep("review");
                } catch (x) {
                  setError((x as Error).message);
                } finally {
                  setBusy(false);
                }
              }}
            >
              <fieldset disabled={busy}>
                <div className="vt-ticket-list">
                  {catalog.types.map((t) => {
                    const closed =
                      Date.parse(t.starts) > Date.now() ||
                      Date.parse(t.ends) <= Date.now() ||
                      t.remaining === 0 ||
                      (t.mode !== "free" && !catalog.canPay);
                    const max = Math.min(20, t.remaining ?? 20, t.perUser ?? 20),
                      value = quantities[t.id] || 0,
                      set = (n: number) => changeQuantity(t.id, Math.max(0, Math.min(max, n)));
                    return (
                      <article className={"vt-ticket" + (value > 0 ? " is-selected" : "")} key={t.id}>
                        <div>
                          <h3>{t.name}</h3>
                          <strong>{t.mode === "free" ? "Gratuito" : ticketMoney(t.price)}</strong>
                          <p>
                            {t.remaining !== null ? t.remaining + " disponível(is) · " : ""}
                            até {new Date(t.ends).toLocaleDateString("pt-BR")}
                            {t.perCpf ? " · pede CPF" : ""}
                          </p>
                          {t.mode !== "free" && !catalog.canPay && (
                            <small>Recebimento ainda não habilitado pela organização.</small>
                          )}
                          {closed && catalog.canPay && <small>Indisponível no momento.</small>}
                        </div>
                        <div className="vt-stepper" aria-label={"Quantidade de " + t.name}>
                          <button
                            type="button"
                            aria-label={"Diminuir " + t.name}
                            disabled={closed || value < 1}
                            onClick={() => set(value - 1)}
                          >
                            −
                          </button>
                          <output aria-live="polite">{value}</output>
                          <button
                            type="button"
                            aria-label={"Aumentar " + t.name}
                            disabled={closed || value >= max}
                            onClick={() => set(value + 1)}
                          >
                            +
                          </button>
                        </div>
                      </article>
                    );
                  })}
                </div>
                {!catalog.types.length && <p>Os ingressos ainda não estão disponíveis para seu perfil.</p>}
                {count > 0 && (
                  <>
                    <h3>Seus dados</h3>
                    <p className="vt-hint">
                      {catalog.authenticated
                        ? "Use o e-mail da sua conta."
                        : "Sem cadastro: o pedido e o comprovante chegam no seu e-mail."}
                    </p>
                    <div className="vt-grid">
                      <label>
                        Nome completo
                        <input
                          required
                          autoComplete="name"
                          minLength={2}
                          maxLength={160}
                          value={buyer.buyerName}
                          onChange={(e) => setBuyer((v) => ({ ...v, buyerName: e.target.value }))}
                        />
                      </label>
                      <label>
                        E-mail
                        <input
                          type="email"
                          required
                          autoComplete="email"
                          maxLength={254}
                          value={buyer.buyerEmail}
                          onChange={(e) => setBuyer((v) => ({ ...v, buyerEmail: e.target.value }))}
                        />
                        {emailHint(buyer.buyerEmail) && (
                          <button
                            type="button"
                            className="vt-link"
                            onClick={() => setBuyer((v) => ({ ...v, buyerEmail: emailHint(v.buyerEmail)! }))}
                          >
                            Você quis dizer {emailHint(buyer.buyerEmail)}?
                          </button>
                        )}
                      </label>
                      <label>
                        WhatsApp (opcional)
                        <input
                          type="tel"
                          inputMode="tel"
                          autoComplete="tel"
                          maxLength={22}
                          value={buyer.buyerPhone}
                          onChange={(e) => setBuyer((v) => ({ ...v, buyerPhone: e.target.value }))}
                        />
                      </label>
                    </div>
                    {participants.map((p, i) => {
                      const type = catalog.types.find((t) => t.id === p.type),
                        needsCpf = !!type?.perCpf,
                        needsName = !sale && (participants.length > 1 || i > 0);
                      if (!needsCpf && !needsName && !catalog.questions.length) return null;
                      return (
                        <section className="vt-panel" key={i}>
                          <h4>
                            {sale ? "Item" : "Participante"} {i + 1} · {type?.name}
                            {!sale && i === 0 ? " (você, se deixar o nome em branco)" : ""}
                          </h4>
                          <div className="vt-grid">
                            {!sale && (
                              <label>
                                Nome do participante
                                <input
                                  required={i > 0}
                                  minLength={2}
                                  maxLength={160}
                                  value={p.name}
                                  placeholder={i === 0 ? buyer.buyerName : ""}
                                  onChange={(e) => update(i, "name", e.target.value)}
                                />
                              </label>
                            )}
                            {needsCpf && (
                              <label>
                                CPF
                                <input
                                  inputMode="numeric"
                                  required
                                  maxLength={14}
                                  value={p.cpf}
                                  onChange={(e) =>
                                    update(
                                      i,
                                      "cpf",
                                      e.target.value
                                        .replace(/\D/g, "")
                                        .slice(0, 11)
                                        .replace(/(\d{3})(\d)/, "$1.$2")
                                        .replace(/(\d{3})(\d)/, "$1.$2")
                                        .replace(/(\d{3})(\d{1,2})$/, "$1-$2"),
                                    )
                                  }
                                />
                              </label>
                            )}
                            {catalog.questions.map((q) => (
                              <TicketQuestionField
                                key={q.id}
                                question={q}
                                value={p.answers[q.id] || ""}
                                change={(v) => update(i, "answers", { ...p.answers, [q.id]: v })}
                              />
                            ))}
                          </div>
                        </section>
                      );
                    })}
                    {hasReservation && !hasPaid && (
                      <label>
                        Como deseja continuar?
                        <select
                          value={buyer.intent}
                          onChange={(e) => setBuyer((v) => ({ ...v, intent: e.target.value }))}
                        >
                          <option value="pay">Pagar agora</option>
                          <option value="reserve">Apenas reservar e pagar depois</option>
                        </select>
                      </label>
                    )}
                    {couponOpen ? (
                      <label>
                        Cupom de desconto
                        <input
                          maxLength={40}
                          autoFocus
                          value={buyer.coupon}
                          onChange={(e) =>
                            setBuyer((v) => ({ ...v, coupon: e.target.value.toUpperCase().replace(/\s/g, "") }))
                          }
                        />
                      </label>
                    ) : (
                      <button type="button" className="vt-link" onClick={() => setCouponOpen(true)}>
                        Tenho um cupom
                      </button>
                    )}
                    <label className="vt-consent">
                      <input
                        type="checkbox"
                        checked={buyer.emailConsent}
                        onChange={(e) => setBuyer((v) => ({ ...v, emailConsent: e.target.checked }))}
                      />
                      <span>Quero receber avisos deste evento por e-mail.</span>
                    </label>
                  </>
                )}
                <div className="vt-sticky-cta">
                  <span>
                    {count} {count === 1 ? "item" : "itens"} · {ticketMoney(estimate)}
                  </span>
                  <button type="submit" className="ve-primary" disabled={busy || count < 1 || count > 20}>
                    {busy ? "Calculando…" : "Continuar"}
                  </button>
                </div>
              </fieldset>
            </form>
          ) : (
            quote && (
              <>
                <div className="vt-order">
                  <h3>Confira antes de finalizar</h3>
                  <p>
                    {buyer.buyerName} · {buyer.buyerEmail}
                  </p>
                  {payload().items.map((p, i) => (
                    <p key={i}>
                      {p.name} · {catalog.types.find((t) => t.id === p.type)?.name}
                    </p>
                  ))}
                  {Number(quote.discount) > 0 && (
                    <p>
                      Subtotal {ticketMoney(quote.subtotal)}
                      <br />
                      Desconto {ticketMoney(quote.discount)}
                    </p>
                  )}
                  <strong className="vt-total">Total {ticketMoney(quote.total)}</strong>
                  <p>
                    {buyer.intent === "reserve" && Number(quote.total) > 0
                      ? "A reserva será mantida pelo prazo informado no pedido. Você poderá pagar depois."
                      : Number(quote.total) > 0
                        ? "Você seguirá para o pagamento seguro. A confirmação será registrada após a aprovação."
                        : "Sua inscrição será confirmada sem pagamento."}
                  </p>
                </div>
                <div className="ve-actions">
                  <button
                    type="button"
                    disabled={busy}
                    onClick={() => {
                      setStep("form");
                      setQuote(null);
                    }}
                  >
                    {sale ? "Editar dados do pedido" : "Editar participantes"}
                  </button>
                  <button
                    type="button"
                    className="ve-primary"
                    disabled={busy}
                    onClick={async () => {
                      if (busy) return;
                      setBusy(true);
                      setError("");
                      try {
                        const a = {
                          ...(attempt || newAttempt()),
                          data: { ...payload(), expectedTotal: quote.total, revision: quote.revision },
                        };
                        localStorage.setItem(storage, JSON.stringify(a));
                        setAttempt(a);
                        const d = await command(event, a, "create", a.data);
                        setOrder(d);
                        // Pix appears right here when the receiver accepts it; otherwise go straight to the provider.
                        if (d.checkoutUrl && d.state === "holding" && Number(d.total) > 0) {
                          if (d.pixAvailable) await requestPix(a);
                          else window.location.assign(d.checkoutUrl);
                        }
                      } catch (x) {
                        setError((x as Error).message);
                      } finally {
                        setBusy(false);
                      }
                    }}
                  >
                    {busy
                      ? "Confirmando…"
                      : Number(quote.total) === 0
                        ? sale
                          ? "Confirmar pedido"
                          : "Confirmar inscrição"
                        : buyer.intent === "reserve" && !hasPaid
                          ? "Confirmar reserva"
                          : "Pagar " + ticketMoney(quote.total)}
                  </button>
                </div>
              </>
            )
          )}
          {attempt && !order && (
            <div className="ve-actions">
              <button type="button" disabled={busy} onClick={() => void run("status")}>
                Consultar tentativa salva
              </button>
              {!!attempt.data && (
                <button type="button" disabled={busy} onClick={() => void run("create")}>
                  Retomar a mesma tentativa
                </button>
              )}
            </div>
          )}
        </>
      )}
    </section>
  );
}
function TicketReceipt({
  item: i,
  title,
  sale = false,
}: {
  item: TicketOrder["items"][number];
  title: string;
  sale?: boolean;
}) {
  const [qr, setQr] = useState("");
  useEffect(() => {
    if (i.code) void QRCode.toDataURL(i.code, { width: 240, margin: 2 }).then(setQr);
  }, [i.code]);
  return (
    <article className="vt-ticket vt-receipt">
      <span className="ve-eyebrow">{title}</span>
      <h3>{i.name}</h3>
      <p>{i.ticket}</p>
      {i.checkedIn ? (
        <strong>{sale ? "Retirada já registrada" : "Entrada já registrada"}</strong>
      ) : i.code ? (
        <>
          {qr && (
            <img
              src={qr}
              alt={sale ? "QR Code para retirada" : "QR Code individual para entrada"}
              width={200}
              height={200}
            />
          )}
          <code>{i.code}</code>
          <button type="button" onClick={() => window.print()}>
            {sale ? "Imprimir comprovante de retirada" : "Imprimir / salvar ticket em PDF"}
          </button>
        </>
      ) : (
        <p>QR Code disponível após a confirmação.</p>
      )}
    </article>
  );
}
