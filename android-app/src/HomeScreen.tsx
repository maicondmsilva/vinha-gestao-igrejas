import {useState,type ReactNode} from 'react';
import {ActivityIndicator,Image,Pressable,ScrollView,StyleSheet,Text,useWindowDimensions,View} from 'react-native';
import {appImage} from '../../shared/app-images';
import type {AgendaEvent} from '../../shared/member-agenda';
import type {PublicPost,ChurchRpc} from '../../shared/member-church';
import {useMinistryMedia} from '../../shared/use-ministry-media';
import {richTextPlain} from '../../shared/rich-text.ts';
import {onBrand} from './experience-model';
import Icon,{type IconName} from './Icon';

type Palette={bg:string;surface:string;text:string;muted:string;line:string;brand:string;accent?:string};
export type Shortcut={key:string;icon:IconName;label:string;onPress:()=>void};
type Props={
 palette:Palette;dark:boolean;rpc:ChurchRpc;org:string;unit:string;authenticated:boolean;name:string;churchName:string;
 posts:PublicPost[];postsLoading:boolean;events:AgendaEvent[];eventsLoading:boolean;
 shortcuts:Shortcut[];onBanner:(p:PublicPost)=>void;onPost:(id:string)=>void;onEvent:(id:string)=>void;onVideo:(id:string)=>void;
 onAgenda:()=>void;onTickets:()=>void;onVideos:()=>void;onContent:()=>void;onLogin:()=>void;onChurch:()=>void;footer?:ReactNode;
};
const months=['JAN','FEV','MAR','ABR','MAI','JUN','JUL','AGO','SET','OUT','NOV','DEZ'];
const weekdays=['domingo','segunda','terça','quarta','quinta','sexta','sábado'];
function local(iso:string){const d=new Date(new Date(iso).toLocaleString('en-US',{timeZone:'America/Sao_Paulo'}));return d}
function hour(iso:string){return local(iso).toLocaleTimeString('pt-BR',{hour:'2-digit',minute:'2-digit'})}
/** Mistura a cor da igreja com branco ou preto para fundos suaves (tons do tema). */
function tint(hex:string,amount:number,toward:'#ffffff'|'#000000'){const a=[1,3,5].map(i=>parseInt(hex.slice(i,i+2),16)),b=[1,3,5].map(i=>parseInt(toward.slice(i,i+2),16));return '#'+a.map((v,i)=>Math.round(v+(b[i]-v)*amount).toString(16).padStart(2,'0')).join('')}

/** Início do app (identidade Vinha): capa na cor da igreja, próximo encontro, atalhos em grade, banners, agenda em linha do tempo, vídeos e avisos. */
export default function HomeScreen(x:Props){
 const p=x.palette,{width}=useWindowDimensions(),inner=Math.min(width,760)-40,slide=inner,[index,setIndex]=useState(0),fg=onBrand(p.brand),ac=p.accent||p.brand;
 const tileCols=width>=900?6:3,videoCols=width>=600?3:2,tileBasis=(100/tileCols-3)+'%';
 const soft=x.dark?tint(p.brand,0.78,'#000000'):tint(p.brand,0.88,'#ffffff');
 const media=useMinistryMedia(x.rpc,x.org,x.unit,'video',x.authenticated);
 const banners=x.posts.filter(b=>b.kind==='banner'&&appImage(b.image));
 const notices=x.posts.filter(b=>b.kind==='notice');
 const pos=new Map(media.history.map(h=>[h.media_id,h.position_seconds]));
 const resume=media.items.find(i=>(pos.get(i.id)||0)>0);
 const featured=resume||media.items[0],grid=media.items.filter(i=>i.id!==featured?.id).slice(0,width>=600?6:4);
 const next=x.events.find(e=>e.status!=='cancelled');
 const head=(over:string,title:string,action?:()=>void)=><View style={s.head}><View style={{flex:1}}><Text style={[s.over,{color:ac}]}>{over}</Text><Text accessibilityRole="header" style={[s.headTitle,{color:p.text}]}>{title}</Text></View>{action&&<Pressable accessibilityRole="button" accessibilityLabel={'Ver tudo: '+title} onPress={action} hitSlop={8}><Text style={{color:p.muted,fontWeight:'700'}}>Ver tudo →</Text></Pressable>}</View>;
 const img=(uri:string|null|undefined,style:object,fallback:string)=>{const u=appImage(uri);return <View style={[{overflow:'hidden',backgroundColor:soft,alignItems:'center',justifyContent:'center'},style]}>{u?<Image source={{uri:u}} resizeMode="cover" style={StyleSheet.absoluteFill}/>:<Text style={{color:ac,fontSize:26}}>{fallback}</Text>}</View>};
 const dateBlock=(iso:string,big=false)=>{const d=local(iso);return <View style={[s.date,{backgroundColor:big?'rgba(255,255,255,0.18)':soft,width:big?62:54}]}><Text style={{color:big?fg:ac,fontSize:big?24:20,fontWeight:'900'}}>{String(d.getDate()).padStart(2,'0')}</Text><Text style={{color:big?fg:ac,fontSize:11,fontWeight:'800',letterSpacing:1}}>{months[d.getMonth()]}</Text></View>};
 return <View>
  <View style={[s.cover,{backgroundColor:p.brand}]}>
   <View style={[s.blob,{width:220,height:220,top:-90,right:-60,backgroundColor:fg,opacity:.08}]}/>
   <View style={[s.blob,{width:140,height:140,bottom:-50,left:-40,backgroundColor:fg,opacity:.06}]}/>
   <Text style={{color:fg,opacity:.85,fontSize:15,fontWeight:'600'}}>{x.authenticated?'Que bom ter você aqui':'Seja bem-vindo'}</Text>
   <Text numberOfLines={1} style={{color:fg,fontSize:30,fontWeight:'900',marginTop:2}}>{x.authenticated?x.name:x.churchName||'à nossa igreja'}</Text>
   {next?<Pressable accessibilityRole="button" accessibilityLabel={'Próximo encontro: '+next.title} onPress={()=>x.onEvent(next.id)} style={s.nextCard}>
    {dateBlock(next.starts_at,true)}
    <View style={{flex:1}}><Text style={{color:fg,opacity:.8,fontSize:12,fontWeight:'800',letterSpacing:1}}>SEU PRÓXIMO ENCONTRO</Text><Text numberOfLines={2} style={{color:fg,fontSize:17,fontWeight:'800',marginTop:2}}>{next.title}</Text><Text style={{color:fg,opacity:.85,marginTop:2}}>{weekdays[local(next.starts_at).getDay()]} · {hour(next.starts_at)}</Text></View>
    <Icon name="chevron" color={fg} size={22}/>
   </Pressable>:x.eventsLoading?<ActivityIndicator color={fg} style={{marginTop:16}}/>:<Pressable accessibilityRole="button" onPress={x.onAgenda} style={s.nextCard}><Icon name="calendar" color={fg} size={22}/><Text style={{color:fg,fontWeight:'700',flex:1}}>Veja a agenda da igreja</Text><Icon name="chevron" color={fg} size={22}/></Pressable>}
  </View>

  <View style={s.grid}>
   {x.shortcuts.map(c=><Pressable key={c.key} accessibilityRole="button" accessibilityLabel={c.label} onPress={c.onPress} style={({pressed})=>[s.tile,{flexBasis:tileBasis,backgroundColor:p.surface,borderColor:p.line,opacity:pressed?.75:1}]}>
    <View style={[s.tileIcon,{backgroundColor:soft}]}><Icon name={c.icon} color={ac} size={24}/></View>
    <Text numberOfLines={2} style={{color:p.text,fontWeight:'700',fontSize:13,marginTop:8}}>{c.label}</Text>
   </Pressable>)}
  </View>

  {banners.length>0&&<View style={{marginTop:26}}>
   <ScrollView horizontal pagingEnabled snapToInterval={slide+12} decelerationRate="fast" showsHorizontalScrollIndicator={false} onMomentumScrollEnd={e=>setIndex(Math.round(e.nativeEvent.contentOffset.x/(slide+12)))}>
    {banners.map(b=><Pressable key={b.id} accessibilityRole="button" accessibilityLabel={b.title} onPress={()=>x.onBanner(b)} style={{width:slide,marginRight:12}}>
     {img(b.image,{height:Math.min(Math.round(slide*0.52),300),borderRadius:24},'')}
     <View style={s.shade}><Text numberOfLines={2} style={{color:'#fff',fontSize:17,fontWeight:'800'}}>{b.title}</Text></View>
    </Pressable>)}
   </ScrollView>
   {banners.length>1&&<View style={[s.counter,{backgroundColor:'rgba(0,0,0,0.55)'}]}><Text style={{color:'#fff',fontWeight:'800',fontSize:12}}>{index+1}/{banners.length}</Text></View>}
  </View>}

  {head('Agenda','Próximos dias',x.onAgenda)}
  <View style={[s.panel,{backgroundColor:p.surface,borderColor:p.line}]}>
   {x.eventsLoading?<ActivityIndicator color={p.brand}/>:x.events.length?x.events.slice(0,4).map((e,i)=><Pressable key={e.id} accessibilityRole="button" accessibilityLabel={'Evento '+e.title} onPress={()=>x.onEvent(e.id)} style={[s.agendaRow,i>0&&{borderTopWidth:1,borderTopColor:p.line}]}>
    {dateBlock(e.starts_at)}
    <View style={{flex:1}}><Text numberOfLines={2} style={{color:p.text,fontWeight:'800',fontSize:16}}>{e.title}</Text><Text style={{color:p.muted,marginTop:2}}>{weekdays[local(e.starts_at).getDay()]} · {hour(e.starts_at)}{e.location?' · '+e.location:''}</Text></View>
    {appImage(e.cover)&&img(e.cover,{width:64,height:64,borderRadius:14},'')}
   </Pressable>):<Text style={{color:p.muted}}>Nenhum evento programado agora.</Text>}
   <Pressable accessibilityRole="button" onPress={x.authenticated?x.onTickets:x.onLogin} style={[s.ticketBar,{backgroundColor:soft}]}><Icon name="ticket" color={ac} size={22}/><Text style={{color:ac,fontWeight:'800',flex:1}}>Minhas inscrições e QR Codes</Text><Icon name="chevron" color={ac} size={18}/></Pressable>
  </View>

  {featured&&<>{head(resume?'Continue':'Novidade','Palavra e mensagens',x.onVideos)}
   <Pressable accessibilityRole="button" accessibilityLabel={'Assistir '+featured.title} onPress={()=>x.onVideo(featured.id)}>
    {img(featured.poster,{height:Math.min(Math.round(inner*0.5),320),borderRadius:24},'▶')}
    <View style={s.shade}><View style={[s.pill,{backgroundColor:p.brand}]}><Text style={{color:fg,fontWeight:'800',fontSize:12}}>{resume?'▶ CONTINUAR':'▶ ASSISTIR'}</Text></View><Text numberOfLines={2} style={{color:'#fff',fontSize:18,fontWeight:'800',marginTop:8}}>{featured.title}</Text></View>
   </Pressable>
   <View style={s.videoGrid}>{grid.map(v=><Pressable key={v.id} accessibilityRole="button" accessibilityLabel={'Assistir '+v.title} onPress={()=>x.onVideo(v.id)} style={{width:(inner-12*(videoCols-1))/videoCols}}>{img(v.poster,{height:Math.round((inner-12*(videoCols-1))/videoCols*0.56),borderRadius:16},'▶')}<Text numberOfLines={2} style={{color:p.text,fontWeight:'700',marginTop:6}}>{v.title}</Text></Pressable>)}</View>
  </>}

  {head('Mural','Avisos da igreja',x.onContent)}
  {x.postsLoading?<ActivityIndicator color={p.brand}/>:notices.length?notices.slice(0,5).map(n=><Pressable key={n.id} accessibilityRole="button" accessibilityLabel={'Abrir '+n.title} onPress={()=>x.onPost(n.id)} style={[s.notice,{backgroundColor:p.surface,borderColor:p.line}]}>
   {appImage(n.image)?img(n.image,{width:84,height:84,borderRadius:16},''):<View style={{width:84,height:84,borderRadius:16,backgroundColor:soft,alignItems:'center',justifyContent:'center'}}><Icon name="mail" color={ac} size={30}/></View>}
   <View style={{flex:1}}><Text numberOfLines={2} style={{color:p.text,fontWeight:'800',fontSize:16}}>{n.title}</Text><Text numberOfLines={2} style={{color:p.muted,marginTop:4}}>{richTextPlain(n.body,140)}</Text></View>
  </Pressable>):<Text style={{color:p.muted}}>Sem avisos novos da igreja.</Text>}
  {x.footer}
 </View>;
}
const s=StyleSheet.create({
 cover:{marginHorizontal:-20,marginTop:-20,paddingHorizontal:22,paddingTop:26,paddingBottom:24,borderBottomLeftRadius:32,borderBottomRightRadius:32,overflow:'hidden'},
 blob:{position:'absolute',borderRadius:999},
 nextCard:{flexDirection:'row',alignItems:'center',gap:14,marginTop:20,padding:14,borderRadius:22,backgroundColor:'rgba(255,255,255,0.14)',borderWidth:1,borderColor:'rgba(255,255,255,0.22)'},
 date:{height:58,borderRadius:16,alignItems:'center',justifyContent:'center'},
 grid:{flexDirection:'row',flexWrap:'wrap',gap:10,marginTop:20},
 tile:{flexGrow:1,borderWidth:1,borderRadius:20,padding:12,minHeight:96},
 tileIcon:{width:42,height:42,borderRadius:14,alignItems:'center',justifyContent:'center'},
 shade:{position:'absolute',left:0,right:0,bottom:0,padding:16,borderBottomLeftRadius:24,borderBottomRightRadius:24,backgroundColor:'rgba(0,0,0,0.45)'},
 counter:{position:'absolute',top:12,right:12,borderRadius:12,paddingHorizontal:10,paddingVertical:4},
 head:{flexDirection:'row',alignItems:'flex-end',gap:8,marginTop:28,marginBottom:12},
 over:{fontSize:11,fontWeight:'900',letterSpacing:1.6,textTransform:'uppercase'},
 headTitle:{fontSize:22,fontWeight:'900'},
 panel:{borderWidth:1,borderRadius:24,padding:14},
 agendaRow:{flexDirection:'row',alignItems:'center',gap:12,paddingVertical:10},
 ticketBar:{flexDirection:'row',alignItems:'center',borderRadius:16,padding:14,marginTop:10},
 pill:{alignSelf:'flex-start',borderRadius:10,paddingHorizontal:10,paddingVertical:4},
 videoGrid:{flexDirection:'row',flexWrap:'wrap',gap:12,marginTop:12},
 notice:{flexDirection:'row',gap:12,alignItems:'center',borderWidth:1,borderRadius:22,padding:10,marginBottom:10},
});
