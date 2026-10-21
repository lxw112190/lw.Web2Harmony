import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { AppConfig } from '../common/AppConfig';
import { RuntimeLog } from '../common/RuntimeLog';
import { webAssets, mimeFor } from '../common/WebAssets';

@Entry
@Component
struct Index {
  private controller: webview.WebviewController = new webview.WebviewController();
  @State private message: string = '';
  private blocked(url: string): boolean {
    return (!AppConfig.allowHttp && url.startsWith('http://')) ||
      (!url.startsWith('https://') && !url.startsWith('http://') && url !== 'about:blank');
  }
  aboutToAppear(): void {
    RuntimeLog.info('WebView viewport: wide=true, overview=true; Allow HTTP='+AppConfig.allowHttp.toString());
    RuntimeLog.info('Loading start page: '+RuntimeLog.safeUrl(AppConfig.startUrl));
  }
  onBackPress(): boolean {
    if (this.controller.accessBackward()) { this.controller.backward(); return true; }
    return false;
  }
  private async exportLogs(): Promise<void> {
    let source: fs.File | undefined = undefined;
    let target: fs.File | undefined = undefined;
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const chooser: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.newFileNames = ['web2harmony-diagnostics.txt'];
      const uris: Array<string> = await chooser.save(options);
      if (uris.length === 0) { return; }
      target = fs.openSync(uris[0],fs.OpenMode.READ_WRITE);
      for (const name of ['device-info.log','runtime.log']) {
        for (let archive: number = 5; archive >= 0; archive--) {
          const path: string = RuntimeLog.directoryPath()+'/'+name+(archive > 0 ? '.'+archive.toString() : '');
          if (!fs.accessSync(path)) { continue; }
          fs.writeSync(target.fd,'\n--- '+name+(archive>0?'.'+archive.toString():'')+' ---\n');
          source = fs.openSync(path,fs.OpenMode.READ_ONLY);
          const buffer: ArrayBuffer = new ArrayBuffer(65536);
          let count: number = fs.readSync(source.fd,buffer);
          while (count > 0) {
            fs.writeSync(target.fd,buffer,{length:count});
            count = fs.readSync(source.fd,buffer);
          }
          fs.closeSync(source);
          source = undefined;
        }
      }
      this.message = '日志已导出';
    } catch { this.message = '日志导出失败'; RuntimeLog.error('Diagnostics export failed'); }
    finally {
      if (source !== undefined) { try { fs.closeSync(source); } catch {} }
      if (target !== undefined) { try { fs.closeSync(target); } catch {} }
    }
  }
  build() {
    Column() {
      Row() {
        Text(this.message).fontSize(12).layoutWeight(1)
        Button('导出诊断日志').fontSize(12).onClick(() => { this.exportLogs(); })
      }.padding(6).width('100%')
      Web({src:AppConfig.startUrl,controller:this.controller})
        .layoutWeight(1).width('100%')
        .javaScriptAccess(true).domStorageAccess(true)
        .fileAccess(false).wideViewModeAccess(true).overviewModeAccess(true)
        .mixedMode(AppConfig.allowHttp ? MixedMode.All : MixedMode.None)
        .onLoadIntercept((event) => {
          if (!event) { return false; }
          const url: string = event.data.getRequestUrl();
          if (this.blocked(url)) {
            RuntimeLog.write('WARN','Navigation blocked: '+RuntimeLog.safeUrl(url));
            this.message = '已阻止不支持或未允许的链接';
            return true;
          }
          return false;
        })
        .onInterceptRequest((event) => {
          if (!event) { return null; }
          const url: string = event.request.getRequestUrl();
          if (AppConfig.mode === 'local' && url.startsWith(AppConfig.origin+'/')) {
            const response: WebResourceResponse = new WebResourceResponse();
            let key: string = '';
            try { key = decodeURIComponent(url.substring(AppConfig.origin.length).split(/[?#]/)[0]); }
            catch { key = ''; }
            const raw: string | undefined = webAssets.get(key);
            if (raw !== undefined) {
              response.setResponseData($rawfile(raw));
              response.setResponseMimeType(mimeFor(raw));
              response.setResponseEncoding('utf-8');
              response.setResponseCode(200);
              response.setReasonMessage('OK');
            } else {
              response.setResponseData('Not found');
              response.setResponseMimeType('text/plain');
              response.setResponseCode(404);
              response.setReasonMessage('Not Found');
              RuntimeLog.write('WARN','Local resource missing: '+RuntimeLog.safeUrl(url));
            }
            response.setResponseIsReady(true);
            return response;
          }
          if (this.blocked(url)) {
            const denied: WebResourceResponse = new WebResourceResponse();
            denied.setResponseData('Blocked');
            denied.setResponseCode(403);
            denied.setReasonMessage('Forbidden');
            denied.setResponseIsReady(true);
            RuntimeLog.write('WARN','Resource blocked: '+RuntimeLog.safeUrl(url));
            return denied;
          }
          return null;
        })
        .onPageBegin((event) => { if (event) { RuntimeLog.info('Page started: '+RuntimeLog.safeUrl(event.url)); } })
        .onPageEnd((event) => {
          if (event) { RuntimeLog.info('Page finished: '+RuntimeLog.safeUrl(event.url)); }
          this.controller.runJavaScript(
            'JSON.stringify({innerWidth:innerWidth,innerHeight:innerHeight,scrollWidth:document.documentElement.scrollWidth,dpr:devicePixelRatio})',
            (error,result) => { if (!error.code) { RuntimeLog.debug('Web viewport: '+result); } });
        })
        .onConsole((event) => {
          if (event) { RuntimeLog.debug('Web Console: '+event.message.getMessage()); }
          return false;
        })
        .onErrorReceive((event) => {
          if (event) {
            RuntimeLog.error('WebResourceError: '+event.error.getErrorInfo()+'; url='+RuntimeLog.safeUrl(event.request.getRequestUrl()));
            this.message = '页面加载失败，请导出诊断日志';
          }
        })
        .onHttpErrorReceive((event) => {
          if (event) { RuntimeLog.error('HTTP Error: '+event.response.getResponseCode().toString()+
            '; url='+RuntimeLog.safeUrl(event.request.getRequestUrl())); }
        })
    }.width('100%').height('100%')
  }
}
