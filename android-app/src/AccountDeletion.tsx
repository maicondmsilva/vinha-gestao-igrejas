import {useState} from 'react';
import {ActivityIndicator, Pressable, StyleSheet, Text, TextInput, View} from 'react-native';
import {supabase} from './supabase';

type Palette = {surface: string; line: string; text: string; muted: string};

/**
 * Account deletion inside the app (App Store 5.1.1(v), Google Play).
 * The server closes only the caller's own account; church records required by law stay with the church.
 */
export default function AccountDeletion({palette, onDeleted}: {palette: Palette; onDeleted: () => void}) {
  const [open, setOpen] = useState(false),
    [confirm, setConfirm] = useState(''),
    [busy, setBusy] = useState(false),
    [notice, setNotice] = useState('');
  async function remove() {
    if (busy || confirm.trim().toUpperCase() !== 'EXCLUIR' || !supabase) return;
    setBusy(true);
    setNotice('');
    try {
      const s = await supabase.auth.getSession();
      if (!s.data.session) throw Error('Entre novamente para confirmar a exclusão.');
      const r = await fetch('https://app.vinhaigrejas.com.br/api/account/close', {
        method: 'POST',
        headers: {'Content-Type': 'application/json', Authorization: 'Bearer ' + s.data.session.access_token},
        body: JSON.stringify({confirm: 'EXCLUIR', via: 'app'}),
      });
      const d = (await r.json().catch(() => ({}))) as {ok?: boolean; error?: string};
      if (!r.ok || !d.ok) throw Error(d.error || 'Não foi possível excluir agora.');
      await supabase.auth.signOut({scope: 'local'}).catch(() => undefined);
      onDeleted();
    } catch (e) {
      setNotice(e instanceof Error ? e.message : 'Falha de conexão.');
    } finally {
      setBusy(false);
    }
  }
  if (!open)
    return (
      <Pressable accessibilityRole="button" onPress={() => setOpen(true)} style={s.link}>
        <Text style={[s.linkText, {color: palette.muted}]}>Excluir minha conta</Text>
      </Pressable>
    );
  return (
    <View style={[s.card, {backgroundColor: palette.surface, borderColor: palette.line}]}>
      <Text accessibilityRole="header" style={[s.title, {color: palette.text}]}>
        Excluir minha conta
      </Text>
      <Text style={[s.copy, {color: palette.muted}]}>
        Seu login, seu e-mail neste aplicativo e os avisos no celular serão removidos, e você perderá o acesso a tickets e
        pedidos pela conta. Registros que a igreja precisa guardar por lei (contribuições, presença Kids e histórico) ficam
        com a igreja. Para pedir a remoção desses dados, fale com a secretaria.
      </Text>
      <Text style={[s.copy, {color: palette.text}]}>Digite EXCLUIR para confirmar.</Text>
      <TextInput
        accessibilityLabel="Digite EXCLUIR para confirmar"
        autoCapitalize="characters"
        autoCorrect={false}
        value={confirm}
        onChangeText={setConfirm}
        editable={!busy}
        style={[s.input, {color: palette.text, borderColor: palette.line}]}
      />
      {!!notice && (
        <Text accessibilityLiveRegion="polite" style={[s.copy, {color: '#b42318'}]}>
          {notice}
        </Text>
      )}
      <View style={s.row}>
        <Pressable accessibilityRole="button" disabled={busy} onPress={() => (setOpen(false), setConfirm(''), setNotice(''))} style={[s.button, {borderColor: palette.line}]}>
          <Text style={{color: palette.text, fontWeight: '600'}}>Cancelar</Text>
        </Pressable>
        <Pressable
          accessibilityRole="button"
          accessibilityState={{disabled: busy || confirm.trim().toUpperCase() !== 'EXCLUIR'}}
          disabled={busy || confirm.trim().toUpperCase() !== 'EXCLUIR'}
          onPress={() => void remove()}
          style={[s.button, s.danger, {opacity: busy || confirm.trim().toUpperCase() !== 'EXCLUIR' ? 0.5 : 1}]}
        >
          {busy ? <ActivityIndicator color="#fff" /> : <Text style={{color: '#fff', fontWeight: '700'}}>Excluir conta</Text>}
        </Pressable>
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  link: {alignSelf: 'center', paddingVertical: 14, paddingHorizontal: 8},
  linkText: {fontSize: 14, textDecorationLine: 'underline'},
  card: {borderWidth: 1, borderRadius: 18, padding: 18, marginTop: 12, gap: 10},
  title: {fontSize: 18, fontWeight: '700'},
  copy: {fontSize: 14, lineHeight: 20},
  input: {borderWidth: 1, borderRadius: 10, minHeight: 46, paddingHorizontal: 12, fontSize: 16, letterSpacing: 2},
  row: {flexDirection: 'row', gap: 10, marginTop: 4},
  button: {flex: 1, minHeight: 46, borderRadius: 10, borderWidth: 1, alignItems: 'center', justifyContent: 'center'},
  danger: {backgroundColor: '#b42318', borderColor: '#b42318'},
});
