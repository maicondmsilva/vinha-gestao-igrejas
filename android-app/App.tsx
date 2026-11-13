import {SafeAreaProvider} from 'react-native-safe-area-context';
import MprApp from './src/MprApp';
/** Área segura do sistema (barra de status e barra de navegação do Android) para todas as telas. */
export default function App() {
  return (
    <SafeAreaProvider>
      <MprApp />
    </SafeAreaProvider>
  );
}
