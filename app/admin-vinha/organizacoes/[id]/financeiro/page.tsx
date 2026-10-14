'use client';

import { useEffect, useState } from 'react';
import Link from '@/app/admin-vinha/CentralLink';
import { useParams } from 'next/navigation';
import '../../../faturamento/billing.css';
import '../../../faturamento/providers.css';
import '../../../faturamento/financial.css';

type Form = {
  legalName: string;
  taxId: string;
  email: string;
  phone: string;
  postalCode: string;
  address: string;
  addressNumber: string;
  district: string;
  city: string;
  state: string;
};

const empty: Form = {
  legalName: '',
  taxId: '',
  email: '',
  phone: '',
  postalCode: '',
  address: '',
  addressNumber: '',
  district: '',
  city: '',
  state: '',
};

export default function FinancialProfile() {
  const { id } = useParams<{ id: string }>();
  const [form, setForm] = useState<Form>(empty);
  const [church, setChurch] = useState('');
  const [code,setCode]=useState<number|null>(null);
  const [notice, setNotice] = useState('');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    const load = async () => {
      try {
        const res = await fetch(`/api/platform/billing/profiles?id=${encodeURIComponent(id)}`);
        const data = await res.json();
        if (!res.ok) {
          setNotice(data.error || 'Não foi possível carregar o cadastro financeiro.');
          return;
        }

        const profile = data.profile || {};
        setChurch(profile.church_name || '');
        setCode(profile.registration_code||null);
        setForm({
          legalName: profile.legal_name || '',
          taxId: profile.tax_id || '',
          email: profile.email || '',
          phone: profile.phone || '',
          postalCode: profile.postal_code || '',
          address: profile.address || '',
          addressNumber: profile.address_number || '',
          district: profile.district || '',
          city: profile.city || '',
          state: profile.state || '',
        });
      } catch {
        setNotice('Não foi possível carregar o cadastro financeiro.');
      }
    };

    if (id) void load();
  }, [id]);

  async function save(e: React.FormEvent) {
    e.preventDefault();
    setSaving(true);
    setNotice('');

    const payload = {
      churchId: id,
      legalName: form.legalName,
      taxId: form.taxId,
      email: form.email,
      phone: form.phone,
      postalCode: form.postalCode,
      address: form.address,
      addressNumber: form.addressNumber,
      district: form.district,
      city: form.city,
      state: form.state,
    } as Record<string,unknown>;

    try {
      const res = await fetch('/api/platform/billing/profiles', {
        method: 'PUT',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(payload),
      });

      const data = await res.json();

      if (!res.ok) {
        setNotice(data.error || 'Não foi possível salvar o cadastro financeiro.');
        setSaving(false);
        return;
      }

      setNotice('Cadastro financeiro salvo com sucesso.');
    } catch {
      setNotice('Erro ao salvar. Tente novamente.');
    } finally {
      setSaving(false);
    }
  }

  const update = (key: keyof Form, value: string) =>
    setForm((current) => ({ ...current, [key]: value }));

  return (
    <main className="billing-page">
      <aside>
        <Link href="/admin-vinha" className="billing-brand">
          <i>V</i>
          <span><b>Vinha</b><small>Administração SaaS</small></span>
        </Link>
        <nav>
          <Link href="/admin-vinha">▦ Organizações</Link>
          <Link className="on" href="/admin-vinha/faturamento">◫ Cobranças</Link>
        </nav>
        <Link className="billing-back" href="https://app.vinhaigrejas.com.br/painel">← Painel da igreja</Link>
      </aside>

      <section className="financial-editor">
        <header>
          <div>
            <small>CADASTRO FINANCEIRO{code?` · CÓDIGO ${code}`:''}</small>
            <h1>{church || 'Organização'}</h1>
            <p>Preencha os dados da entidade para emissão, cobrança e integração financeira.</p>
          </div>
          <Link className="billing-button secondary" href="/admin-vinha">
            ← Voltar
          </Link>
        </header>

        {notice && <div className="billing-success">{notice}</div>}

        <form onSubmit={save}>
          <div className="billing-grid">
            <label>
              Razão social
              <input value={form.legalName} onChange={(e) => update('legalName', e.target.value)} />
            </label>

            <label>
              CNPJ / CPF
              <input value={form.taxId} onChange={(e) => update('taxId', e.target.value)} />
            </label>

            <label>
              E-mail financeiro
              <input type="email" value={form.email} onChange={(e) => update('email', e.target.value)} />
            </label>

            <label>
              Telefone
              <input value={form.phone} onChange={(e) => update('phone', e.target.value)} />
            </label>

            <label>
              CEP
              <input value={form.postalCode} onChange={(e) => update('postalCode', e.target.value)} />
            </label>

            <label>
              Estado
              <input value={form.state} onChange={(e) => update('state', e.target.value)} />
            </label>

            <label className="full">
              Endereço
              <input value={form.address} onChange={(e) => update('address', e.target.value)} />
            </label>

            <label>
              Número
              <input value={form.addressNumber} onChange={(e) => update('addressNumber', e.target.value)} />
            </label>

            <label>
              Bairro
              <input value={form.district} onChange={(e) => update('district', e.target.value)} />
            </label>

            <label>
              Cidade
              <input value={form.city} onChange={(e) => update('city', e.target.value)} />
            </label>

            <div className="full">
              <button className="billing-button" type="submit" disabled={saving}>
                {saving ? 'Salvando…' : 'Salvar cadastro'}
              </button>
            </div>
          </div>
        </form>
      </section>
    </main>
  );
}
