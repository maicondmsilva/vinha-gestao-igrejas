import {useEffect,useState} from 'react';
import {ActivityIndicator,Pressable,ScrollView,StyleSheet,Text,TextInput,View,useWindowDimensions} from 'react-native';
import {useMemberCommunity} from '../../shared/use-member-community';
import {communityCategories,communityLabels,communityStatus,type CommunityItem,type CommunityKind} from '../../shared/member-community';
import type {ChurchRpc} from '../../shared/member-church';
import {onBrand} from './experience-model';
import Icon,{type IconName} from './Icon';
type Palette={bg:string;surface:string;text:string;muted:string;line:string;brand:string;accent?:string};
type Props={rpc:ChurchRpc;org:string;unit:string;authenticated:boolean;palette:Palette;onLogin:()=>void;initialKind:CommunityKind;active:boolean};
/** Ícone de cada área (identidade Vinha: o membro escolhe tocando no cartão, não numa lista). */
const areaIcon:Record<string,IconName>={'Espiritual':'prayer','Família':'cells','Saúde':'give','Trabalho':'calendar','Finanças':'ticket','Outros':'chat'};
const intro:Record<CommunityKind,{over:string;title:string;copy:string}>={
 prayers:{over:'ORAMOS COM VOCÊ',title:'Pelo que podemos orar?',copy:'Seu pedido é privado: só você e a equipe de oração desta igreja veem.'},
 testimonies:{over:'O QUE DEUS TEM FEITO',title:'Testemunhos da igreja',copy:'Histórias compartilhadas com autorização e aprovadas pela igreja.'},
 groups:{over:'SIRVA E PARTICIPE',title:'Ministérios e departamentos',copy:'Peça para participar e aguarde a resposta da liderança.'},
 notes:{over:'SÓ PARA VOCÊ',title:'Minhas anotações',copy:'Anotações privadas da sua conta. A administração não vê.'},
 archived:{over:'SÓ PARA VOCÊ',title:'Anotações arquivadas',copy:'Restaure quando quiser.'},
};
const statusTone=(s?:string)=>s==='published'||s==='approved'||s==='completed'?'ok':s==='rejected'||s==='cancelled'||s==='withdrawn'||s==='left'?'off':'wait';

export default function NativeCommunity({rpc,org,unit,authenticated,palette:p,onLogin,initialKind,active}:Props){
 const {width}=useWindowDimensions(),cols=width>=700?3:2,ac=p.accent||p.brand,onB=onBrand(p.brand);
 const [kind,setKind]=useState<CommunityKind>(initialKind),[offset,setOffset]=useState(0),[editing,setEditing]=useState<CommunityItem|null>(null),[title,setTitle]=useState(''),[body,setBody]=useState(''),[category,setCategory]=useState<string>(''),[contact,setContact]=useState<boolean|null>(null),[consent,setConsent]=useState(false),[showName,setShowName]=useState(false),[confirm,setConfirm]=useState(''),[query,setQuery]=useState(''),[filter,setFilter]=useState(''),[validation,setValidation]=useState('');
 const m=useMemberCommunity(rpc,org,unit,authenticated,kind,offset,active);
 function clear(){setEditing(null);setTitle('');setBody('');setCategory('');setConsent(false);setShowName(false);setContact(null);setConfirm('');setValidation('')}
 useEffect(()=>{setKind(initialKind);setOffset(0);clear()},[initialKind,unit,org,authenticated]);
 const change=(k:CommunityKind)=>{setKind(k);setOffset(0);setQuery('');setFilter('');clear()};
 const copy=(value:string,extra?:object)=><Text style={[s.copy,{color:p.muted},extra]}>{value}</Text>;
 const over=(t:string)=><Text style={[s.over,{color:ac}]}>{t}</Text>;
 const primary=(label:string,fn:()=>void,disabled=false)=><Pressable accessibilityRole="button" accessibilityState={{disabled}} disabled={disabled} onPress={fn} style={[s.primary,{backgroundColor:p.brand,opacity:disabled?.5:1}]}><Text style={{color:onB,fontSize:16,fontWeight:'800',textAlign:'center'}}>{label}</Text></Pressable>;
 const ghost=(label:string,fn:()=>void,disabled=false)=><Pressable accessibilityRole="button" accessibilityState={{disabled}} disabled={disabled} onPress={fn} style={[s.ghost,{borderColor:p.line,opacity:disabled?.5:1}]}><Text style={{color:p.text,fontWeight:'700',textAlign:'center'}}>{label}</Text></Pressable>;
 const input=(label:string,value:string,set:(v:string)=>void,max:number,multiline=false,placeholder='')=><TextInput accessibilityLabel={label} value={value} onChangeText={set} maxLength={max} multiline={multiline} placeholder={placeholder||label} placeholderTextColor={p.muted} textAlignVertical={multiline?'top':'center'} style={[s.input,{color:p.text,borderColor:p.line,backgroundColor:p.bg},multiline&&{minHeight:140}]}/>;
 const choice=(label:string,hint:string,on:boolean,press:()=>void)=><Pressable accessibilityRole="radio" accessibilityState={{checked:on}} onPress={press} style={[s.choice,{borderColor:on?ac:p.line,backgroundColor:on?ac+'1c':p.bg}]}><View style={[s.radio,{borderColor:on?ac:p.muted}]}>{on&&<View style={[s.radioDot,{backgroundColor:ac}]}/>}</View><View style={{flex:1}}><Text style={{color:p.text,fontWeight:'800'}}>{label}</Text><Text style={{color:p.muted,marginTop:2}}>{hint}</Text></View></Pressable>;
 const chip=(label:string,tone:'ok'|'wait'|'off')=><View style={[s.chip,{backgroundColor:tone==='ok'?ac+'26':tone==='off'?p.line:'transparent',borderColor:tone==='wait'?ac:'transparent'}]}><Text style={{color:tone==='off'?p.muted:ac,fontWeight:'800',fontSize:12}}>{label}</Text></View>;
 const action=(label:string,operation:string,row:CommunityItem)=>confirm===operation+row.id?<View style={[s.confirm,{borderColor:p.line}]}><Text style={{color:p.text,fontWeight:'700'}}>{label}?</Text><View style={{flexDirection:'row',gap:8,marginTop:8}}><Pressable accessibilityRole="button" disabled={m.busy} onPress={()=>void m.command(operation,row).then(ok=>{if(ok)setConfirm('')})} style={[s.small,{backgroundColor:p.brand}]}><Text style={{color:onB,fontWeight:'800'}}>Sim, confirmar</Text></Pressable><Pressable accessibilityRole="button" onPress={()=>setConfirm('')} style={[s.small,{borderWidth:1,borderColor:p.line}]}><Text style={{color:p.text,fontWeight:'700'}}>Não</Text></Pressable></View></View>:<Pressable accessibilityRole="button" disabled={m.busy} onPress={()=>setConfirm(operation+row.id)}><Text style={{color:ac,fontWeight:'800',marginTop:10}}>{label}</Text></Pressable>;

 async function save(){setValidation('');
  if(kind!=='notes'&&!category){setValidation(kind==='prayers'?'Escolha a área do pedido.':'Escolha a área do testemunho.');return}
  if((kind!=='prayers'&&title.trim().length<2)||body.trim().length<(kind==='notes'?1:10)){setValidation(kind==='prayers'?'Conte um pouco mais (pelo menos 10 letras).':'Preencha o título e o texto (pelo menos 10 letras).');return}
  if(kind==='prayers'&&contact===null){setValidation('Diga se a equipe pode procurar você.');return}
  if(kind==='testimonies'&&!consent){setValidation('Autorize a publicação para enviar seu testemunho.');return}
  const op=kind==='prayers'?'prayer.create':kind==='testimonies'?'testimony.create':editing?'note.edit':'note.create';
  const data=kind==='prayers'?{category,body,allowContact:!!contact}:kind==='testimonies'?{title,category,body,consent,showName}:{title,body};
  if(await m.command(op,editing||undefined,data))clear();
 }
 const own=m.own.filter(r=>[r.title,r.name,r.body,r.category].join(' ').toLocaleLowerCase('pt-BR').includes(query.toLocaleLowerCase('pt-BR')));
 const wall=m.directory.filter(r=>!filter||r.category===filter),cats=[...new Set(m.directory.map(r=>r.category).filter(Boolean))] as string[];
 const t=intro[kind];

 return <View>
  <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{gap:8,paddingBottom:14}}>{(['prayers','testimonies','groups','notes'] as CommunityKind[]).map(k=>{const on=kind===k||(k==='notes'&&kind==='archived');return <Pressable key={k} accessibilityRole="tab" accessibilityState={{selected:on}} onPress={()=>change(k)} style={[s.seg,{borderColor:on?ac:p.line,backgroundColor:on?ac:p.surface}]}><Text style={{color:on?onBrand(ac):p.text,fontWeight:'700'}}>{communityLabels[k]}</Text></Pressable>})}</ScrollView>

  <View style={[s.cover,{backgroundColor:p.brand}]}><View style={[s.blob,{backgroundColor:onB,opacity:.08}]}/><View style={[s.blob2,{backgroundColor:onB,opacity:.06}]}/>
   <Text style={[s.coverOver,{color:onB}]}>{t.over}</Text><Text style={[s.coverTitle,{color:onB}]}>{t.title}</Text><Text style={{color:onB,opacity:.88,marginTop:6,lineHeight:22}}>{t.copy}</Text></View>

  {!!m.notice&&<Text accessibilityRole="alert" style={[s.alert,{color:p.text,borderColor:p.line}]}>{m.notice}</Text>}
  {!!m.error&&<Text accessibilityRole="alert" style={[s.alert,{color:p.text,borderColor:ac}]}>{m.error}</Text>}
  {m.loading&&<ActivityIndicator color={ac} style={{marginVertical:10}}/>}
  {!unit&&kind!=='notes'&&kind!=='archived'&&copy('Escolha sua igreja local para enviar e acompanhar.')}
  {!authenticated&&<View style={[s.block,{backgroundColor:p.surface,borderColor:p.line}]}>{copy(kind==='testimonies'?'Entre na conta para compartilhar o que Deus fez na sua vida.':'Entre na conta para enviar e acompanhar seus pedidos.',{marginTop:0})}{primary('Entrar na conta',onLogin)}</View>}

  {authenticated&&(kind==='prayers'||kind==='testimonies')&&<View style={[s.block,{backgroundColor:p.surface,borderColor:p.line}]}>
   {over(kind==='prayers'?'1 · ÁREA DO PEDIDO':'1 · ÁREA')}
   <View style={s.grid}>{communityCategories.map(c=>{const on=category===c;return <Pressable key={c} accessibilityRole="radio" accessibilityState={{checked:on}} onPress={()=>setCategory(c)} style={[s.area,{width:cols===3?'31.5%':'48%',borderColor:on?ac:p.line,backgroundColor:on?ac:p.bg}]}><Icon name={areaIcon[c]||'chat'} color={on?onBrand(ac):ac} size={26}/><Text style={{color:on?onBrand(ac):p.text,fontWeight:'800',marginTop:6}}>{c}</Text></Pressable>})}</View>
   {over(kind==='prayers'?'2 · CONTE PARA NÓS':'2 · SUA HISTÓRIA')}
   {kind==='testimonies'&&input('Título',title,setTitle,160,false,'Um título curto, ex.: "Cura na família"')}
   {input(kind==='prayers'?'Motivo de oração':'Seu testemunho',body,setBody,4000,true,kind==='prayers'?'Escreva com suas palavras. Pelo menos 10 letras.':'Conte o que aconteceu. Pelo menos 10 letras.')}
   {over(kind==='prayers'?'3 · ACOMPANHAMENTO':'3 · PUBLICAÇÃO')}
   {kind==='prayers'?<>{choice('Podem me procurar','A equipe pode falar comigo pelo telefone do cadastro.',contact===true,()=>setContact(true))}{choice('Só quero oração','Ninguém vai me ligar sobre este pedido.',contact===false,()=>setContact(false))}</>
    :<>{choice('Autorizo publicar depois da aprovação','Sem isso o testemunho não é enviado.',consent,()=>setConsent(!consent))}{choice(showName?'Mostrar meu nome':'Publicar como "Membro da igreja"',showName?'Seu nome aparece junto ao testemunho.':'Toque para mostrar seu nome.',showName,()=>setShowName(!showName))}</>}
   {!!validation&&<Text accessibilityRole="alert" style={{color:ac,fontWeight:'700',marginTop:8}}>{validation}</Text>}
   {primary(kind==='prayers'?'Enviar pedido de oração':'Enviar testemunho',()=>void save(),m.busy||!unit)}
  </View>}

  {kind==='testimonies'&&<>{over('MURAL')}
   {cats.length>1&&<ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{gap:8,paddingBottom:10}}>{['',...cats].map(c=><Pressable key={c||'all'} accessibilityRole="button" accessibilityState={{selected:filter===c}} onPress={()=>setFilter(c)} style={[s.seg,{borderColor:filter===c?ac:p.line,backgroundColor:filter===c?ac+'22':p.surface}]}><Text style={{color:p.text,fontWeight:'700'}}>{c||'Todos'}</Text></Pressable>)}</ScrollView>}
   {wall.map(row=><View key={row.id} style={[s.quote,{backgroundColor:p.surface,borderColor:p.line}]}><Text style={{color:ac,fontSize:44,lineHeight:44,fontWeight:'900'}}>“</Text><Text style={{color:p.text,fontWeight:'900',fontSize:18,marginTop:-8}}>{row.title}</Text><Text style={{color:p.text,lineHeight:23,marginTop:6}}>{row.body}</Text><View style={{flexDirection:'row',alignItems:'center',gap:8,marginTop:12}}><Text style={{color:p.muted,fontWeight:'700',flex:1}}>— {row.author||'Membro da igreja'}</Text>{!!row.category&&chip(row.category,'ok')}</View></View>)}
   {!m.loading&&!wall.length&&copy('Ainda não há testemunhos publicados nesta igreja.')}</>}

  {kind==='groups'&&<>{over('DISPONÍVEIS NESTA IGREJA')}{m.directory.map(row=><View key={row.id} style={[s.block,{backgroundColor:p.surface,borderColor:p.line}]}><View style={{flexDirection:'row',alignItems:'center',gap:8}}><Text style={{color:p.text,fontWeight:'900',fontSize:17,flex:1}}>{row.name}</Text>{chip(row.kind==='department'?'Departamento':'Ministério','ok')}</View>{!!row.description&&copy(row.description)}{row.accepting?primary('Quero participar',()=>authenticated?void m.command('group.request',row):onLogin(),m.busy):copy('Sem novas participações no momento.')}</View>)}{!m.loading&&!m.directory.length&&copy('Nenhum ministério recebendo participantes agora.')}</>}

  {authenticated&&(kind==='notes'||kind==='archived')&&<>{kind==='notes'&&<View style={[s.block,{backgroundColor:p.surface,borderColor:p.line}]}>{over(editing?'EDITANDO ANOTAÇÃO':'NOVA ANOTAÇÃO')}{input('Título',title,setTitle,160)}{input('Anotação',body,setBody,12000,true,'Escreva o que quiser guardar.')}{!!validation&&<Text accessibilityRole="alert" style={{color:ac,fontWeight:'700'}}>{validation}</Text>}{primary(editing?'Salvar anotação':'Guardar anotação',()=>void save(),m.busy)}{editing&&ghost('Cancelar edição',clear)}</View>}
   {ghost(kind==='notes'?'Ver anotações arquivadas':'Voltar às anotações',()=>change(kind==='notes'?'archived':'notes'))}</>}

  {authenticated&&<>{over(kind==='groups'?'MINHAS PARTICIPAÇÕES':kind==='testimonies'?'MEUS ENVIOS':kind==='prayers'?'MEUS PEDIDOS':'GUARDADAS')}
   {m.own.length>4&&input('Pesquisar nos meus registros',query,setQuery,120)}
   {own.map(row=><View key={row.id} style={[s.block,{backgroundColor:p.surface,borderColor:p.line}]}>
    <View style={{flexDirection:'row',alignItems:'center',gap:10}}>{kind==='prayers'&&<View style={[s.icon,{backgroundColor:ac+'1f'}]}><Icon name={areaIcon[row.category||'']||'prayer'} color={ac} size={20}/></View>}<Text style={{color:p.text,fontWeight:'900',fontSize:16,flex:1}}>{row.title||row.name||row.category}</Text>{!!row.status&&chip(kind==='prayers'&&row.status==='pending'?'Recebido':communityStatus[row.status]||row.status,statusTone(row.status))}</View>
    {!!row.body&&<Text numberOfLines={kind==='notes'?6:4} style={{color:p.muted,lineHeight:22,marginTop:8}}>{row.body}</Text>}
    {!!row.reply&&<View style={[s.reply,{borderLeftColor:ac,backgroundColor:p.bg}]}><Text style={{color:ac,fontWeight:'800',fontSize:12}}>RESPOSTA DA EQUIPE</Text><Text style={{color:p.text,marginTop:4,lineHeight:21}}>{row.reply}</Text></View>}
    {!!row.reason&&<Text style={{color:p.muted,marginTop:6}}>Motivo: {row.reason}</Text>}
    {kind==='prayers'&&['pending','care'].includes(row.status||'')&&action('Cancelar pedido','prayer.cancel',row)}
    {kind==='testimonies'&&row.status!=='withdrawn'&&action('Retirar testemunho','testimony.withdraw',row)}
    {kind==='groups'&&['pending','approved'].includes(row.status||'')&&action('Encerrar participação','group.leave',row)}
    {kind==='notes'&&<View style={{flexDirection:'row',gap:18}}><Pressable accessibilityRole="button" onPress={()=>{setEditing(row);setTitle(row.title||'');setBody(row.body||'');setValidation('')}}><Text style={{color:ac,fontWeight:'800',marginTop:10}}>Editar</Text></Pressable>{action('Arquivar','note.archive',row)}</View>}
    {kind==='archived'&&<Pressable accessibilityRole="button" disabled={m.busy} onPress={()=>void m.command('note.restore',row)}><Text style={{color:ac,fontWeight:'800',marginTop:10}}>Restaurar</Text></Pressable>}
   </View>)}
   {!m.loading&&!m.own.length&&copy(kind==='prayers'?'Você ainda não enviou pedidos por aqui.':kind==='testimonies'?'Você ainda não compartilhou testemunhos.':kind==='groups'?'Você ainda não participa de nenhum ministério.':'Nada guardado ainda.')}</>}

  {(offset>0||m.more)&&<View style={{flexDirection:'row',gap:8}}><View style={{flex:1}}>{ghost('‹ Anteriores',()=>setOffset(n=>Math.max(0,n-20)),!offset||m.loading||m.busy)}</View><View style={{flex:1}}>{ghost('Mais ›',()=>setOffset(n=>n+20),!m.more||m.loading||m.busy)}</View></View>}
  {ghost('Atualizar',m.refresh,m.busy)}
 </View>;
}
const s=StyleSheet.create({
 seg:{borderWidth:1,borderRadius:22,paddingHorizontal:16,paddingVertical:10},
 cover:{borderRadius:24,padding:22,overflow:'hidden',marginBottom:14},blob:{position:'absolute',width:220,height:220,borderRadius:110,right:-80,top:-90},blob2:{position:'absolute',width:130,height:130,borderRadius:65,left:-50,bottom:-60},
 coverOver:{fontSize:11,fontWeight:'800',letterSpacing:2,opacity:.9},coverTitle:{fontSize:25,fontWeight:'900',marginTop:6},
 over:{fontSize:11,fontWeight:'800',letterSpacing:1.8,marginTop:10,marginBottom:10},
 copy:{fontSize:15,lineHeight:23,marginVertical:6},alert:{borderWidth:1,borderRadius:14,padding:12,marginBottom:12,lineHeight:21},
 block:{borderWidth:1,borderRadius:22,padding:16,marginBottom:14},
 grid:{flexDirection:'row',flexWrap:'wrap',gap:8},area:{borderWidth:1.5,borderRadius:18,paddingVertical:14,paddingHorizontal:12,minHeight:84},
 input:{borderWidth:1,borderRadius:14,padding:13,fontSize:16,marginBottom:10,minHeight:50},
 choice:{flexDirection:'row',alignItems:'center',gap:12,borderWidth:1.5,borderRadius:18,padding:14,marginBottom:8},radio:{width:22,height:22,borderRadius:11,borderWidth:2,alignItems:'center',justifyContent:'center'},radioDot:{width:10,height:10,borderRadius:5},
 primary:{borderRadius:16,paddingVertical:15,minHeight:52,justifyContent:'center',marginTop:12},ghost:{borderWidth:1,borderRadius:16,paddingVertical:13,minHeight:48,justifyContent:'center',marginTop:10},
 chip:{borderWidth:1,borderRadius:14,paddingHorizontal:10,paddingVertical:4},
 confirm:{borderWidth:1,borderRadius:14,padding:12,marginTop:10},small:{paddingHorizontal:14,paddingVertical:10,borderRadius:20},
 quote:{borderWidth:1,borderRadius:24,padding:18,marginBottom:12},
 reply:{borderLeftWidth:3,borderRadius:10,padding:10,marginTop:10},icon:{width:36,height:36,borderRadius:18,alignItems:'center',justifyContent:'center'},
});
