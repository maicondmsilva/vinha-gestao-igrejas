import test from 'node:test';import assert from 'node:assert/strict';
import {eventPublicationIssues} from '../shared/event-publication.ts';
import {emptyEventInfo} from '../shared/event-info.ts';
const now=Date.parse('2026-11-04T12:00:00Z'),event={starts_at:'2026-11-05T12:00:00Z',status:'draft'};
test('publicacao presencial aponta campos incompletos e aceita endereco completo',()=>{const info=emptyEventInfo();assert.match(eventPublicationIssues(event,info,now).join(' '),/rua, número, cidade e estado/);info.venue={...info.venue,street:'Rua fictícia',number:'S/N',city:'Cidade fictícia',state:'SP'};assert.deepEqual(eventPublicationIssues(event,info,now),[])});
test('online exige link e hibrido exige tambem local',()=>{const info=emptyEventInfo();info.venue.format='online';assert.match(eventPublicationIssues(event,info,now).join(' '),/link/);info.venue.onlineUrl='https://example.com';assert.deepEqual(eventPublicationIssues(event,info,now),[]);info.venue.format='hybrid';assert.match(eventPublicationIssues(event,info,now).join(' '),/rua/)});
test('inicio vencido e cancelamento nao permitem publicacao',()=>{assert.match(eventPublicationIssues({...event,starts_at:'2026-11-04T11:59:00Z'},null,now)[0],/futuros/);assert.match(eventPublicationIssues({...event,status:'cancelled'},null,now)[0],/cancelado/)});
test('evento legado nao ganha obrigacoes de local que nao possuia',()=>{assert.deepEqual(eventPublicationIssues(event,null,now),[])});
test('link inseguro ou reservado recebe orientacao antes de publicar',()=>{const info=emptyEventInfo();info.venue.format='online';for(const url of ['http://example.com','https://example.invalid','javascript:alert(1)']){info.venue.onlineUrl=url;assert.match(eventPublicationIssues(event,info,now).join(' '),/HTTPS válido/)} });
