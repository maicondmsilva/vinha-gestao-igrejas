import {useState} from 'react';
import {ActivityIndicator,Image,Pressable,ScrollView,StyleSheet,Text,useWindowDimensions,View} from 'react-native';
import {appImage} from '../../shared/app-images';
import {agendaDate,type AgendaEvent} from '../../shared/member-agenda';
import type {PublicPost,ChurchRpc} from '../../shared/member-church';
import {useMinistryMedia} from '../../shared/use-ministry-media';
import {richTextPlain} from '../../shared/rich-text.ts';
import {onBrand} from './experience-model';

type Palette={bg:string;surface:string;text:string;muted:string;line:string;brand:string};
export type Shortcut={key:string;icon:string;label:string;onPress:()=>void};
type Props={
 palette:Palette;rpc:ChurchRpc;org:string;unit:string;authenticated:boolean;name:string;churchName:string;
 posts:PublicPost[];postsLoading:boolean;events:AgendaEvent[];eventsLoading:boolean;
 shortcuts:Shortcut[];onBanner:(p:PublicPost)=>void;onPost:(id:string)=>void;onEvent:(id:string)=>void;onVideo:(id:string)=>void;
 onAgenda:()=>void;onTickets:()=>void;onVideos:()=>void;onContent:()=>void;onLogin:()=>void;onChurch:()=>void;footer?:React.ReactNode;
};

/** Início do app: saudação, banners da igreja, atalhos, minha agenda, vídeos e avisos com imagem. */
export default function HomeScreen(x:Props){
 const p=x.palette,{width}=useWindowDimensions(),slide=width-40,[index,setIndex]=useState(0);
 const media=useMinistryMedia(x.rpc,x.org,x.unit,'video',x.authenticated);
 const banners=x.posts.filter(b=>b.kind==='banner'&&appImage(b.image));
 const notices=x.posts.filter(b=>b.kind==='notice');
 const pos=new Map(media.history.map(h=>[h.media_id,h.position_seconds]));
 const continueWatching=media.items.filter(i=>(pos.get(i.id)||0)>0);
 const head=(title:string,action?:()=>void,label='Ver todos')=><View style={s.head}><Text accessibilityRole="header" style={[s.headTitle,{color:p.text}]}>{title}</Text>{action&&<Pressable accessibilityRole="button" accessibilityLabel={label+': '+title} onPress={action} style={s.headAction}><Text style={{color:p.brand,fontWeight:'700'}}>{label}</Text></Pressable>}</View>;
 const thumb=(uri:string|null|undefined,h:number,fallback:string)=>{const img=appImage(uri);return <View style={{height:h,borderRadius:14,overflow:'hidden',backgroundColor:p.line,alignItems:'center',justifyContent:'center'}}>{img?<Image source={{uri:img}} resizeMode="cover" style={StyleSheet.absoluteFill}/>:<Text style={{color:p.muted,fontSize:28}}>{fallback}</Text>}</View>};
 return <View>
  <View style={s.greet}>
   <View style={[s.avatar,{backgroundColor:p.brand}]}><Text style={{color:onBrand(p.brand),fontWeight:'800',fontSize:22}}>{(x.name||'?').slice(0,1).toUpperCase()}</Text></View>
   <View style={{flex:1}}><Text style={{color:p.muted,fontSize:16}}>{x.authenticated?'Que bom ter você aqui,':'Bem-vindo à'}</Text><Text numberOfLines={1} style={{color:p.brand,fontSize:26,fontWeight:'800'}}>{x.authenticated?x.name:x.churchName||'nossa igreja'}</Text></View>
  </View>
  {banners.length>0&&<View style={{marginTop:18}}>
   <ScrollView horizontal pagingEnabled snapToInterval={slide+12} decelerationRate="fast" showsHorizontalScrollIndicator={false} onMomentumScrollEnd={e=>setIndex(Math.round(e.nativeEvent.contentOffset.x/(slide+12)))}>
    {banners.map(b=><Pressable key={b.id} accessibilityRole="button" accessibilityLabel={b.title} onPress={()=>x.onBanner(b)} style={{width:slide,marginRight:12}}>{thumb(b.image,Math.round(slide*0.5),'')}</Pressable>)}
   </ScrollView>
   {banners.length>1&&<View style={s.dots}>{banners.map((b,i)=><View key={b.id} style={[s.dot,{backgroundColor:i===index?p.brand:p.line,width:i===index?18:8}]}/>)}</View>}
  </View>}
  <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{marginTop:20}} contentContainerStyle={{gap:14,paddingRight:8}}>
   {x.shortcuts.map(c=><Pressable key={c.key} accessibilityRole="button" accessibilityLabel={c.label} onPress={c.onPress} style={s.shortcut}><View style={[s.circle,{borderColor:p.line,backgroundColor:p.surface}]}><Text style={{fontSize:26,color:p.brand}}>{c.icon}</Text></View><Text numberOfLines={2} style={{color:p.text,fontWeight:'600',textAlign:'center',fontSize:13,marginTop:6}}>{c.label}</Text></Pressable>)}
  </ScrollView>
  <View style={[s.panel,{backgroundColor:p.surface,borderColor:p.line}]}>
   {head('Minha agenda',x.onAgenda)}
   <Pressable accessibilityRole="button" onPress={x.authenticated?x.onTickets:x.onLogin} style={[s.row,{borderColor:p.line}]}><Text style={{fontSize:20,color:p.brand}}>🎟</Text><Text style={{flex:1,color:p.text,fontWeight:'700',fontSize:16}}>Meus tickets</Text><Text style={{color:p.muted,fontSize:20}}>›</Text></Pressable>
   {x.eventsLoading?<ActivityIndicator color={p.brand}/>:x.events.length?<ScrollView horizontal showsHorizontalScrollIndicator={false} style={{marginTop:12}}>{x.events.slice(0,8).map(e=><Pressable key={e.id} accessibilityRole="button" accessibilityLabel={'Evento '+e.title} onPress={()=>x.onEvent(e.id)} style={{width:260,marginRight:12}}>{thumb(e.cover,140,'▦')}<Text numberOfLines={2} style={[s.cardTitle,{color:p.text}]}>{e.title}</Text><Text style={{color:p.muted}}>{agendaDate(e.starts_at)}</Text></Pressable>)}</ScrollView>:<Text style={{color:p.muted,marginTop:10}}>Nenhum evento programado agora.</Text>}
  </View>
  {(media.items.length>0||media.loading)&&<View style={[s.panel,{backgroundColor:p.surface,borderColor:p.line}]}>
   {head('Palavra e mensagens',x.onVideos)}
   {media.loading&&!media.items.length?<ActivityIndicator color={p.brand}/>:<>
    {media.items[0]&&<Pressable accessibilityRole="button" accessibilityLabel={'Assistir '+media.items[0].title} onPress={()=>x.onVideo(media.items[0].id)}>{thumb(media.items[0].poster,190,'▶')}<Text numberOfLines={2} style={[s.cardTitle,{color:p.text}]}>{media.items[0].title}</Text></Pressable>}
    {continueWatching.length>0&&<Text style={[s.sub,{color:p.text}]}>Continue de onde parou</Text>}
    <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{marginTop:10}}>{(continueWatching.length?continueWatching:media.items.slice(1,9)).map(i=><Pressable key={i.id} accessibilityRole="button" accessibilityLabel={'Assistir '+i.title} onPress={()=>x.onVideo(i.id)} style={{width:200,marginRight:12}}>{thumb(i.poster,112,'▶')}<Text numberOfLines={2} style={{color:p.text,fontWeight:'700',marginTop:6}}>{i.title}</Text></Pressable>)}</ScrollView>
   </>}
  </View>}
  <View style={[s.panel,{backgroundColor:p.surface,borderColor:p.line}]}>
   {head('Avisos da igreja',x.onContent)}
   {x.postsLoading?<ActivityIndicator color={p.brand}/>:notices.length?<ScrollView horizontal showsHorizontalScrollIndicator={false}>{notices.slice(0,8).map(n=><Pressable key={n.id} accessibilityRole="button" accessibilityLabel={'Abrir '+n.title} onPress={()=>x.onPost(n.id)} style={{width:240,marginRight:12}}>{thumb(n.image,130,'✉')}<Text numberOfLines={2} style={[s.cardTitle,{color:p.text}]}>{n.title}</Text><Text numberOfLines={2} style={{color:p.muted}}>{richTextPlain(n.body,120)}</Text></Pressable>)}</ScrollView>:<Text style={{color:p.muted}}>Sem avisos novos da igreja.</Text>}
  </View>
  {x.footer}
 </View>;
}
const s=StyleSheet.create({
 greet:{flexDirection:'row',alignItems:'center',gap:14,marginTop:4},
 avatar:{width:58,height:58,borderRadius:29,alignItems:'center',justifyContent:'center'},
 dots:{flexDirection:'row',justifyContent:'center',gap:6,marginTop:10},
 dot:{height:8,borderRadius:4},
 shortcut:{width:78,alignItems:'center'},
 circle:{width:66,height:66,borderRadius:33,borderWidth:1,alignItems:'center',justifyContent:'center'},
 panel:{borderWidth:1,borderRadius:22,padding:18,marginTop:20},
 head:{flexDirection:'row',alignItems:'center',justifyContent:'space-between',marginBottom:10,gap:8},
 headTitle:{fontSize:21,fontWeight:'800',flexShrink:1},
 headAction:{minHeight:40,justifyContent:'center',paddingHorizontal:4},
 row:{flexDirection:'row',alignItems:'center',gap:12,paddingVertical:12,borderTopWidth:1,borderBottomWidth:1},
 cardTitle:{fontSize:16,fontWeight:'700',marginTop:8},
 sub:{fontSize:16,fontWeight:'700',marginTop:16},
});
