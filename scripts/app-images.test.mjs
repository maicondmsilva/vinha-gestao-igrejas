import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {appImage,watchLink} from '../shared/app-images.ts';
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8');
const id='0b6c5a2e-1d3f-4a5b-8c7d-9e0f1a2b3c4d';
test('imagens da plataforma e HTTPS viram endereço completo; o resto é recusado',()=>{
 assert.equal(appImage('/api/event-images/'+id),'https://app.vinhaigrejas.com.br/api/event-images/'+id);
 assert.equal(appImage('/api/publishing-images/'+id),'https://app.vinhaigrejas.com.br/api/publishing-images/'+id);
 assert.equal(appImage('https://cdn.exemplo.com/capa.jpg'),'https://cdn.exemplo.com/capa.jpg');
 for(const v of ['','http://x.com/a.jpg','/api/outra-coisa/'+id,'javascript:alert(1)','https://user:pw@x.com/a.jpg',null,undefined])assert.equal(appImage(v),null,String(v));
});
test('link para abrir o vídeo no YouTube ou Vimeo',()=>{
 assert.equal(watchLink('https://www.youtube.com/watch?v=abcDEF12345'),'https://www.youtube.com/watch?v=abcDEF12345');
 assert.equal(watchLink('https://youtu.be/abcDEF12345?t=10'),'https://youtu.be/abcDEF12345');
 assert.equal(watchLink('https://www.youtube.com/live/abcDEF12345'),'https://www.youtube.com/watch?v=abcDEF12345');
 assert.equal(watchLink('https://vimeo.com/123456789'),'https://vimeo.com/123456789');
 assert.equal(watchLink('http://youtube.com/watch?v=x'),null);
});
test('telas do app usam imagens, vídeo no app, QR e configurações',()=>{
 const home=read('android-app/src/HomeScreen.tsx');for(const t of ['Minha agenda','Para sua edificação','Fique por dentro','Meus tickets','pagingEnabled'])assert.ok(home.includes(t),t);
 const player=read('android-app/src/NativeMediaPlayer.tsx');assert.match(player,/Compartilhar/);assert.match(player,/Abrir no/);assert.match(player,/autoplay=1/);
 assert.ok(!read('android-app/src/MemberExperience.tsx').includes('Links abrem fora do aplicativo'));
 const agenda=read('android-app/src/AgendaScreens.tsx');assert.match(agenda,/<QrCode value=\{ticket\.code\}/);assert.match(agenda,/<Cover uri=\{e\.cover\}/);
 assert.match(read('android-app/src/ServicesScreen.tsx'),/<QrCode value=\{c\.code\}/);
 assert.match(read('android-app/src/MemberExperience.tsx'),/Política de privacidade/);
 assert.match(read('app/privacidade/page.tsx'),/Lei 13\.709\/2018/);assert.match(read('app/termos/page.tsx'),/Termos de uso/);
 assert.match(read('android-app/package.json'),/qrcode-generator/);
});
