package host.msknet.sunsetripple.transport.bluetooth

import host.msknet.sunsetripple.protocol.Frame
import host.msknet.sunsetripple.protocol.FrameType
import java.util.ArrayDeque

internal class BluetoothSendQueue(
    private val audioCapacity: Int = 3,
) {
    private val lock = Object()
    private val frames = ArrayDeque<Frame>()
    private var closed = false

    init {
        require(audioCapacity > 0) { "audioCapacity 必须大于 0" }
    }

    fun offer(frame: Frame) = synchronized(lock) {
        if (closed) return@synchronized
        if (frame.type == FrameType.AUDIO && queuedAudioCount() >= audioCapacity) {
            val iterator = frames.iterator()
            while (iterator.hasNext()) {
                if (iterator.next().type == FrameType.AUDIO) {
                    iterator.remove()
                    break
                }
            }
        }
        frames.addLast(frame)
        lock.notifyAll()
    }

    fun take(): Frame? = synchronized(lock) {
        while (frames.isEmpty() && !closed) {
            lock.wait()
        }
        frames.pollFirst()
    }

    fun close() = synchronized(lock) {
        closed = true
        lock.notifyAll()
    }

    private fun queuedAudioCount(): Int = frames.count { it.type == FrameType.AUDIO }
}
