import {Pressable,StyleSheet,Text,View} from 'react-native';
import {profileProgress} from '../../shared/profile-progress';
type Palette={surface:string;text:string;muted:string;line:string;brand:string;accent?:string};

/** "Seu cadastro" (identidade Vinha): uma faixa por seção e as informações que faltam em etiquetas. */
export default function ProfileProgress({profile,palette:p,compact=false,onFill}:{profile:Record<string,string>|null|undefined;palette:Palette;compact?:boolean;onFill?:()=>void}){
 const r=profileProgress(profile),ac=p.accent||p.brand,missing=r.sections.flatMap(s=>s.missing),done=missing.length===0;
 return <View style={[s.card,{backgroundColor:p.surface,borderColor:p.line}]}>
  <Text style={{color:p.text,fontWeight:'900',fontSize:17}}>{done?'Cadastro completo':missing.length===1?'Falta 1 informação':`Faltam ${missing.length} informações`}</Text>
  <Text style={{color:p.muted,marginTop:2}}>{done?'Obrigado! A igreja já conhece você melhor.':'Com o cadastro em dia a igreja cuida melhor de você.'}</Text>
  <View style={s.segments}>{r.sections.map(sec=><View key={sec.key} style={{flex:1}}><View style={[s.track,{backgroundColor:p.line}]}><View style={{height:6,borderRadius:3,width:`${Math.round(sec.done/sec.total*100)}%`,backgroundColor:ac}}/></View><Text style={{color:p.muted,fontSize:11,marginTop:4,fontWeight:'700'}}>{sec.label}</Text></View>)}</View>
  {!compact&&missing.length>0&&<View style={s.tags}>{missing.map(m=><View key={m} style={[s.tag,{borderColor:p.line}]}><Text style={{color:p.text,fontSize:13}}>{m}</Text></View>)}</View>}
  {compact&&!done&&onFill&&<Pressable accessibilityRole="button" onPress={onFill} style={[s.fill,{backgroundColor:ac}]}><Text style={{color:'#fff',fontWeight:'800'}}>Completar agora</Text></Pressable>}
 </View>;
}
const s=StyleSheet.create({card:{borderWidth:1,borderRadius:22,padding:16,marginBottom:14},segments:{flexDirection:'row',gap:6,marginTop:12},track:{height:6,borderRadius:3,overflow:'hidden'},tags:{flexDirection:'row',flexWrap:'wrap',gap:6,marginTop:12},tag:{borderWidth:1,borderRadius:14,paddingHorizontal:10,paddingVertical:4},fill:{alignSelf:'flex-start',borderRadius:12,paddingHorizontal:14,paddingVertical:9,marginTop:12}});
