import {StyleSheet,Text,View} from 'react-native';
import {profileProgress} from '../../shared/profile-progress';
type Palette={surface:string;text:string;muted:string;line:string;brand:string;accent?:string};

/** Cartão "Seu cadastro": porcentagem geral e o que falta em cada seção. */
export default function ProfileProgress({profile,palette:p,compact=false}:{profile:Record<string,string>|null|undefined;palette:Palette;compact?:boolean}){
 const r=profileProgress(profile),ac=p.accent||p.brand,bar=(v:number)=><View style={[s.track,{backgroundColor:p.line}]}><View style={[s.fill,{width:`${v}%`,backgroundColor:ac}]}/></View>;
 return <View style={[s.card,{backgroundColor:p.surface,borderColor:p.line}]}>
  <View style={s.row}><Text style={{color:p.text,fontWeight:'800',fontSize:16,flex:1}}>Seu cadastro</Text><Text style={{color:ac,fontWeight:'900',fontSize:20}}>{r.percent}%</Text></View>
  {bar(r.percent)}
  {!compact&&r.sections.map(sec=><View key={sec.key} style={{marginTop:12}}>
   <View style={s.row}><Text style={{color:p.text,fontWeight:'700',flex:1}}>{sec.label}</Text><Text style={{color:sec.missing.length?p.muted:ac,fontWeight:'700'}}>{sec.missing.length?`${sec.done}/${sec.total}`:'Completo'}</Text></View>
   {sec.missing.length>0&&<Text style={{color:p.muted,marginTop:2}}>Falta: {sec.missing.join(', ')}</Text>}
  </View>)}
  {compact&&r.percent<100&&<Text style={{color:p.muted,marginTop:8}}>Complete seu cadastro para a igreja conhecer você melhor.</Text>}
 </View>;
}
const s=StyleSheet.create({card:{borderWidth:1,borderRadius:20,padding:16,marginBottom:14},row:{flexDirection:'row',alignItems:'center',gap:8},track:{height:8,borderRadius:4,marginTop:10,overflow:'hidden'},fill:{height:8,borderRadius:4}});
