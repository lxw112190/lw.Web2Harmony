import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

export class RuntimeLog {
  private static directory: string = '';
  private static readonly maxBytes: number = 2 * 1024 * 1024;
  private static readonly archives: number = 5;
  static initialize(filesDir: string): void {
    RuntimeLog.directory = filesDir + '/logs';
    try { if (!fs.accessSync(RuntimeLog.directory)) { fs.mkdirSync(RuntimeLog.directory); } }
    catch { hilog.warn(0x0000, 'Web2Harmony', 'Cannot create log directory'); }
  }
  static localTime(): string {
    const now: Date = new Date();
    const offset: number = -now.getTimezoneOffset();
    return now.getFullYear().toString() + '-' + RuntimeLog.pad(now.getMonth()+1) + '-' +
      RuntimeLog.pad(now.getDate()) + ' ' + RuntimeLog.pad(now.getHours()) + ':' +
      RuntimeLog.pad(now.getMinutes()) + ':' + RuntimeLog.pad(now.getSeconds()) + '.' +
      now.getMilliseconds().toString().padStart(3, '0') + ' ' + (offset >= 0 ? '+' : '-') +
      RuntimeLog.pad(Math.floor(Math.abs(offset)/60)) + ':' + RuntimeLog.pad(Math.abs(offset)%60);
  }
  private static pad(n: number): string { return n.toString().padStart(2,'0'); }
  static safeUrl(value: string): string {
    return value.split(/[?#]/)[0].replace(/(https?:\/\/)[^/@]+@/gi, '$1[redacted]@');
  }
  static redact(value: string): string {
    return value.replace(/(https?:\/\/[^\s"'<>]+)/gi, (url: string): string => RuntimeLog.safeUrl(url))
      .replace(/((?:authorization|proxy-authorization|cookie|set-cookie)\s*[:=]\s*)[^\r\n]+/gi, '$1[redacted]')
      .replace(/(["']?(?:password|passwd|token|access_token|refresh_token|secret|api[_-]?key)["']?\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^\s,;}]+)/gi, '$1[redacted]')
      .substring(0, 8192);
  }
  private static rotate(path: string, incoming: number): void {
    if (!fs.accessSync(path) || fs.statSync(path).size + incoming <= RuntimeLog.maxBytes) { return; }
    const oldest: string = path + '.' + RuntimeLog.archives.toString();
    if (fs.accessSync(oldest)) { fs.unlinkSync(oldest); }
    for (let i: number = RuntimeLog.archives - 1; i >= 1; i--) {
      const source: string = path + '.' + i.toString();
      if (fs.accessSync(source)) { fs.renameSync(source, path + '.' + (i+1).toString()); }
    }
    fs.renameSync(path,path+'.1');
  }
  static write(level: string, message: string, fileName: string = 'runtime.log'): void {
    const safe: string = RuntimeLog.redact(message);
    hilog.info(0x0000, 'Web2Harmony', '%{public}s', '['+level+'] '+safe);
    if (RuntimeLog.directory.length === 0) { return; }
    let file: fs.File | undefined = undefined;
    try {
      const path: string = RuntimeLog.directory + '/' + fileName;
      const line: string = RuntimeLog.localTime() + ' [' + level + '] ' + safe + '\n';
      RuntimeLog.rotate(path,line.length * 4);
      file = fs.openSync(path,fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.APPEND);
      fs.writeSync(file.fd,line);
    } catch { hilog.warn(0x0000,'Web2Harmony','File logging unavailable'); }
    finally { if (file !== undefined) { try { fs.closeSync(file); } catch {} } }
  }
  static info(text: string): void { RuntimeLog.write('INFO',text); }
  static error(text: string): void { RuntimeLog.write('ERROR',text); }
  static debug(text: string): void { RuntimeLog.write('DEBUG',text); }
  static directoryPath(): string { return RuntimeLog.directory; }
}
