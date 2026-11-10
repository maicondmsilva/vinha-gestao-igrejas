import {useEffect,useRef,useState,type ReactNode} from 'react';
import {AccessibilityInfo,Image,Pressable,Text,View} from 'react-native';
import * as SecureStore from 'expo-secure-store';
import {VideoView,useVideoPlayer} from 'expo-video';
import type {ChurchRpc} from '../../shared/member-church';
import {openingValid,type AppOpening} from '../../shared/ministry-media';
export default function NativeAppOpening({rpc,org,primary,logo,children}:{rpc:ChurchRpc;org:string;primary:string;logo:string|null;children:ReactNode}){
 const skipped=useRef(false);
 const [opening,setOpening]=useState<AppOpening|null>(null),[ready,setReady]=useState(false);
 useEffect(()=>{skipped.current=false;setReady(false);setOpening(null);let live=true;const timer=setTimeout(()=>{if(live){setReady(true);live=false}},3000);Promise.resolve(rpc.rpc('member_app_opening',{p_org:org})).then(async r=>{const o=openingValid(r.data),reduce=await AccessibilityInfo.isReduceMotionEnabled();if(!live||skipped.current)return;if(!r.error&&o&&o.kind!=='none'&&!(reduce&&o.kind==='video')){const seen=await SecureStore.getItemAsync('vinha.opening.'+org);if(live&&!skipped.current&&seen!==String(o.version))setOpening(o)}if(live)setReady(true)}).catch(()=>{if(live)setReady(true)});return()=>{live=false;clearTimeout(timer)}},[rpc,org]);
 useEffect(()=>{if(!opening)return;const timer=setTimeout(finish,opening.seconds*1000);return()=>clearTimeout(timer)},[opening]);
 function finish(){skipped.current=true;if(opening)void SecureStore.setItemAsync('vinha.opening.'+org,String(opening.version)).catch(()=>{});setOpening(null);setReady(true)}
 if(ready&&!opening)return <>{children}</>;
 return <View style={{flex:1,backgroundColor:primary,padding:24,justifyContent:'center',alignItems:'center'}}>{logo&&<Image source={{uri:logo}} accessibilityLabel="Logo do ministério" style={{height:85,width:150,resizeMode:'contain',marginBottom:20}}/>}{opening?.kind==='image'&&<Image source={{uri:opening.url}} accessibilityLabel={opening.title||'Boas-vindas à igreja'} onError={finish} style={{width:'100%',height:'55%',resizeMode:'contain'}}/>}{opening?.kind==='video'&&<IntroVideo source={opening.url} onFinish={finish}/>}<Text style={{color:'#fff',textAlign:'center',fontSize:20,marginVertical:20}}>{opening?.title||'Bem-vindo à sua igreja'}</Text><Pressable accessibilityRole="button" onPress={finish} style={{backgroundColor:'#fff',padding:16,borderRadius:12}}><Text style={{color:'#163b2d',fontWeight:'700'}}>Pular abertura e continuar</Text></Pressable></View>;
}
function IntroVideo({source,onFinish}:{source:string;onFinish:()=>void}){const player=useVideoPlayer(source,p=>{p.muted=true;p.loop=false;p.play()});useEffect(()=>{const a=player.addListener('playToEnd',onFinish),b=player.addListener('statusChange',e=>{if(e.status==='error')onFinish()});return()=>{a.remove();b.remove()}},[player,onFinish]);return <VideoView player={player} nativeControls={false} contentFit="contain" surfaceType="textureView" style={{width:'100%',height:'55%'}}/>}
