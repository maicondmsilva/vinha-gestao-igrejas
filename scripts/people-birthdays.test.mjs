import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {birthdaysQuery,whatsappLink,birthdayMessage,dayLabel} from '../app/lib/birthdays.ts';
const u='b0000000-0000-4000-8000-000000000001';
const read=p=>readFileSync(new URL('../'+p,import.meta.url),'utf8');
test('consulta exige igreja e período válido',()=>{
 assert.deepEqual(birthdaysQuery(new Request(`https://v.test/api/people/birthdays?unit=${u}&range=week`)),{unit:u,range:'week'});
 assert.throws(()=>birthdaysQuery(new Request(`https://v.test/api/people/birthdays?unit=${u}&range=year`)));
 assert.throws(()=>birthdaysQuery(new Request('https://v.test/api/people/birthdays?unit=x&range=today')));
});
test('mensagem e link do WhatsApp',()=>{
 assert.equal(birthdayMessage({name:'Ana Paula Souza',kind:'birthday',years:30},'Igreja Vinha'),'Feliz aniversário, Ana! A Igreja Vinha celebra a sua vida e ora por você. Deus abençoe seus 30 anos!');
 assert.match(birthdayMessage({name:'Gil Casado',kind:'wedding',years:10},'Igreja Vinha'),/10 anos de casamento/);
 assert.equal(whatsappLink('(11) 98888-7777','Oi'),'https://wa.me/5511988887777?text=Oi');
 assert.equal(whatsappLink('+55 11 98888-7777','Oi'),'https://wa.me/5511988887777?text=Oi');
 assert.equal(whatsappLink('123','Oi'),null);
 assert.equal(whatsappLink(null,'Oi'),null);
});
test('dia em português',()=>{assert.equal(dayLabel('2026-11-13','2026-11-13'),'Hoje');assert.equal(dayLabel('2026-11-14','2026-11-13'),'Amanhã');assert.match(dayLabel('2026-11-20','2026-11-13'),/20\/11/)});
test('rota usa a igreja da sessão e a lista mostra os aniversariantes',()=>{
 const r=read('app/api/people/birthdays/route.ts');assert.match(r,/p_org:auth\.access!\.membership\.organization_id/);assert.match(r,/people_birthdays/);
 assert.match(read('app/PeopleDirectory.tsx'),/<PeopleBirthdays/);
 const ui=read('app/PeopleBirthdays.tsx');assert.match(ui,/Aniversariantes/);assert.match(ui,/Mandar mensagem/);
});
