'use client';
// Pessoas › ficha (PersonProfile) e cadastro completo (PersonModal). Carregados só quando abertos.
import {FormEvent,useEffect,useRef,useState,type ReactNode} from 'react';
import FamilyLinks from '../FamilyLinks';
import {PastoralHistory} from './PastoralCare';
import PersonRoles,{applyStaged,emptyStaged,type StagedRoles} from './PersonRoles';
import {useMinistryLanguage} from '../MinistryLanguage';
import PersonTimeline from '../PersonTimeline';
import PersonConsents from '../PersonConsents';
import PersonPhoto from '../PersonPhoto';
import PersonVisits from '../PersonVisits';
import MemberFiles from '../MemberFiles';
import useRegistrationFormatting from '../useRegistrationFormatting';
import {brazilStates,formatRegistrationField,genders,maritalStatuses} from '../../shared/brazil-registration';
import {memberFormPayload} from '../lib/member-write';
import type {ChurchUnit,Person} from './types';
import {brDate,personAgeLabel} from '../../shared/person-age';
import './person-forms.css';
import '../people-form.css';
import '../members.css';

export function PersonProfile({person,close,edit}:{person:Person,close:()=>void,edit:()=>void}){
 const child=person.status==='Criança',age=personAgeLabel(person.birthDate),plural=useMinistryLanguage().t('pessoas.cargos');
 const item=(label:string,value:string|undefined|null)=><span><small>{label}</small>{value?<b>{value}</b>:<b className="pp-empty">Não informado</b>}</span>;
 const digits=(person.phone||'').replace(/\D/g,''),wa=digits.length>=10?'https://wa.me/'+(digits.length<=11?'55':'')+digits:'';
 const group=person.group&&person.group!=='Sem grupo'?person.group:'';
 const address=[person.address,person.number,person.district,person.city,person.state].filter(Boolean).join(', ');
 const go=(id:string)=>document.getElementById('pp-'+id)?.scrollIntoView({behavior:'smooth',block:'start'});
 const sec=(id:string,icon:string,title:string,body:ReactNode,extra='')=><section id={'pp-'+id} className={'pp-sec '+extra}><h3><i aria-hidden="true">{icon}</i>{title}</h3>{body}</section>;
 return <div className="overlay profile-overlay" onMouseDown={e=>e.target===e.currentTarget&&close()}><aside className="person-profile pp pp2" aria-label={'Ficha de '+person.name}>
  <div className="profile-head pp-hero"><button className="pp-close" onClick={close} aria-label="Fechar ficha">×</button>
   <span className={'pa pp-avatar'+(child?' pa-kid':'')} title={child?'Cadastro de criança':undefined}><PersonPhoto id={person.id} initials={person.initials} name={person.name}/>{child&&<b className="pa-badge" aria-label="Criança">K</b>}</span>
   <div className="pp-who">
    <p className="pp-id">{child&&<span className="pd-kid-tag">Kids</span>}{person.code?'Nº '+person.code:'Sem número'}</p>
    <h2>{person.name}</h2>
    <p className="pp-chips"><em className="pp-status">{person.status}</em>{age&&<em>{age}</em>}{group&&<em>{group}</em>}</p>
   </div>
   <div className="pp-actions">
    <button className="create" onClick={edit}>✎ Editar cadastro</button>
    {wa&&<a href={wa} target="_blank" rel="noreferrer" aria-label="Conversar no WhatsApp">WhatsApp</a>}
    {person.email&&<a href={'mailto:'+person.email} aria-label="Enviar e-mail">E-mail</a>}
   </div>
  </div>
  <div className="pp-facts">
   <span><small>Idade</small><b>{age||'—'}</b></span>
   <span><small>Etapa</small><b>{person.status||'—'}</b></span>
   <span><small>Na igreja desde</small><b>{person.since||'—'}</b></span>
   <span><small>{child?'Sala / grupo':'Grupo'}</small><b>{group||'—'}</b></span>
  </div>
  <nav className="pp-nav" aria-label="Seções da ficha">{([['contato','Contato'],['pessoais','Dados'],['funcoes',plural],['familia','Família'],['igreja','Vida na igreja'],['atendimento','Atendimento'],['docs','Termos e arquivos'],['historico','Histórico']] as [string,string][]).map(([id,l])=><button key={id} type="button" onClick={()=>go(id)}>{l}</button>)}</nav>
  <div className="profile-body pp-body">
   <div className="pp-cols">
    {sec('contato','☎','Contato',<div className="profile-grid">{item('E-mail',person.email)}{item('Telefone',person.phone)}</div>)}
    {sec('pessoais','◉','Dados pessoais',<div className="profile-grid">{item('Nascimento',person.birthDate?brDate(person.birthDate)+(age?' · '+age:''):'')}{item('CPF',person.cpf)}{item('Estado civil',person.maritalStatus)}{item('Unidade',person.campus)}</div>)}
   </div>
   {person.id&&sec('funcoes','★',plural+' e funções',<PersonRoles person={person.id} editable/>)}
   {person.id&&sec('familia','♡','Família',<FamilyLinks person={person.id}/>)}
   {sec('igreja','✦','Vida na igreja',<><div className="profile-grid">{item('Etapa',person.status)}{item('Batizado',person.baptized)}{item('Grupo / ministério',group)}{item('Desde',person.since)}{person.convertedAt&&item('Decisão por Jesus',brDate(person.convertedAt))}</div>{person.tags&&<p className="profile-tags">{person.tags.split(',').map(tag=><em key={tag}>{tag.trim()}</em>)}</p>}</>)}
   {sec('endereco','⌂','Endereço e emergência',<div className="profile-grid">{item('Endereço',address)}{item('Contato de emergência',person.emergencyName?(person.emergencyName+(person.emergencyPhone?' · '+person.emergencyPhone:'')):'')}</div>)}
   {person.notes&&sec('pastoral','🔒','Observação pastoral',<p>{person.notes}</p>,'pastoral')}
   {person.id&&sec('atendimento','✚','Histórico de atendimento',<PastoralHistory person={person.id} personName={person.name} unit={person.campusId||(typeof window==='undefined'?'':new URLSearchParams(location.search).get('unidade')||'')}/>)}
   <div id="pp-docs" className="pp-docs"><PersonConsents personId={person.id||''}/><PersonVisits personId={person.id||''}/><MemberFiles personId={person.id||''}/></div>
   {person.id&&sec('historico','↺','Histórico',<PersonTimeline person={person.id}/>)}
  </div></aside></div>;
}

export function PersonModal({initial,close,save,units,unitId,canPastoral}:{initial:Person|null,close:()=>void,save:(p:Person,after?:(id:string)=>Promise<void>)=>Promise<void>,units:ChurchUnit[],unitId:string,canPastoral:boolean}){
 const [step,setStep]=useState(1); const [staged,setStaged]=useState<StagedRoles>(emptyStaged); const plural=useMinistryLanguage().t('pessoas.cargos'); const [birthAge,setBirthAge]=useState(()=>personAgeLabel(initial?.birthDate)); const [saving,setSaving]=useState(false); const [error,setError]=useState(''); const [draft,setDraft]=useState<Record<string,unknown>>(()=>({...initial,notes:'',campus:initial?.campusId||initial?.campus||unitId})); const formRef=useRef<HTMLFormElement>(null);const [changedConsents,setChangedConsents]=useState<string[]>([]);
 useEffect(()=>{if(!formRef.current)return;Object.entries(draft).forEach(([key,value])=>{const field=formRef.current?.elements.namedItem(key);if(field instanceof HTMLInputElement&&field.type==='checkbox')field.checked=Boolean(value);else if(field&&'value' in field){const formatted=formatRegistrationField(key,String(value??''));if(field instanceof HTMLSelectElement&&formatted&&!Array.from(field.options).some(option=>option.value===formatted)){const option=document.createElement('option');option.value=formatted;option.textContent=formatted+' (cadastro anterior)';field.appendChild(option)}(field as unknown as HTMLInputElement).value=formatted}})},[step,units]);
 const registration=useRegistrationFormatting(formRef,step);
 function collect(){const data=new FormData(formRef.current!);const next={...draft};data.forEach((value,key)=>next[key]=String(value));['privacy','imageConsent','messages'].forEach(key=>{const field=formRef.current?.elements.namedItem(key) as unknown as HTMLInputElement|null;if(field)next[key]=field.checked});setDraft(next);return next}
 function goToStep(next:number){collect();if(next>step&&!formRef.current?.reportValidity())return;setError('');setStep(next)}
 function advance(event:{preventDefault:()=>void}){event.preventDefault();goToStep(step+1)}
 async function submit(e:FormEvent<HTMLFormElement>){e.preventDefault();if(step!==4&&!initial){setError('Revise as etapas antes de concluir.');return}if(!formRef.current?.reportValidity())return;const all=collect();if(String(all.name||'').trim().length<2){setError('Informe o nome completo.');return}if(!units.some(u=>u.id===all.campus)){setError('Selecione uma unidade autorizada.');return}setSaving(true);setError('');try{await save(memberFormPayload(all,initial,changedConsents) as unknown as Person,!initial&&(staged.positions.length||staged.groups.length)?id=>applyStaged(id,staged):undefined)}catch(error){setError(error instanceof Error?error.message:'Não foi possível salvar agora.');setSaving(false)}}
 return <div className="overlay" onMouseDown={e=>e.target===e.currentTarget&&close()}><form ref={formRef} className="modal member-modal pf" onSubmit={submit} onInput={registration.onInput}>
  <div className="modal-head"><div><p className="section-over">{initial?'EDITAR CADASTRO':'CADASTRO COMPLETO'}</p><h2>{initial?'Editar pessoa':'Adicionar à comunidade'}</h2></div><button type="button" onClick={close}>×</button></div>
  <div className="stepper pf-tabs" role="tablist" aria-label="Etapas do cadastro">{['Dados pessoais','Família e endereço','Vida na igreja','Privacidade'].map((s,i)=><button type="button" role="tab" aria-selected={step===i+1} key={s} className={step===i+1?'on':step>i+1?'done':''} onClick={()=>goToStep(i+1)}><i>{step>i+1?'✓':i+1}</i><span>{s}</span></button>)}</div>
  <div className="step-content">
   {step===1&&<><h3>Dados pessoais</h3><div className="photo-field"><i>＋</i><span><b>Foto de perfil</b><small>JPG ou PNG · até 5 MB</small></span><button type="button" disabled>Foto em preparação</button></div><label>Nome completo<input name="name" required placeholder="Ex.: João da Silva"/></label><div className="form-row"><label><span>Data de nascimento{birthAge&&<em className="pf-age"> · {birthAge}</em>}</span><input name="birthDate" type="date" onChange={e=>setBirthAge(personAgeLabel(e.target.value))}/></label><label>Sexo<select name="gender"><option value="">Selecione</option>{genders.map(value=><option key={value}>{value}</option>)}</select></label></div><div className="form-row"><label>Estado civil<select name="maritalStatus"><option value="">Selecione</option>{maritalStatuses.map(value=><option key={value}>{value}</option>)}</select></label><label>CPF<input name="cpf" inputMode="numeric" maxLength={14} placeholder="000.000.000-00"/></label></div><div className="form-row"><label>E-mail<input type="email" name="email" required placeholder="joao@email.com"/></label><label>Telefone<input name="phone" type="tel" maxLength={20} required placeholder="(11) 99999-9999"/></label></div></>}
   {step===2&&<><h3>Família e endereço</h3><div className="pf-family">{initial?.id?<FamilyLinks person={initial.id} editable/>:<p>Salve o cadastro para adicionar familiares.</p>}</div><h3>Endereço</h3><div className="form-row"><label>CEP<input name="zip" inputMode="numeric" maxLength={9} placeholder="00000-000"/></label><label>Estado<select name="state"><option value="">Selecione a UF</option>{brazilStates.map(([uf,name])=><option key={uf} value={uf}>{uf} — {name}</option>)}</select></label></div>{registration.postalNotice&&<p role="status">{registration.postalNotice}</p>}<label>Endereço<input name="address" placeholder="Rua, avenida..."/></label><div className="form-row three"><label>Número<input name="number"/></label><label>Complemento<input name="extra"/></label><label>Bairro<input name="district"/></label></div><label>Cidade<input name="city"/></label><h3>Contato de emergência</h3><div className="form-row"><label>Nome<input name="emergencyName"/></label><label>Telefone<input name="emergencyPhone" type="tel" maxLength={20} placeholder="(11) 99999-9999"/></label></div></>}
   {step===3&&<><h3>Jornada e vida na igreja</h3><div className="form-row"><label>Etapa da jornada<select name="status"><option>Membro</option><option>Em integração</option><option>Criança</option><option>Frequentador</option><option>Visitante</option><option>Afastado</option><option>Transferido</option></select></label><label>Unidade<select name="campus" required><option value="">Selecione a unidade</option>{units.map(u=><option value={u.id} key={u.id}>{u.name}</option>)}</select></label></div><div className="form-row"><label>Data da primeira visita<input type="date" name="firstVisit"/></label><label>Data de entrada<input type="date" name="joined"/></label></div><div className="form-row"><label>Batizado?<select name="baptized"><option>Não informado</option><option>Sim</option><option>Não</option></select></label><label>Data do batismo<input type="date" name="baptismDate"/></label></div><div className="pf-roles"><h3>{plural} e funções</h3><PersonRoles person={initial?.id} editable staged={staged} onStaged={setStaged}/></div><label>Tags<input name="tags" placeholder="Ex.: músico, líder, novo convertido"/></label>{canPastoral&&<label>Novo registro pastoral<textarea name="notes" placeholder="Acrescenta uma nota; o histórico anterior é preservado."/></label>}</>}
   {step===4&&<><h3>Consentimentos e acesso</h3><p>Registro administrativo: não substitui o aceite do titular no aplicativo. Na edição, apenas alterações explícitas nestas opções geram registros.</p><div className="privacy-card" onChange={event=>{const field=event.target;if(field instanceof HTMLInputElement)setChangedConsents(current=>current.includes(field.name)?current:[...current,field.name])}}><label><input type="checkbox" name="privacy"/><span><b>Tratamento de dados pessoais</b><small>Registrar o estado informado para tratamento de dados.</small></span></label><label><input type="checkbox" name="imageConsent"/><span><b>Uso de imagem</b><small>Permite uso de fotos e vídeos em comunicações da igreja.</small></span></label><label><input type="checkbox" name="messages"/><span><b>Comunicações</b><small>Autoriza receber e-mails, mensagens e notificações.</small></span></label></div><p>Salvar o cadastro não cria conta nem envia convite ao aplicativo. Campos personalizados ainda estão em preparação.</p><div className="review-box"><i>✓</i><div><b>Cadastro pronto para revisão</b><small>Você poderá editar todas as informações depois.</small></div></div></>}
  </div>
  {error&&<p className="form-error">{error}</p>}<div className="modal-actions"><button type="button" onClick={step===1?close:()=>goToStep(step-1)}>{step===1?'Cancelar':'Voltar'}</button>{step<4&&initial&&<button key="member-save-now" type="submit" className="pf-save-now" disabled={saving||!units.length}>{saving?'Salvando...':'Salvar alterações'}</button>}{step<4?<button key="member-continue" type="button" className="create" onClick={advance}>Continuar</button>:<button key="member-save" type="submit" className="create" disabled={saving||!units.length}>{saving?'Salvando...':initial?'Salvar alterações':'Concluir cadastro'}</button>}</div>
 </form></div>
}
