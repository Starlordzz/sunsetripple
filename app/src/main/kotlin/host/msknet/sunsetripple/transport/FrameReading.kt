package host.msknet.sunsetripple.transport

import host.msknet.sunsetripple.protocol.Frame
import host.msknet.sunsetripple.protocol.FrameStreamReader

/**
 * 接收循环专用的安全读帧：断流、载荷越界、未知帧类型（[Frame.decode] 抛 IllegalArgumentException）
 * 一律返回 null，由调用方按"协议错误 = 断开该对端"处理，避免异常穿透打死接收线程。
 */
fun FrameStreamReader.readFrameSafely(): Frame? = try {
    readFrame()
} catch (e: IllegalArgumentException) {
    TransportLog.w("协议错误，断开该对端: ${e.message}", e)
    null
}
