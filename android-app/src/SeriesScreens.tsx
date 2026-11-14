import {useEffect,useState} from 'react';
import {Image,Pressable,ScrollView,StyleSheet,Text,View} from 'react-native';
import {appImage} from '../../shared/app-images';
import type {ChurchRpc} from '../../shared/member-church';
import {nextEpisode,type Series,type SeriesEpisode} from '../../shared/series';
import {onBrand} from './experience-model';
import Icon from './Icon';
type Palette={surface:string;text:string;muted:string;line:string;brand:string;accent?:string};

/** Séries publicadas para a igreja local (Comunicação › Séries de mensagens). */
export function useSeries(rpc:ChurchRpc,org:string,unit:string,active:boolean){
 const [items,setItems]=useState<Series[]>([]);
 useEffect(()=>{let live=true;setItems([]);if(!active||!unit)return;
  void Promise.resolve(rpc.rpc('member_series',{p_org:org,p_unit:unit})).then(r=>{if(live&&!r.error)setItems(((r.data as {items?:Series[]})?.items)||[])}).catch(()=>undefined);
  return()=>{live=false}},[rpc,org,unit,active]);
 return items;
}

/** Prateleira "Séries de mensagens": capas em formato retrato com a faixa da cor da igreja. */
export function SeriesShelf({items,palette:p,onOpen}:{items:Series[];palette:Palette;onOpen:(id:string)=>void}){
 if(!items.length)return null;const ac=p.accent||p.brand;
 return <View style={{marginTop:20}}>
  <Text style={[s.over,{color:ac}]}>SÉRIES DE MENSAGENS</Text>
  <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{gap:12}}>{items.map(x=>{const img=appImage(x.poster);return <Pressable key={x.id} accessibilityRole="button" accessibilityLabel={'Abrir série '+x.title} onPress={()=>onOpen(x.id)} style={[s.card,{backgroundColor:p.brand}]}>
   {img?<Image source={{uri:img}} resizeMode="cover" style={StyleSheet.absoluteFill}/>:<><View style={[s.blob,{backgroundColor:onBrand(p.brand),opacity:.1}]}/><View style={[s.blob2,{backgroundColor:onBrand(p.brand),opacity:.07}]}/></>}
   <View style={[s.band,{backgroundColor:p.brand}]}><Text numberOfLines={2} style={{color:onBrand(p.brand),fontWeight:'900',fontSize:16}}>{x.title}</Text><Text style={{color:onBrand(p.brand),opacity:.85,fontSize:12,marginTop:2}}>{x.episodes.length} {x.episodes.length===1?'mensagem':'mensagens'}</Text></View>
  </Pressable>})}</ScrollView>
 </View>;
}

/** Série aberta: capa, descrição, botão para continuar e a trilha numerada dos episódios. */
export function SeriesView({series:x,watched,palette:p,onPlay,onBack}:{series:Series;watched:(id:string)=>number;palette:Palette;onPlay:(e:SeriesEpisode)=>void;onBack:()=>void}){
 const ac=p.accent||p.brand,onB=onBrand(p.brand),img=appImage(x.poster),next=nextEpisode(x.episodes,watched),started=x.episodes.some(e=>watched(e.id)>0);
 return <View>
  <Pressable accessibilityRole="button" onPress={onBack} style={{paddingVertical:10}}><Text style={{color:ac,fontWeight:'800'}}>‹ Biblioteca</Text></Pressable>
  <View style={[s.cover,{backgroundColor:p.brand}]}>
   {img?<Image source={{uri:img}} resizeMode="cover" style={[StyleSheet.absoluteFill,{opacity:.35}]}/>:null}<View style={[s.blob,{backgroundColor:onB,opacity:.08}]}/>
   <Text style={{color:onB,fontSize:11,fontWeight:'800',letterSpacing:2}}>SÉRIE · {x.episodes.length} {x.episodes.length===1?'MENSAGEM':'MENSAGENS'}</Text>
   <Text style={{color:onB,fontSize:26,fontWeight:'900',marginTop:6}}>{x.title}</Text>
   {!!x.description&&<Text style={{color:onB,opacity:.9,marginTop:8,lineHeight:22}}>{x.description}</Text>}
   {next&&<Pressable accessibilityRole="button" onPress={()=>onPlay(next)} style={[s.cta,{backgroundColor:onB}]}><Icon name="play" color={p.brand} size={20}/><Text style={{color:p.brand,fontWeight:'900'}}>{started?'Continuar · parte '+(x.episodes.indexOf(next)+1):'Começar pela parte 1'}</Text></Pressable>}
  </View>
  <Text style={[s.over,{color:ac,marginTop:18}]}>A TRILHA DA SÉRIE</Text>
  {x.episodes.map((e,i)=>{const seen=watched(e.id)>0,last=i===x.episodes.length-1;return <Pressable key={e.id} accessibilityRole="button" accessibilityLabel={'Assistir parte '+(i+1)+': '+e.title} onPress={()=>onPlay(e)} style={s.step}>
   <View style={{alignItems:'center'}}><View style={[s.dot,{borderColor:ac,backgroundColor:seen?ac:'transparent'}]}><Text style={{color:seen?onBrand(ac):ac,fontWeight:'900'}}>{seen?'✓':i+1}</Text></View>{!last&&<View style={[s.line,{backgroundColor:p.line}]}/>}</View>
   <View style={[s.ep,{backgroundColor:p.surface,borderColor:next?.id===e.id?ac:p.line}]}>
    <Text style={{color:p.muted,fontSize:11,fontWeight:'800',letterSpacing:1}}>PARTE {i+1}{next?.id===e.id?' · PRÓXIMA':''}</Text>
    <Text numberOfLines={2} style={{color:p.text,fontWeight:'800',fontSize:16,marginTop:2}}>{e.title}</Text>
    {!!e.description&&<Text numberOfLines={2} style={{color:p.muted,marginTop:4}}>{e.description}</Text>}
   </View>
  </Pressable>})}
 </View>;
}
const s=StyleSheet.create({
 over:{fontSize:11,fontWeight:'800',letterSpacing:1.8,marginBottom:10},
 card:{width:168,height:224,borderRadius:22,overflow:'hidden',justifyContent:'flex-end'},
 band:{margin:8,borderRadius:16,padding:10,opacity:.96},
 blob:{position:'absolute',width:200,height:200,borderRadius:100,right:-80,top:-70},blob2:{position:'absolute',width:120,height:120,borderRadius:60,left:-40,top:60},
 cover:{borderRadius:24,padding:22,overflow:'hidden'},
 cta:{flexDirection:'row',alignItems:'center',gap:8,alignSelf:'flex-start',borderRadius:22,paddingHorizontal:16,paddingVertical:11,marginTop:16},
 step:{flexDirection:'row',gap:12},dot:{width:34,height:34,borderRadius:17,borderWidth:2,alignItems:'center',justifyContent:'center'},line:{width:2,flex:1,minHeight:18},
 ep:{flex:1,borderWidth:1,borderRadius:18,padding:12,marginBottom:12},
});
