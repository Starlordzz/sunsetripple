import SwiftUI

public struct ContentView: View {
    @State private var nickname: String = "iOS 探索者"
    @State private var isNight: Bool = false
    @State private var activeRoomHost: Bool? = nil

    public init() {}

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 1. 顶部落日/月海艺术渐变
                ZStack {
                    LinearGradient(
                        colors: isNight
                            ? [Color(hex: "3C5A8C"), Color(hex: "24395F"), Color(hex: "101A2E")]
                            : [Color(hex: "C97C66"), Color(hex: "9B4A52"), Color(hex: "392832")],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    // 太阳 / 月亮
                    Circle()
                        .fill(isNight ? Color(hex: "E9EEF7") : Color(hex: "F3DCAA"))
                        .frame(width: 110, height: 110)
                        .shadow(color: (isNight ? Color.white : Color(hex: "F3DCAA")).opacity(0.4), radius: 24)
                }
                .frame(height: 250)
                .edgesIgnoringSafeArea(.top)

                // 2. 主体操作区
                VStack(spacing: 22) {
                    Text("落日后残波")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(isNight ? Color(hex: "E4EBF4") : Color(hex: "2A2225"))

                    Text("夕阳已远，涟漪未散，犹诉未尽之言。")
                        .font(.system(size: 14))
                        .foregroundColor(isNight ? Color(hex: "8FA2BC") : Color(hex: "6E625E"))

                    // 昵称输入
                    TextField("请输入对讲昵称", text: $nickname)
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                        .background(isNight ? Color(hex: "182437") : Color(hex: "FCFAF7"))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isNight ? Color(hex: "33485F") : Color(hex: "D5C5BD"), lineWidth: 1)
                        )
                        .padding(.horizontal, 32)
                        .foregroundColor(isNight ? Color.white : Color.black)

                    // 按钮组
                    HStack(spacing: 16) {
                        Button(action: { activeRoomHost = true }) {
                            Text("创建房间")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(isNight ? Color(hex: "3F76AC") : Color(hex: "9B4A52"))
                                .cornerRadius(25)
                        }

                        Button(action: { activeRoomHost = false }) {
                            Text("加入房间")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(isNight ? Color(hex: "2A5A6E") : Color(hex: "C97C66"))
                                .cornerRadius(25)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 10)

                    Spacer()
                }
                .padding(.top, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(isNight ? Color(hex: "0E1626") : Color(hex: "F4F1EC"))
            }
            .background(
                NavigationLink(
                    destination: RoomView(nickname: nickname, isHost: activeRoomHost ?? true, isNight: isNight),
                    isActive: Binding(
                        get: { activeRoomHost != nil },
                        set: { if !$0 { activeRoomHost = nil } }
                    )
                ) { EmptyView() }
            )
            .navigationBarHidden(true)
        }
    }
}

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

