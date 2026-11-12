import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {semitones,transposeChord,transposeChart,chartLine,worshipCommand,worshipQuery,worshipFailure} from '../app/lib/worship.ts';

const unit='11111111-1111-4111-8111-111111111111',song='22222222-2222-4222-8222-222222222222',service='33333333-3333-4333-8333-333333333333';

test('transposição: semitons, acordes com baixo e grafia com bemóis',()=>{
 assert.equal(semitones('G','A'),2);assert.equal(semitones('A','G'),10);assert.equal(semitones('','A'),0);
 assert.equal(transposeChord('F#m7/C#',2),'G#m7/D#');
 assert.equal(transposeChord('G',3,true),'Bb');
 assert.equal(transposeChart('[G]Santo, [D/F#]santo [Em7]é','G','A'),'[A]Santo, [E/G#]santo [F#m7]é');
 assert.equal(transposeChart('[G]Santo','G','F'),'[F]Santo');
 assert.equal(transposeChart('[G]Santo','G','G'),'[G]Santo');
 assert.equal(transposeChart('[Intro] [G]Santo','G','A'),'[Intro] [A]Santo','marcação que não é acorde fica igual');
});

test('linha de cifra vira pares acorde + letra',()=>{
 assert.deepEqual(chartLine('Eu [G]te adoro [D]Senhor'),[{chord:'',text:'Eu '},{chord:'G',text:'te adoro '},{chord:'D',text:'Senhor'}]);
 assert.deepEqual(chartLine('Só letra'),[{chord:'',text:'Só letra'}]);
});

test('consulta aceita só filtros conhecidos',()=>{
 assert.equal(worshipQuery(new Request(`https://x/api/worship?unit=${unit}&kind=songs&search=santo`)).action,'list');
 assert.equal(worshipQuery(new Request(`https://x/api/worship?unit=${unit}&kind=setlist&service=${service}`)).data.service,service);
 assert.throws(()=>worshipQuery(new Request(`https://x/api/worship?unit=${unit}&org=${unit}`)));
 assert.throws(()=>worshipQuery(new Request(`https://x/api/worship?unit=${unit}&key=H`)));
});

test('música: campos validados e links só https',()=>{
 const base={id:song,version:0,title:'Santo',originalKey:'G',bpm:72,timeSignature:'4/4',tags:['adoração'],links:{video:'https://youtu.be/x'}};
 assert.equal(worshipCommand({unit,kind:'song',action:'save',data:base}).data.bpm,'72');
 assert.throws(()=>worshipCommand({unit,kind:'song',action:'save',data:{...base,originalKey:'H'}}),/Tom/);
 assert.throws(()=>worshipCommand({unit,kind:'song',action:'save',data:{...base,links:{video:'javascript:alert(1)'}}}),/https/);
 assert.throws(()=>worshipCommand({unit,kind:'song',action:'save',data:{...base,organization:unit}}));
 assert.throws(()=>worshipCommand({unit,kind:'song',action:'save',data:{...base,bpm:900}}),/BPM/);
});

test('repertório do culto: até 40 músicas, ids válidos',()=>{
 const ok=worshipCommand({unit,kind:'setlist',action:'save',data:{service,version:0,notes:'',items:[{song,key:'A'}]}});
 assert.equal(ok.fn,'worship_setlists');
 assert.throws(()=>worshipCommand({unit,kind:'setlist',action:'save',data:{service,version:0,items:Array(41).fill({song})}}));
 assert.throws(()=>worshipCommand({unit,kind:'setlist',action:'save',data:{service,version:0,items:[{song:'x'}]}}));
 assert.equal(worshipCommand({unit,kind:'setlist',action:'publish',data:{service,version:2}}).action,'publish');
});

test('erros do banco viram mensagens claras sem detalhes internos',()=>{
 assert.equal(worshipFailure('23503','song_in_use').status,400);
 assert.match(worshipFailure('40001','song_version_conflict').error,/alterada/);
 assert.doesNotMatch(worshipFailure('XX000','secret details').error,/secret/);
});

test('rota confere a igreja da sessão antes de chamar o banco',()=>{
 const src=readFileSync(new URL('../app/api/worship/route.ts',import.meta.url),'utf8');
 assert.match(src,/membership\.units\.some\(u=>u\.id===input\.unit\)/);
 assert.match(src,/p_org:auth\.access!\.membership\.organization_id/);
});
