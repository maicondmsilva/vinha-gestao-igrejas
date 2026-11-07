'use client';
import MemberPublishingCatalog from './MemberPublishingCatalog';
import MemberMediaPortal from './MemberMediaPortal';
import MediaPlayer from './MediaPlayer';
import {mediaSource} from '../shared/ministry-media';
import MemberPaidEvents from './MemberPaidEvents';

import {useState} from 'react';
import MemberServicesPortal from './MemberServicesPortal';
import MemberFamilyPortal from './MemberFamilyPortal';
import MemberLearningPortal from './MemberLearningPortal';
import MemberCommunityPortal from './MemberCommunityPortal';
import type {CommunityKind} from '../shared/member-community';
import MemberAgendaPortal from './MemberAgendaPortal';
import {useMemberChurch} from '../shared/use-member-church';
import {churchStatus,publicLink,type ChurchRpc} from '../shared/member-church';
import type {AppConfig} from '../shared/member-profile';
import RichText from './RichText';
export default function MemberChurchChoice({rpc,config}:{rpc:ChurchRpc;config:AppConfig}){
 const [familyKind,setFamilyKind]=useState<'kids'|'cells'>('kids');
 const [communityKind,setCommunityKind]=useState<CommunityKind>('prayers');
 const c=useMemberChurch(rpc,config.id),name=(id:string|null)=>config.units.find(u=>u.id===id)?.name||'Não definida',pending=c.state?.transfers.find(t=>t.status==='pending');
 return <section aria-label="Igreja e conteúdo"><h2>Minha igreja local</h2><p>Conteúdos públicos acompanham sua escolha. O cadastro de membro só muda após aprovação.</p><label>Igreja para acompanhar<select value={c.selected} disabled={c.busy||!c.state} onChange={e=>void c.command('select',e.target.value)}><option value="" disabled>Selecione sua igreja</option>{config.units.map(u=><option key={u.id} value={u.id}>{u.name}{u.city?' · '+u.city:''}</option>)}</select></label><p>Vínculo oficial: <strong>{name(c.state?.officialUnit||null)}</strong></p>{c.notice&&<p role="status">{c.notice}</p>}{!pending&&c.state?.canRequest&&c.selected&&c.selected!==c.state.officialUnit&&<button type="button" disabled={c.busy} onClick={()=>void c.command('request',c.selected)}>Solicitar transferência para {name(c.selected)}</button>}{pending&&<p>Aguardando aprovação: {name(pending.source_unit)} → {name(pending.target_unit)}. <button type="button" disabled={c.busy} onClick={()=>void c.command('cancel',undefined,pending.id)}>Cancelar solicitação de transferência</button></p>}<button type="button" disabled={c.busy} onClick={c.refresh}>Atualizar situação da igreja</button><MemberPublishingCatalog rpc={rpc} org={config.id} unit={c.selected} kind="banner"/><h3>Conteúdos públicos · {name(c.selected)}</h3>{c.loading?<p>Carregando conteúdos…</p>:!c.posts.length?<p>Nenhum conteúdo público publicado para esta igreja.</p>:c.posts.map(p=><article key={p.id}><h4>{p.title}</h4>{p.kind==='notice'?<RichText body={p.body}/>:<p style={{whiteSpace:'pre-wrap'}}>{p.body}</p>}{p.kind==='video'&&mediaSource(p.url)?<MediaPlayer source={p.url} title={p.title}/>:publicLink(p.url)&&<a href={publicLink(p.url)!} target="_blank" rel="noopener noreferrer">Abrir conteúdo</a>}</article>)}<MemberMediaPortal key={config.id+':'+c.selected} rpc={rpc} org={config.id} unit={c.selected}/><MemberPaidEvents rpc={rpc} org={config.id} unit={c.selected}/><MemberServicesPortal rpc={rpc} org={config.id} unit={c.selected}/><MemberAgendaPortal rpc={rpc} org={config.id} unit={c.selected} onFamily={kind=>{setFamilyKind(kind);document.getElementById('member-family')?.scrollIntoView({behavior:'smooth'})}} onCommunity={kind=>{setCommunityKind(kind);document.getElementById('member-community')?.scrollIntoView({behavior:'smooth'})}}/><MemberCommunityPortal rpc={rpc} org={config.id} unit={c.selected} initialKind={communityKind}/><MemberLearningPortal rpc={rpc} org={config.id} unit={c.selected}/><MemberFamilyPortal rpc={rpc} org={config.id} unit={c.selected} initialKind={familyKind}/>{!!c.state?.transfers.length&&<details><summary>Histórico de transferências</summary>{c.state.transfers.map(t=><p key={t.id}>{name(t.source_unit)} → {name(t.target_unit)}: {churchStatus[t.status]} {t.reason}</p>)}</details>}</section>;
}
