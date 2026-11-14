import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {episodeMedia, nextEpisode} from '../shared/series.ts';
import {publicationSource, publishingKinds, publicationLabels} from '../shared/publishing.ts';
import {publishingCommand} from '../app/lib/publishing-command.ts';
const read = (p) => readFileSync(new URL('../' + p, import.meta.url), 'utf8');
const ep = (id) => ({
  id,
  title: 'Parte ' + id,
  description: '',
  source: 'https://www.youtube.com/watch?v=abcdefghijk',
  poster: '',
  episode: null,
  download_allowed: false,
  version: 1,
});
test('próxima parte da série', () => {
  const list = [ep('1'), ep('2'), ep('3')];
  assert.equal(nextEpisode(list, () => 0).id, '1', 'nada assistido começa pela primeira');
  assert.equal(nextEpisode(list, (id) => (id === '1' ? 120 : 0)).id, '2', 'continua depois da última iniciada');
  assert.equal(nextEpisode(list, (id) => (id === '3' ? 10 : 0)).id, '3', 'última iniciada fica como próxima');
  assert.equal(
    nextEpisode([], () => 0),
    null,
  );
  assert.equal(episodeMedia(ep('1'), 'u').kind, 'video');
});
test('série no painel: tipo novo, sem link', () => {
  assert.ok(publishingKinds.includes('series'));
  assert.equal(publicationLabels.series, 'Séries de mensagens');
  assert.equal(publicationSource('series', ''), '');
  assert.equal(publicationSource('series', 'https://x.test'), null);
  const id = '11111111-1111-4111-8111-111111111111';
  const ok = publishingCommand({
    unit: id,
    action: 'save',
    id,
    version: 0,
    data: {
      kind: 'series',
      title: 'Série',
      body: '',
      source: '',
      poster: '',
      category: '',
      channel: '',
      scope: 'local',
      targets: [id],
      group: '',
      groupVersion: 0,
      provider: '',
      starts: '',
      ends: '',
      download: false,
      share: true,
    },
  });
  assert.ok(ok, 'comando de série aceito');
});
test('identidade Vinha na série e rota de ordem dos episódios', () => {
  const ui = read('android-app/src/SeriesScreens.tsx'),
    route = read('app/api/publishing/series/route.ts'),
    sql = read('supabase/migrations/20261114120000_series_videos.sql');
  for (const t of ['SÉRIES DE MENSAGENS', 'A TRILHA DA SÉRIE', 'Começar pela parte 1', 'Continuar · parte ']) assert.ok(ui.includes(t), t);
  assert.match(route, /publishing_series_episodes/);
  assert.match(sql, /revoke all on function public\.publishing_series_episodes\(uuid,uuid,uuid,uuid\[\]\) from public,anon/);
});
test('oração e testemunhos com identidade Vinha',()=>{
 const ui=read('android-app/src/CommunityScreens.tsx');
 for(const t of ['Pelo que podemos orar?','1 · ÁREA DO PEDIDO','Podem me procurar','Só quero oração','MURAL','RESPOSTA DA EQUIPE'])assert.ok(ui.includes(t),t);
 assert.match(ui,/allowContact:!!contact/,'consentimento continua indo para o servidor');
});
