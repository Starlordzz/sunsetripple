import SwiftUI

public struct RoomView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var session: IosRoomSession

    let isHost: Bool
    let isNight: Bool

    public init(nickname: String, isHost: Bool, isNight: Bool) {
        self.isHost = isHost
        self.isNight = isNight
        _session = StateObject(wrappedValue: IosRoomSession(nickname: nickname))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部栏
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isHost ? "落日对讲房 (房主)" : "落日对讲房 (成员)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(isNight ? Color(hex: "E4EBF4") : Color(hex: "2A2225"))
                    Text("当前用户: \(session.selfNickname)")
                        .font(.system(size: 13))
                        .foregroundColor(isNight ? Color(hex: "8FA2BC") : Color(hex: "6E625E"))
                }

                Spacer()

                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text("通话中")
                        .font(.system(size: 13))
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Spacer()

            // 2. 中间 PTT 大按键
            ZStack {
                // 动态波纹
                Circle()
                    .fill((isNight ? Color(hex: "3F76AC") : Color(hex: "9B4A52")).opacity(session.pttPressed ? 0.25 : 0.08))
                    .frame(width: session.pttPressed ? 210 : 170, height: session.pttPressed ? 210 : 170)
                    .animation(.easeInOut(duration: 0.18), value: session.pttPressed)

                Circle()
                    .fill(session.pttPressed
                        ? (isNight ? Color(hex: "3F76AC") : Color(hex: "9B4A52"))
                        : (isNight ? Color(hex: "182437") : Color(hex: "FCFAF7")))
                    .frame(width: 150, height: 150)
                    .overlay(
                        Circle().stroke(
                            session.pttPressed
                                ? (isNight ? Color(hex: "93B8DF") : Color(hex: "C9A163"))
                                : (isNight ? Color(hex: "33485F") : Color(hex: "D5C5BD")),
                            lineWidth: 2
                        )
                    )
                    .shadow(radius: 12)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in session.setPtt(pressed: true) }
                            .onEnded { _ in session.setPtt(pressed: false) }
                    )

                VStack(spacing: 6) {
                    Text(session.pttPressed ? "正在讲话..." : "按住说话")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(session.pttPressed ? .white : (isNight ? Color(hex: "E4EBF4") : Color(hex: "2A2225")))

                    Text(session.pttPressed ? "松手收听" : "PTT 对讲")
                        .font(.system(size: 12))
                        .foregroundColor(session.pttPressed ? Color.white.opacity(0.8) : (isNight ? Color(hex: "8FA2BC") : Color(hex: "6E625E")))
                }
            }

            Spacer()

            // 3. 底部控制栏
            HStack(spacing: 24) {
                // 静音
                Button(action: { session.toggleMute() }) {
                    Text(session.isMicMuted ? "已静音" : "静音")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isNight ? Color(hex: "E4EBF4") : Color(hex: "2A2225"))
                        .frame(width: 80, height: 44)
                        .background(session.isMicMuted ? (isNight ? Color(hex: "33485F") : Color(hex: "D5C5BD")) : (isNight ? Color(hex: "182437") : Color(hex: "FCFAF7")))
                        .cornerRadius(22)
                }

                // 扬声器
                Button(action: { session.isSpeakerOn.toggle() }) {
                    Text(session.isSpeakerOn ? "扬声器" : "听筒")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isNight ? Color(hex: "E4EBF4") : Color(hex: "2A2225"))
                        .frame(width: 80, height: 44)
                        .background(isNight ? Color(hex: "182437") : Color(hex: "FCFAF7"))
                        .cornerRadius(22)
                }

                // 离开房间
                Button(action: {
                    session.leave()
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("离开")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isNight ? Color(hex: "FF7B92") : Color(hex: "FF9E90"))
                        .frame(width: 80, height: 44)
                        .background((isNight ? Color(hex: "FF7B92") : Color(hex: "FF9E90")).opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .stroke((isNight ? Color(hex: "FF7B92") : Color(hex: "FF9E90")).opacity(0.62), lineWidth: 1)
                        )
                        .cornerRadius(22)
                }
            }
            .padding(.bottom, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isNight ? Color(hex: "0E1626") : Color(hex: "F4F1EC"))
        .onAppear {
            session.start(isHost: isHost)
        }
        .onDisappear {
            session.leave()
        }
        .navigationBarHidden(true)
    }
}

