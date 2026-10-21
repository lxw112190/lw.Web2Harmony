import { deviceInfo } from '@kit.BasicServicesKit';
import { display } from '@kit.ArkUI';
import { AppConfig } from './AppConfig';
import { RuntimeLog } from './RuntimeLog';
export function recordDeviceInfo(): void {
  RuntimeLog.write('INFO','Session start; Time UTC: '+new Date().toISOString(),'device-info.log');
  RuntimeLog.write('INFO','App: '+AppConfig.appName+'; bundle='+AppConfig.bundleName+
    '; version='+AppConfig.version+'; runtime='+AppConfig.runtimeVersion,'device-info.log');
  RuntimeLog.write('INFO','Manufacturer='+deviceInfo.manufacture+'; model='+deviceInfo.productModel+
    '; OS='+deviceInfo.osFullName+'; API='+deviceInfo.sdkApiVersion.toString()+
    '; ABI='+deviceInfo.abiList,'device-info.log');
  RuntimeLog.write('INFO','Mode='+AppConfig.mode+'; start='+RuntimeLog.safeUrl(AppConfig.startUrl)+
    '; Allow HTTP='+AppConfig.allowHttp.toString()+'; fullscreen='+AppConfig.fullscreen.toString()+
    '; orientation='+AppConfig.orientation+'; wide=true; overview=true','device-info.log');
  try {
    const metrics: display.Display = display.getDefaultDisplaySync();
    RuntimeLog.write('INFO','Display: widthPx='+metrics.width.toString()+'; heightPx='+
      metrics.height.toString()+'; density='+metrics.densityPixels.toString()+
      '; densityDpi='+metrics.densityDPI.toString(),'device-info.log');
  } catch { RuntimeLog.info('Display metrics unavailable'); }
}
