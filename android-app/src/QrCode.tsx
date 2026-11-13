import {useMemo} from 'react';
import {View} from 'react-native';
import qrcode from 'qrcode-generator';

/** QR Code desenhado com Views (sem módulo nativo). Fundo branco e margem para a leitura funcionar no tema escuro. */
export default function QrCode({value, size = 220}: {value: string; size?: number}) {
  const rows = useMemo(() => {
    const qr = qrcode(0, 'M');
    qr.addData(value);
    qr.make();
    const n = qr.getModuleCount();
    const out: {start: number; length: number}[][] = [];
    for (let r = 0; r < n; r++) {
      const runs: {start: number; length: number}[] = [];
      let c = 0;
      while (c < n) {
        if (!qr.isDark(r, c)) {
          c++;
          continue;
        }
        const start = c;
        while (c < n && qr.isDark(r, c)) c++;
        runs.push({start, length: c - start});
      }
      out.push(runs);
    }
    return {n, out};
  }, [value]);
  const quiet = 4,
    cell = size / (rows.n + quiet * 2);
  return (
    <View accessibilityRole="image" accessibilityLabel="QR Code" style={{width: size, height: size, backgroundColor: '#ffffff', padding: cell * quiet, borderRadius: 12}}>
      {rows.out.map((runs, r) => (
        <View key={r} style={{height: cell, flexDirection: 'row'}}>
          {runs.map((run) => (
            <View key={run.start} style={{position: 'absolute', left: run.start * cell, width: run.length * cell + 0.5, height: cell + 0.5, backgroundColor: '#000000'}} />
          ))}
        </View>
      ))}
    </View>
  );
}
