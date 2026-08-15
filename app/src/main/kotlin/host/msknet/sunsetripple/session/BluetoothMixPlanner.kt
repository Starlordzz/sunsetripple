package host.msknet.sunsetripple.session

import host.msknet.sunsetripple.audio.Mixer

data class BluetoothMixPlan(
    val hostPlayback: ShortArray,
    val downlinks: Map<Int, ShortArray>,
)

/** 蓝牙星型主机的一帧混音规划：本地听所有远端，每位成员听除自己外的声音。 */
object BluetoothMixPlanner {
    fun plan(
        memberIds: Set<Int>,
        remotePcm: Map<Int, ShortArray>,
        hostPcm: ShortArray?,
        frameSamples: Int,
    ): BluetoothMixPlan {
        require(frameSamples > 0) { "frameSamples 必须大于 0" }
        require(remotePcm.values.all { it.size == frameSamples }) { "远端 PCM 帧长不一致" }
        require(hostPcm == null || hostPcm.size == frameSamples) { "主机 PCM 帧长不一致" }

        fun mixOrSilence(frames: List<ShortArray>): ShortArray =
            if (frames.isEmpty()) ShortArray(frameSamples) else Mixer.mix(frames)

        val hostPlayback = mixOrSilence(remotePcm.values.toList())
        val downlinks = memberIds.associateWith { recipientId ->
            val frames = buildList {
                hostPcm?.let(::add)
                remotePcm.forEach { (senderId, pcm) -> if (senderId != recipientId) add(pcm) }
            }
            mixOrSilence(frames)
        }
        return BluetoothMixPlan(hostPlayback, downlinks)
    }
}
