import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {transposeChart,chartLine} from '../shared/worship-chart.ts';
import {musicianError,songLines} from '../shared/use-worship-musician.ts';
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8');

test('cifra no tom do dia e linhas com acorde sobre a letra',()=>{
 assert.equal(transposeChart('[C]Santo [G/B]santo','C','D'),'[D]Santo [A/C#]santo');
 assert.deepEqual(chartLine('[D]Santo, [A]santo'),[{chord:'D',text:'Santo, '},{chord:'A',text:'santo'}]);
 const lines=songLines({chart:'[C]Santo\nFiel',originalKey:'C',dayKey:'D'},true);
 assert.deepEqual(lines,[[{chord:'D',text:'Santo'}],[{chord:'',text:'Fiel'}]]);
 assert.deepEqual(songLines({chart:'[C]Santo [G]Deus',originalKey:'C',dayKey:'C'},false),[[{chord:'',text:'Santo Deus'}]],'modo só letra tira os acordes');
});

test('mensagens claras',()=>{
 assert.match(musicianError('42501'),/escalado/);
 assert.match(musicianError('XX000'),/Tente de novo/);
});

test('hook usa a função do banco e as telas usam o hook',()=>{
 assert.match(read('shared/use-worship-musician.ts'),/rpc\('worship_musician'/);
 const web=read('app/MemberWorshipMusician.tsx');
 assert.match(web,/useWorshipMusician/);assert.match(web,/Modo palco/);assert.match(web,/Confirmar presença no ensaio/);assert.match(web,/songLines/);
 assert.match(read('app/MemberVolunteerScales.tsx'),/<MemberWorshipMusician/);
 const droid=read('android-app/src/WorshipMusician.tsx');
 assert.match(droid,/useWorshipMusician/);assert.match(droid,/Modo palco/);assert.match(droid,/songLines/);
 assert.match(read('android-app/src/VolunteerScales.tsx'),/<WorshipMusician/);
 assert.match(read('app/lib/worship.ts'),/shared\/worship-chart/);
});
