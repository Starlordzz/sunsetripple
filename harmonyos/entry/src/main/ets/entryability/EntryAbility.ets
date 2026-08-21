import UIAbility from '@ohos.app.ability.UIAbility';
import window from '@ohos.window';
import hilog from '@ohos.hilog';

export default class EntryAbility extends UIAbility {
  onCreate(want, launchParam) {
    hilog.info(0x0000, 'SunsetRipple', 'Ability onCreate');
  }

  onDestroy() {
    hilog.info(0x0000, 'SunsetRipple', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage) {
    hilog.info(0x0000, 'SunsetRipple', 'Ability onWindowStageCreate');
    windowStage.loadContent('pages/Index', (err, data) => {
      if (err.code) {
        hilog.error(0x0000, 'SunsetRipple', `Failed to load content: ${JSON.stringify(err)}`);
        return;
      }
      hilog.info(0x0000, 'SunsetRipple', 'Succeeded in loading content');
    });
  }

  onWindowStageDestroy() {
    hilog.info(0x0000, 'SunsetRipple', 'Ability onWindowStageDestroy');
  }

  onForeground() {
    hilog.info(0x0000, 'SunsetRipple', 'Ability onForeground');
  }

  onBackground() {
    hilog.info(0x0000, 'SunsetRipple', 'Ability onBackground');
  }
}

