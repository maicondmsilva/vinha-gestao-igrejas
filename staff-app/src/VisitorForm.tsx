import {useState} from 'react';
import {ActivityIndicator, Pressable, ScrollView, Text, TextInput, View} from 'react-native';
import {supabase} from './supabase';
import {colors, ui} from './theme';
import type {Unit} from './api';
import {visitorError, visitorHeard, visitorPhoneMask} from '../../shared/visitors.ts';

/** Vinha Equipe: a recepção cadastra o visitante na hora (mesmo destino do QR Code: Pessoas › Visitante). */
export default function VisitorForm({org, unit, back}: {org: string; unit: Unit; back: () => void}) {
  const [name, setName] = useState(''),
    [phone, setPhone] = useState(''),
    [email, setEmail] = useState(''),
    [firstTime, setFirstTime] = useState(true),
    [heard, setHeard] = useState(''),
    [contact, setContact] = useState(true),
    [visit, setVisit] = useState(false),
    [prayer, setPrayer] = useState(''),
    [note, setNote] = useState(''),
    [busy, setBusy] = useState(false),
    [error, setError] = useState(''),
    [done, setDone] = useState<string[]>([]);
  async function save() {
    if (!supabase || busy) return;
    setError('');
    if (name.trim().split(/\s+/).length < 2) return setError('Digite nome e sobrenome.');
    if (phone.replace(/\D/g, '').length < 10) return setError('Digite o WhatsApp com DDD.');
    setBusy(true);
    const r = await supabase.rpc('visitor_staff', {
      p_org: org,
      p_unit: unit.id,
      p_action: 'save',
      p_data: {name, phone, email, firstTime, contact, visit, prayer, note, ...(heard ? {heard} : {})},
    });
    setBusy(false);
    if (r.error) return setError(visitorError(r.error.message));
    setDone((d) => [name.trim(), ...d].slice(0, 10));
    setName('');
    setPhone('');
    setEmail('');
    setHeard('');
    setPrayer('');
    setNote('');
    setFirstTime(true);
    setVisit(false);
    setContact(true);
  }
  const chip = (on: boolean, label: string, onPress: () => void) => (
    <Pressable key={label} accessibilityRole="button" accessibilityState={{selected: on}} onPress={onPress} style={[ui.chip, on && ui.chipOn]}>
      <Text style={{color: on ? '#fff' : colors.text, fontWeight: '700'}}>{label}</Text>
    </Pressable>
  );
  return (
    <ScrollView contentContainerStyle={[ui.pad, {paddingTop: 24}]} keyboardShouldPersistTaps="handled">
      <Text style={ui.over}>RECEPÇÃO · {unit.name.toUpperCase()}</Text>
      <Text style={ui.h1}>Cadastrar visitante</Text>
      <Text style={ui.copy}>O cadastro entra em Pessoas como Visitante, com acompanhamento pendente para a equipe de integração.</Text>
      {done.length > 0 && <Text style={[ui.copy, {color: colors.ok, fontWeight: '700'}]}>Cadastrado: {done.join(', ')}</Text>}
      <Text style={ui.label}>Nome e sobrenome</Text>
      <TextInput style={ui.input} value={name} onChangeText={setName} autoCapitalize="words" maxLength={120} />
      <Text style={ui.label}>WhatsApp</Text>
      <TextInput style={ui.input} value={phone} onChangeText={(v) => setPhone(visitorPhoneMask(v))} keyboardType="phone-pad" placeholder="(11) 98888-7777" />
      <Text style={ui.label}>E-mail (opcional)</Text>
      <TextInput style={ui.input} value={email} onChangeText={setEmail} autoCapitalize="none" keyboardType="email-address" maxLength={160} />
      <Text style={ui.label}>Primeira vez?</Text>
      <View style={{flexDirection: 'row', gap: 8}}>
        {chip(firstTime, 'Sim', () => setFirstTime(true))}
        {chip(!firstTime, 'Já veio antes', () => setFirstTime(false))}
      </View>
      <Text style={ui.label}>Como conheceu a igreja</Text>
      <View style={{flexDirection: 'row', flexWrap: 'wrap', gap: 8}}>
        {visitorHeard.map(([k, l]) => chip(heard === k, l, () => setHeard(heard === k ? '' : k)))}
      </View>
      <View style={{flexDirection: 'row', flexWrap: 'wrap', gap: 8}}>
        {chip(contact, 'Aceita contato', () => setContact(!contact))}
        {chip(visit, 'Quer receber visita', () => setVisit(!visit))}
      </View>
      <Text style={ui.label}>Pedido de oração (opcional)</Text>
      <TextInput style={[ui.input, {minHeight: 80}]} value={prayer} onChangeText={setPrayer} multiline maxLength={500} />
      <Text style={ui.label}>Observação da recepção (opcional)</Text>
      <TextInput style={ui.input} value={note} onChangeText={setNote} maxLength={300} placeholder="Ex.: veio com a família Souza" />
      {!!error && (
        <Text accessibilityRole="alert" style={ui.error}>
          {error}
        </Text>
      )}
      <Pressable accessibilityRole="button" style={[ui.primary, busy && {opacity: 0.6}]} disabled={busy} onPress={() => void save()}>
        {busy ? <ActivityIndicator color="#fff" /> : <Text style={ui.primaryText}>Salvar visitante</Text>}
      </Pressable>
      <Pressable accessibilityRole="button" style={ui.ghost} onPress={back}>
        <Text style={ui.ghostText}>Voltar</Text>
      </Pressable>
    </ScrollView>
  );
}
