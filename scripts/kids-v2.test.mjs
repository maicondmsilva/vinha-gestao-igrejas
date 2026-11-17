import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read = (p) => readFileSync(new URL('../' + p, import.meta.url), 'utf8');

test('fotos das crianças em lote: uma chamada para vários cartões e cache', async () => {
  const {kidsPhotoBatcher} = await import('../shared/kids-photo-batch.ts');
  const calls = [];
  const photo = kidsPhotoBatcher(async (unit, profiles) => {
    calls.push([unit, profiles]);
    return Object.fromEntries(profiles.filter((p) => p !== 'c').map((p) => [p, 'https://x/' + p]));
  });
  const got = await Promise.all(['a', 'b', 'c', 'a'].map((p) => photo('u', p)));
  assert.deepEqual(got, ['https://x/a', 'https://x/b', '', 'https://x/a']);
  assert.equal(calls.length, 1, 'uma chamada só');
  assert.deepEqual(calls[0][1].sort(), ['a', 'b', 'c']);
  assert.equal(await photo('u', 'b'), 'https://x/b');
  assert.equal(calls.length, 1, 'segunda leitura vem do cache');
  assert.match(read('app/api/kids/photo/route.ts'), /createSignedUrls\(/);
  assert.match(read('app/KidsChildPhoto.tsx'), /kidsPhotoBatcher/);
  assert.match(read('staff-app/src/KidsChildPhoto.tsx'), /kidsPhotoBatcher/);
});

test('painel Kids: abas sob demanda, telão em Configurar e ausências em Relatórios', async () => {
  const {kidsSections, kidsSectionOf} = await import('../shared/dashboard-menu.ts');
  assert.equal(kidsSectionOf('stations'), 'plan');
  assert.equal(kidsSectionOf('absent'), 'reports');
  assert.ok(!kidsSections.find(([id]) => id === 'today')[2].includes('stations'));
  const ui = read('app/KidsOperations.tsx') + read('app/kids/KidsTabs.tsx');
  for (const c of ['KidsSetupPanel', 'KidsProjector', 'KidsStations', 'KidsDesk', 'MemberFamilyAdmin']) assert.match(ui, new RegExp('const ' + c + '=lazy\\('));
  assert.doesNotMatch(ui, /^import KidsSetupPanel/m);
  assert.match(ui, /<KidsProjectorStatus/);
  assert.match(ui, /<KidsBirthdays/);
  assert.match(read('app/api/kids-operations/route.ts'), /zoneRequest/);
  assert.match(read('app/KidsSetupPanel.tsx'), /isKidsSetup\(d\)/);
  assert.doesNotMatch(read('app/KidsDesk.tsx'), /Até \(exclusivo\)/);
});

test('avisos à família, totem e pausa em segundo plano', () => {
  const sql = read('supabase/migrations/20261117170000_kids_avisos_familia.sql');
  assert.match(sql, /create trigger kids_family_notice after insert or update of status on private\.kids_attendance/);
  assert.match(sql, /not g\.temporary/);
  assert.doesNotMatch(sql.split('kids_family_notice()')[1].split('$$')[1], /kids_care/, 'aviso não lê dados de saúde');
  assert.match(read('android-app/src/push-routing.ts'), /case 'kids':/);
  const kiosk = read('staff-app/src/KidsKiosk.tsx');
  assert.match(kiosk, /'checkin'/);
  assert.doesNotMatch(kiosk, /'checkout'/, 'totem nunca faz retirada');
  assert.match(kiosk, /delayLongPress=\{2000\}/);
  assert.match(read('staff-app/src/KidsBoard.tsx'), /AppState\.addEventListener/);
});
