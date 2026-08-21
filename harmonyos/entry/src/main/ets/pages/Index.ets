import router from '@ohos.router';
import promptAction from '@ohos.promptAction';

@Entry
@Component
struct Index {
  @State nickname: string = '鸿蒙探索者';
  @State isNight: boolean = false;

  build() {
    Column() {
      // 1. 顶部落日/月海艺术横幅
      Stack({ alignContent: Alignment.Center }) {
        // 天体（太阳/月亮）
        Circle({ width: 120, height: 120 })
          .fill(this.isNight ? '#E9EEF7' : '#F3DCAA')
          .shadow({ radius: 30, color: this.isNight ? '#40E9EEF7' : '#50F3DCAA' })

        // 艺术水波纹
        Column({ space: 8 }) {
          Line().width('60%').height(2).stroke(this.isNight ? '#33485F' : '#D5C5BD')
          Line().width('45%').height(2).stroke(this.isNight ? '#33485F' : '#D5C5BD')
          Line().width('30%').height(2).stroke(this.isNight ? '#33485F' : '#D5C5BD')
        }
        .margin({ top: 110 })
      }
      .width('100%')
      .height(260)
      .linearGradient({
        direction: GradientDirection.Bottom,
        colors: this.isNight
          ? [['#3C5A8C', 0.0], ['#24395F', 0.5], ['#101A2E', 1.0]]
          : [['#C97C66', 0.0], ['#9B4A52', 0.5], ['#392832', 1.0]]
      })

      // 2. 主体操作区
      Column({ space: 24 }) {
        Text('落日后残波')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.isNight ? '#E4EBF4' : '#2A2225')

        Text('夕阳已远，涟漪未散，犹诉未尽之言。')
          .fontSize(14)
          .fontColor(this.isNight ? '#8FA2BC' : '#6E625E')

        // 昵称输入框
        TextInput({ text: this.nickname, placeholder: '请输入您的对讲昵称' })
          .width('85%')
          .height(50)
          .backgroundColor(this.isNight ? '#182437' : '#FCFAF7')
          .fontColor(this.isNight ? '#E4EBF4' : '#2A2225')
          .borderRadius(12)
          .border({ width: 1, color: this.isNight ? '#33485F' : '#D5C5BD' })
          .onChange((val) => { this.nickname = val; })

        // 操作按钮组
        Row({ space: 16 }) {
          Button('创建房间')
            .width('40%')
            .height(52)
            .backgroundColor(this.isNight ? '#3F76AC' : '#9B4A52')
            .fontColor('#FFFFFF')
            .borderRadius(26)
            .shadow({ radius: 12, color: this.isNight ? '#403F76AC' : '#409B4A52' })
            .onClick(() => {
              router.pushUrl({
                url: 'pages/RoomPage',
                params: { nickname: this.nickname, isHost: true }
              });
            })

          Button('加入房间')
            .width('40%')
            .height(52)
            .backgroundColor(this.isNight ? '#2A5A6E' : '#C97C66')
            .fontColor('#FFFFFF')
            .borderRadius(26)
            .shadow({ radius: 12, color: this.isNight ? '#402A5A6E' : '#40C97C66' })
            .onClick(() => {
              router.pushUrl({
                url: 'pages/RoomPage',
                params: { nickname: this.nickname, isHost: false }
              });
            })
        }
        .margin({ top: 12 })
      }
      .width('100%')
      .padding({ top: 32, bottom: 32 })
      .layoutWeight(1)
      .backgroundColor(this.isNight ? '#0E1626' : '#F4F1EC')
    }
    .width('100%')
    .height('100%')
  }
}

