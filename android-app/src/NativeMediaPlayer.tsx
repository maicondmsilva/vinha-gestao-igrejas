import {useEffect,useRef,useState} from 'react';
import {AppState,Image,Linking,Pressable,Share,Text,View} from 'react-native';
import {VideoView,useVideoPlayer} from 'expo-video';
import Constants from 'expo-constants';
import {WebView} from 'react-native-webview';
import {mediaSource} from '../../shared/ministry-media';
import {appImage,watchLink} from '../../shared/app-images';
/** Toca o vídeo dentro do app: capa com play, um toque e o player abre; abaixo, compartilhar e abrir no app do provedor. */
export default function NativeMediaPlayer({source,title,start=0,onProgress,color='#173b30',poster,actions=true}:{source:string;title:string;start?:number;onProgress?:(seconds:number)=>void;color?:string;poster?:string;actions?:boolean}){
 const media=source.startsWith('file://')?{kind:'direct',url:source,embed:source}:mediaSource(source),[play,setPlay]=useState(false);
 if(!media)return <Text style={{color}}>Formato de reprodução indisponível.</Text>;
 const link=source.startsWith('file://')?null:watchLink(source),provider=media.kind==='youtube'?'YouTube':media.kind==='vimeo'?'Vimeo':'';
 const bar=actions&&link?<View style={{flexDirection:'row',gap:10,marginTop:10,flexWrap:'wrap'}}>
  <Pressable accessibilityRole="button" onPress={()=>void Share.share({message:title+'\n'+link})} style={{paddingVertical:10,paddingHorizontal:14,borderWidth:1,borderColor:color,borderRadius:20,minHeight:44,justifyContent:'center'}}><Text style={{color,fontWeight:'600'}}>Compartilhar</Text></Pressable>
  {provider!==''&&<Pressable accessibilityRole="button" onPress={()=>void Linking.openURL(link).catch(()=>undefined)} style={{paddingVertical:10,paddingHorizontal:14,borderWidth:1,borderColor:color,borderRadius:20,minHeight:44,justifyContent:'center'}}><Text style={{color,fontWeight:'600'}}>Abrir no {provider}</Text></Pressable>}
 </View>:null;
 if(media.kind==='direct')return <View><DirectPlayer key={media.url} source={media.url} title={title} start={start} onProgress={onProgress} color={color}/>{bar}</View>;
 const cover=appImage(poster);
 const embed=media.embed+(media.embed.includes('?')?'&':'?')+'autoplay=1&playsinline=1'+(start>0&&media.kind==='youtube'?'&start='+Math.floor(start):'');
 return <View>{play?<WebView source={{uri:embed,headers:{Referer:'https://'+(Constants.expoConfig?.android?.package||'com.vinha.mpr.preview')}}} style={{height:220,backgroundColor:'#080e15',borderRadius:12}} javaScriptEnabled domStorageEnabled allowsFullscreenVideo mediaPlaybackRequiresUserAction={false} allowsInlineMediaPlayback setSupportMultipleWindows={false} onShouldStartLoadWithRequest={r=>{try{return r.url==='about:blank'||['www.youtube-nocookie.com','www.youtube.com','youtube.com','player.vimeo.com'].includes(new URL(r.url).hostname)}catch{return false}}}/>
  :<Pressable accessibilityRole="button" accessibilityLabel={'Assistir '+title} onPress={()=>setPlay(true)} style={{height:220,borderRadius:12,overflow:'hidden',backgroundColor:'#080e15',alignItems:'center',justifyContent:'center'}}>
   {cover&&<Image source={{uri:cover}} resizeMode="cover" style={{position:'absolute',top:0,left:0,right:0,bottom:0}}/>}
   <View style={{width:68,height:68,borderRadius:34,backgroundColor:'rgba(0,0,0,0.55)',borderWidth:2,borderColor:'#ffffff',alignItems:'center',justifyContent:'center'}}><Text style={{color:'#ffffff',fontSize:28,marginLeft:4}}>▶</Text></View>
  </Pressable>}{bar}</View>;
}
function DirectPlayer({source,title,start,onProgress,color}:{source:string;title:string;start:number;onProgress?: (seconds:number)=>void;color:string}){
 const [failed,setFailed]=useState(false),last=useRef(0),callback=useRef(onProgress);callback.current=onProgress;
 const player=useVideoPlayer({uri:source,contentType:/\.m3u8(?:\?|$)/i.test(source)?'hls':'progressive'},p=>{p.timeUpdateEventInterval=1;p.currentTime=Math.max(0,start);p.loop=false});
 useEffect(()=>{const a=player.addListener('timeUpdate',e=>{const seconds=Math.floor(e.currentTime);if(Math.abs(seconds-last.current)>=15){last.current=seconds;callback.current?.(seconds)}}),b=player.addListener('statusChange',e=>{if(e.status==='error')setFailed(true)}),state=AppState.addEventListener('change',s=>{if(s!=='active')player.pause()});return()=>{a.remove();b.remove();state.remove()}},[player]);
 if(failed)return <Text accessibilityRole="alert" style={{color}}>Não foi possível reproduzir. Confira a conexão e abra novamente o vídeo.</Text>;
 return <VideoView player={player} nativeControls contentFit="contain" surfaceType="textureView" fullscreenOptions={{enable:true}} accessibilityLabel={'Reprodutor: '+title} style={{height:230,width:'100%',backgroundColor:'#080e15',borderRadius:12}}/>;
}
