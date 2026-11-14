import {useState,type Dispatch,type SetStateAction} from 'react';
import {ActivityIndicator,Pressable,StyleSheet,Text,View} from 'react-native';
import ChurchSelect from './ChurchSelect';
import RegistrationFields from './RegistrationFields';
import {onBrand} from './experience-model';
import {registrationSteps,stepMissing} from '../../shared/login-rules';
type Church={id:string;name:string};
type Props={churches:Church[];unit:string;setUnit:(v:string)=>void;form:Record<string,string>;setForm:Dispatch<SetStateAction<Record<string,string>>>;lockChurch:boolean;locked:boolean;busy:boolean;onSubmit:()=>void;color:string;background:string;accent:string;muted?:string;line?:string};

/** Cadastro para a igreja em etapas: igreja, sobre você, contato e endereço, com o que falta em cada uma. */
export default function RegistrationSteps(p:Props){
 const steps=[{key:'church',title:'Sua igreja',fields:[] as readonly string[]},...registrationSteps],[at,setAt]=useState(0);
 const muted=p.muted||p.color,line=p.line||'#83978a',step=steps[at]!,last=at===steps.length-1,onA=onBrand(p.accent);
 const missing=(i:number)=>i===0?(p.unit?[]:['church']):stepMissing(p.form,steps[i]!.fields);
 return <View>
  <View style={s.track}>{steps.map((x,i)=>{const done=!missing(i).length,on=i===at;return <Pressable key={x.key} accessibilityRole="tab" accessibilityState={{selected:on}} accessibilityLabel={(i+1)+'. '+x.title+(done?', completo':'')} onPress={()=>setAt(i)} style={{flex:1}}>
   <View style={[s.bar,{backgroundColor:done||on?p.accent:line,opacity:on||done?1:.6}]}/><Text numberOfLines={1} style={{color:on?p.color:muted,fontWeight:on?'800':'600',fontSize:12,marginTop:6}}>{done&&!on?'✓':i+1}</Text></Pressable>})}</View>
  <Text style={{color:muted,fontSize:12,fontWeight:'800',letterSpacing:1.5}}>ETAPA {at+1} DE {steps.length}</Text><Text style={[s.title,{color:p.color}]}>{step.title}</Text>
  {at===0?<><Text style={{color:muted,marginBottom:10,lineHeight:21}}>A igreja onde você congrega. É ela que vai conferir seu cadastro.</Text><ChurchSelect churches={p.churches} value={p.unit} onChange={p.setUnit} disabled={p.busy||p.lockChurch} color={p.color} background={p.background} accent={p.accent}/></>
   :<RegistrationFields only={step.fields} form={p.form} setForm={p.setForm} disabled={p.busy||p.locked} color={p.color} background={p.background} accent={p.accent}/>}
  {missing(at).length>0&&at>0&&<Text style={{color:muted,fontSize:13,marginBottom:6}}>Ainda falta: {missing(at).length} {missing(at).length===1?'campo':'campos'} nesta etapa. Você pode completar depois.</Text>}
  <View style={s.nav}>
   {at>0&&<Pressable accessibilityRole="button" onPress={()=>setAt(at-1)} style={[s.ghost,{borderColor:line}]}><Text style={{color:p.color,fontWeight:'800'}}>Voltar</Text></Pressable>}
   {!last?<Pressable accessibilityRole="button" onPress={()=>setAt(at+1)} style={[s.primary,{backgroundColor:p.accent}]}><Text style={{color:onA,fontWeight:'900'}}>Continuar</Text></Pressable>
    :<Pressable accessibilityRole="button" accessibilityState={{disabled:p.busy||p.locked}} disabled={p.busy||p.locked} onPress={p.onSubmit} style={[s.primary,{backgroundColor:p.accent,opacity:p.busy||p.locked?.5:1}]}>{p.busy?<ActivityIndicator color={onA}/>:<Text style={{color:onA,fontWeight:'900'}}>Enviar para a igreja</Text>}</Pressable>}
  </View>
  {p.locked&&<Text style={{color:muted,fontSize:13,marginTop:8}}>Seu cadastro está em análise pela igreja. Os campos voltam a ficar livres depois da resposta.</Text>}
 </View>;
}
const s=StyleSheet.create({track:{flexDirection:'row',gap:6,marginBottom:16},bar:{height:6,borderRadius:3},title:{fontSize:20,fontWeight:'900',marginBottom:10},nav:{flexDirection:'row',gap:10,marginTop:10},primary:{flex:1,borderRadius:16,minHeight:52,alignItems:'center',justifyContent:'center'},ghost:{borderWidth:1,borderRadius:16,minHeight:52,paddingHorizontal:20,alignItems:'center',justifyContent:'center'}});
