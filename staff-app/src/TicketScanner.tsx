import {useEffect, useRef, useState} from 'react';
import {ActivityIndicator, Pressable, ScrollView, Text, View} from 'react-native';
import {CameraView, useCameraPermissions} from 'expo-camera';
import * as Haptics from 'expo-haptics';
import {api, ticketCode, type Unit} from './api';
import {colors, ui} from './theme';

type Event = {id: string; title: string; starts_at: string; commerce_mode?: string};
type Result = {tone: 'ok' | 'warn' | 'danger'; title: string; detail: string};

/** Entrance desk: scan the QR of a paid ticket, a free registration or a sale pickup. */
export default function TicketScanner({org, unit, back}: {org: string; unit: Unit; back: () => void}) {
  const [events, setEvents] = useState<Event[] | null>(null),
    [event, setEvent] = useState<Event | null>(null),
    [error, setError] = useState('');
  useEffect(() => {
    api<{items: Event[]}>('/api/programming?' + new URLSearchParams({unit: unit.id, action: 'list', section: 'proximos', page: '1', size: '30'}), org)
      .then((d) => setEvents(d.items || []))
      .catch((e) => setError((e as Error).message));
  }, [org, unit.id]);
  if (event) return <Scanner org={org} unit={unit} event={event} back={() => setEvent(null)} />;
  return (
    <ScrollView contentContainerStyle={ui.pad}>
      <Pressable accessibilityRole="button" onPress={back}>
        <Text style={{color: colors.brand, fontWeight: '600'}}>← Voltar</Text>
      </Pressable>
      <Text style={ui.over}>VALIDAR ENTRADA</Text>
      <Text style={ui.h1}>Qual evento?</Text>
      {error ? (
        <Text style={ui.error}>{error}</Text>
      ) : !events ? (
        <ActivityIndicator color={colors.brand} />
      ) : !events.length ? (
        <Text style={ui.copy}>Nenhum evento ou venda nos próximos dias nesta igreja.</Text>
      ) : (
        events.map((e) => (
          <Pressable key={e.id} accessibilityRole="button" style={ui.card} onPress={() => setEvent(e)}>
            <Text style={ui.h2}>{e.title}</Text>
            <Text style={ui.copy}>
              {new Date(e.starts_at).toLocaleString('pt-BR', {weekday: 'short', day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit'})}
              {e.commerce_mode === 'sale' ? ' · Retirada de vendas' : ''}
            </Text>
          </Pressable>
        ))
      )}
    </ScrollView>
  );
}

function Scanner({org, unit, event, back}: {org: string; unit: Unit; event: Event; back: () => void}) {
  const [permission, requestPermission] = useCameraPermissions(),
    [result, setResult] = useState<Result | null>(null),
    [busy, setBusy] = useState(false),
    [count, setCount] = useState(0),
    last = useRef<{code: string; at: number}>({code: '', at: 0});
  async function check(code: string) {
    // Paid tickets and sale pickups first; free registrations use the agenda check-in.
    try {
      const r = await api<{already?: boolean; name?: string}>('/api/event-tickets-admin', org, {method: 'POST', body: {unit: unit.id, event: event.id, action: 'checkin', data: {code}}});
      return r;
    } catch (paidError) {
      try {
        return await api<{already?: boolean; name?: string}>('/api/programming', org, {method: 'POST', body: {unit: unit.id, action: 'checkin', id: event.id, data: {code}}});
      } catch {
        throw paidError;
      }
    }
  }
  async function onScan(raw: string) {
    const code = ticketCode(raw),
      now = Date.now();
    if (busy || !code || (code === last.current.code && now - last.current.at < 4000)) return;
    last.current = {code, at: now};
    setBusy(true);
    try {
      const r = await check(code);
      if (r.already) {
        setResult({tone: 'warn', title: 'Entrada já registrada', detail: (r.name ? r.name + ' · ' : '') + 'Este QR já foi usado. Confira com a pessoa antes de liberar.'});
        void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning);
      } else {
        setResult({tone: 'ok', title: 'Entrada liberada', detail: r.name || 'Ingresso válido para este evento.'});
        setCount((n) => n + 1);
        void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
      }
    } catch (e) {
      setResult({tone: 'danger', title: 'Não liberar', detail: (e as Error).message || 'QR inválido para este evento.'});
      void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
    } finally {
      setBusy(false);
    }
  }
  if (!permission) return <ActivityIndicator style={{marginTop: 80}} color={colors.brand} />;
  if (!permission.granted)
    return (
      <View style={ui.pad}>
        <Text style={ui.h1}>Câmera</Text>
        <Text style={ui.copy}>A câmera é usada só para ler o QR Code dos ingressos neste aparelho.</Text>
        <Pressable accessibilityRole="button" style={ui.primary} onPress={() => void requestPermission()}>
          <Text style={ui.primaryText}>Permitir câmera</Text>
        </Pressable>
        <Pressable accessibilityRole="button" style={ui.ghost} onPress={back}>
          <Text style={ui.ghostText}>Voltar</Text>
        </Pressable>
      </View>
    );
  const tone = result ? {ok: colors.ok, warn: colors.warn, danger: colors.danger}[result.tone] : colors.brandDark;
  return (
    <View style={{flex: 1, backgroundColor: '#000'}}>
      <CameraView style={{flex: 1}} facing="back" barcodeScannerSettings={{barcodeTypes: ['qr']}} onBarcodeScanned={(s) => void onScan(s.data)} />
      <View style={{backgroundColor: tone, padding: 20, gap: 6}} accessibilityLiveRegion="assertive">
        <Text style={{color: '#fff', fontSize: 13, letterSpacing: 1}}>
          {event.title.toUpperCase()} · {count} {count === 1 ? 'entrada' : 'entradas'} neste aparelho
        </Text>
        <Text style={{color: '#fff', fontSize: 24, fontWeight: '800'}}>{busy ? 'Conferindo…' : result ? result.title : 'Aponte para o QR Code'}</Text>
        {!!result && !busy && <Text style={{color: '#fff', fontSize: 15}}>{result.detail}</Text>}
        <Pressable accessibilityRole="button" onPress={back} style={{marginTop: 8}}>
          <Text style={{color: '#fff', fontWeight: '700'}}>← Trocar evento</Text>
        </Pressable>
      </View>
    </View>
  );
}
