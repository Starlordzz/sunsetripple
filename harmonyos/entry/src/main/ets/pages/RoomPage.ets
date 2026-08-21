import router from '@ohos.router';
import { HarmonyRoomSession } from '../session/HarmonyRoomSession';

@Entry
@Component
struct RoomPage {
  @State nickname: string = '鸿蒙探索者';
  @State isHost: boolean = true;
  @State isNight: boolean = false;
  @State pttPressed: boolean = false;
  @State isMuted: boolean = false;
  @State isSpeaker: boolean = true;

  private session: HarmonyRoomSession = new HarmonyRoomSession('鸿蒙探索者');

  aboutToAppear() {
    const params = router.getParams() as Record<string, Object>;
    if (params) {
      if (params['nickname']) this.nickname = params['nickname'] as string;
      if (params['isHost'] !== undefined) this.isHost = params['isHost'] as boolean;
    }
    this.session.selfNickname = this.nickname;
    this.session.start();
  }

  aboutToDisappear() {
    this.session.leave();
  }

  build() {
    Column() {
      // 1. 顶部房间信息
      Row() {
        Column() {
          Text(this.isHost ? '落日对讲房 (房主)' : '落日对讲房 (成员)')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.isNight ? '#E4EBF4' : '#2A2225')
          Text(`当前用户: ${this.nickname}`)
            .fontSize(13)
            .fontColor(this.isNight ? '#8FA2BC' : '#6E625E')
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)

        Blank()

        // 状态指示
        Row({ space: 6 }) {
          Circle({ width: 8, height: 8 }).fill('#4CAF50')
          Text('通话中')
            .fontSize(13)
            .fontColor('#4CAF50')
        }
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 20, bottom: 20 })

      // 2. 中间：PTT 大圆盘
      Column() {
        Stack({ alignContent: Alignment.Center }) {
          // 发言动态光环
          Circle({ width: this.pttPressed ? 200 : 160, height: this.pttPressed ? 200 : 160 })
            .fill(this.isNight ? '#203F76AC' : '#209B4A52')
            .animation({ duration: 180, curve: Curve.EaseInOut })

          // PTT 主体圆盘
          Circle({ width: 150, height: 150 })
            .fill(this.pttPressed
              ? (this.isNight ? '#3F76AC' : '#9B4A52')
              : (this.isNight ? '#182437' : '#FCFAF7'))
            .border({
              width: 2,
              color: this.pttPressed
                ? (this.isNight ? '#93B8DF' : '#C9A163')
                : (this.isNight ? '#33485F' : '#D5C5BD')
            })
            .shadow({ radius: 16, color: '#20000000' })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                this.pttPressed = true;
                this.session.setPttPressed(true);
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.pttPressed = false;
                this.session.setPttPressed(false);
              }
            })

          // 图标与文字
          Column({ space: 8 }) {
            Text(this.pttPressed ? '正在讲话...' : '按住说话')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.pttPressed
                ? '#FFFFFF'
                : (this.isNight ? '#E4EBF4' : '#2A2225'))
            Text(this.pttPressed ? '松手收听' : 'PTT 对讲')
              .fontSize(12)
              .fontColor(this.pttPressed
                ? '#E0E0E0'
                : (this.isNight ? '#8FA2BC' : '#6E625E'))
          }
        }
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)

      // 3. 底部控制栏
      Row({ space: 24 }) {
        // 静音按钮
        Button(this.isMuted ? '已静音' : '静音')
          .height(44)
          .backgroundColor(this.isMuted ? (this.isNight ? '#33485F' : '#D5C5BD') : (this.isNight ? '#182437' : '#FCFAF7'))
          .fontColor(this.isNight ? '#E4EBF4' : '#2A2225')
          .borderRadius(22)
          .onClick(() => {
            this.isMuted = !this.isMuted;
            this.session.toggleMute();
          })

        // 扬声器
        Button(this.isSpeaker ? '扬声器' : '听筒')
          .height(44)
          .backgroundColor(this.isNight ? '#182437' : '#FCFAF7')
          .fontColor(this.isNight ? '#E4EBF4' : '#2A2225')
          .borderRadius(22)
          .onClick(() => {
            this.isSpeaker = !this.isSpeaker;
          })

        // 离开按钮（采用夜间玫瑰粉 / 日间暖珊瑚）
        Button('离开')
          .height(44)
          .backgroundColor(this.isNight ? '#20FF7B92' : '#20FF9E90')
          .fontColor(this.isNight ? '#FF7B92' : '#FF9E90')
          .border({ width: 1, color: this.isNight ? '#A0FF7B92' : '#A0FF9E90' })
          .borderRadius(22)
          .onClick(() => {
            this.session.leave();
            router.back();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ bottom: 36, top: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.isNight ? '#0E1626' : '#F4F1EC')
  }
}

