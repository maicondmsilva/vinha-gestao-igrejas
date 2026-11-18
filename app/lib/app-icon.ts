/** Confere um PNG quadrado de 1024 px direto no arquivo enviado (não confia no navegador). */
export function iconOk(bytes: Uint8Array) {
  const sig = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (bytes.length < 33 || bytes.length > 1024 * 1024 || sig.some((b, i) => bytes[i] !== b)) return false;
  const v = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  return String.fromCharCode(...bytes.slice(12, 16)) === 'IHDR' && v.getUint32(16) === 1024 && v.getUint32(20) === 1024;
}
