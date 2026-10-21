// Exact package resource allowlist. Unknown requests never fall through to the network.
export const webAssets: Map<string, string> = new Map<string, string>([
  ["/测试页/index.html", "www/测试页/index.html"],
  ["/assets/app.js", "www/assets/app.js"],
  ["/assets/panda.png", "www/assets/panda.png"],
  ["/assets/style.css", "www/assets/style.css"],
  ["/index.html", "www/index.html"],
]);
export function mimeFor(path: string): string {
  const extension: string = path.substring(path.lastIndexOf('.') + 1).toLowerCase();
  const types: Map<string, string> = new Map<string, string>([
    ['html','text/html'],['htm','text/html'],['js','text/javascript'],['mjs','text/javascript'],
    ['css','text/css'],['json','application/json'],['txt','text/plain'],['svg','image/svg+xml'],
    ['png','image/png'],['jpg','image/jpeg'],['jpeg','image/jpeg'],['gif','image/gif'],
    ['webp','image/webp'],['ico','image/x-icon'],['wasm','application/wasm'],
    ['woff','font/woff'],['woff2','font/woff2'],['pdf','application/pdf'],
    ['mp4','video/mp4'],['mp3','audio/mpeg'],['map','application/json']
  ]);
  return types.get(extension) ?? 'application/octet-stream';
}
