import { UIAbility, Want, AbilityConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { RuntimeLog } from '../common/RuntimeLog';
import { AppConfig } from '../common/AppConfig';
import { recordDeviceInfo } from '../common/DeviceInfo';

export default class EntryAbility extends UIAbility {
  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    RuntimeLog.initialize(this.context.filesDir);
    RuntimeLog.info('Activity created');
    recordDeviceInfo();
  }
  onWindowStageCreate(stage: window.WindowStage): void {
    RuntimeLog.info('Window stage created');
    stage.loadContent('pages/Index', (error) => {
      if (error.code) { RuntimeLog.error('loadContent failed: '+error.message); }
    });
    stage.getMainWindow().then((mainWindow: window.Window) => {
      mainWindow.setWindowLayoutFullScreen(AppConfig.fullscreen).catch(() => {
        RuntimeLog.error('Cannot apply fullscreen setting');
      });
    }).catch(() => { RuntimeLog.error('Cannot access main window'); });
  }
  onForeground(): void { RuntimeLog.info('Activity foreground'); }
  onBackground(): void { RuntimeLog.info('Activity background'); }
  onDestroy(): void { RuntimeLog.info('Activity destroyed'); }
}
