package host.msknet.sunsetripple.transport

import host.msknet.sunsetripple.protocol.Frame
import host.msknet.sunsetripple.session.RosterCodec
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction

data class TransferCandidate(
    val memberId: Int,
    val joinOrder: Long,
    val nickname: String,
    val endpoint: String,
    val connected: Boolean,
)

data class HostTransferMember(
    val memberId: Int,
    val joinOrder: Long,
    val nickname: String,
    val endpoint: String,
)

data class HostTransferPlan(
    val successorId: Int,
    val members: List<HostTransferMember>,
) {
    init {
        require(successorId in 1..255) { "继任成员 ID 越界: $successorId" }
        require(members.size in 1..MAX_MEMBERS) { "交接成员数越界: ${members.size}" }
        require(members.map { it.memberId }.distinct().size == members.size) { "交接成员 ID 重复" }
        require(members.map { it.endpoint.lowercase() }.distinct().size == members.size) { "交接成员端点重复" }
        require(members.map { it.joinOrder }.distinct().size == members.size) { "交接 joinOrder 重复" }
        require(members.any { it.memberId == successorId }) { "交接成员表不含继任者 $successorId" }
        members.forEach { member ->
            require(member.memberId in 1..255) { "交接成员 ID 越界: ${member.memberId}" }
            require(member.joinOrder >= 0) { "joinOrder 不能为负数" }
            require(member.endpoint.isNotBlank()) { "交接端点不能为空" }
        }
    }

    companion object {
        const val MAX_MEMBERS = 6
    }
}

object HostElection {
    fun select(candidates: List<TransferCandidate>): TransferCandidate? =
        candidates.asSequence()
            .filter { it.connected && it.endpoint.isNotBlank() }
            .minWithOrNull(compareBy<TransferCandidate> { it.joinOrder }.thenBy { it.memberId })

    fun plan(candidates: List<TransferCandidate>): HostTransferPlan? {
        val active = candidates
            .filter { it.connected && it.endpoint.isNotBlank() }
            .sortedWith(compareBy<TransferCandidate> { it.joinOrder }.thenBy { it.memberId })
        val successor = active.firstOrNull() ?: return null
        return HostTransferPlan(
            successorId = successor.memberId,
            members = active.map {
                HostTransferMember(it.memberId, it.joinOrder, it.nickname, it.endpoint)
            },
        )
    }
}

data class SeededTransferMember(
    val previousId: Int,
    val newId: Int,
    val joinOrder: Long,
    val nickname: String,
    val endpoint: String,
)

data class HostTransferSeed(
    val members: List<SeededTransferMember>,
    val nextJoinOrder: Long,
) {
    val host: SeededTransferMember get() = members.first()

    fun expectedByEndpoint(): Map<String, SeededTransferMember> =
        members.drop(1).associateBy { it.endpoint }

    companion object {
        fun from(plan: HostTransferPlan): HostTransferSeed {
            val ordered = plan.members.sortedWith(
                compareBy<HostTransferMember> { it.joinOrder }.thenBy { it.memberId },
            )
            val successor = ordered.first { it.memberId == plan.successorId }
            val remapped = buildList {
                add(successor.toSeeded(newId = 0))
                ordered.filterNot { it.memberId == plan.successorId }
                    .forEachIndexed { index, member -> add(member.toSeeded(newId = index + 1)) }
            }
            val maxOrder = ordered.maxOf { it.joinOrder }
            require(maxOrder < Long.MAX_VALUE) { "joinOrder 已耗尽" }
            return HostTransferSeed(remapped, maxOrder + 1)
        }

        private fun HostTransferMember.toSeeded(newId: Int) = SeededTransferMember(
            previousId = memberId,
            newId = newId,
            joinOrder = joinOrder,
            nickname = nickname,
            endpoint = endpoint,
        )
    }
}

object HostTransferCodec {
    private const val VERSION = 1

    fun encode(plan: HostTransferPlan): ByteArray {
        val bytes = ByteArrayOutputStream().also { buffer ->
            DataOutputStream(buffer).use { output ->
                output.writeByte(VERSION)
                output.writeByte(plan.successorId)
                output.writeByte(plan.members.size)
                plan.members.forEach { member ->
                    val nickname = RosterCodec.truncateNickname(member.nickname).toByteArray(Charsets.UTF_8)
                    val endpoint = member.endpoint.toAsciiBytes()
                    output.writeByte(member.memberId)
                    output.writeLong(member.joinOrder)
                    output.writeByte(nickname.size)
                    output.write(nickname)
                    output.writeByte(endpoint.size)
                    output.write(endpoint)
                }
            }
        }.toByteArray()
        require(bytes.size <= Frame.MAX_PAYLOAD) { "交接载荷超上限: ${bytes.size}" }
        return bytes
    }

    fun decode(payload: ByteArray): HostTransferPlan {
        require(payload.size <= Frame.MAX_PAYLOAD) { "交接载荷超上限: ${payload.size}" }
        val input = DataInputStream(ByteArrayInputStream(payload))
        require(input.available() >= 3) { "交接载荷字段不完整" }
        require(input.readUnsignedByte() == VERSION) { "不支持的交接版本" }
        val successorId = input.readUnsignedByte()
        val count = input.readUnsignedByte()
        require(count in 1..HostTransferPlan.MAX_MEMBERS) { "交接成员数越界: $count" }
        val members = ArrayList<HostTransferMember>(count)
        repeat(count) { index ->
            require(input.available() >= 11) { "交接成员 $index 字段不完整" }
            val memberId = input.readUnsignedByte()
            val joinOrder = input.readLong()
            val nickname = readUtf8(input, input.readUnsignedByte(), "交接成员 $index 昵称")
            require(input.available() >= 1) { "交接成员 $index 缺少端点长度" }
            val endpointLength = input.readUnsignedByte()
            require(endpointLength > 0) { "交接成员 $index 端点为空" }
            val endpointBytes = readBytes(input, endpointLength, "交接成员 $index 端点")
            require(endpointBytes.all { it.toInt() in 0..0x7F }) { "交接成员 $index 端点不是 ASCII" }
            members += HostTransferMember(
                memberId,
                joinOrder,
                nickname,
                String(endpointBytes, Charsets.US_ASCII),
            )
        }
        require(input.available() == 0) { "交接载荷尾部多余 ${input.available()} 字节" }
        return HostTransferPlan(successorId, members)
    }

    private fun readUtf8(input: DataInputStream, length: Int, field: String): String {
        val bytes = readBytes(input, length, field)
        return runCatching {
            Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes))
                .toString()
        }.getOrElse { throw IllegalArgumentException("$field 不是合法 UTF-8", it) }
    }

    private fun readBytes(input: DataInputStream, length: Int, field: String): ByteArray {
        require(input.available() >= length) { "$field 长度越界: $length" }
        return ByteArray(length).also(input::readFully)
    }

    private fun String.toAsciiBytes(): ByteArray {
        require(isNotBlank()) { "交接端点不能为空" }
        require(all { it.code in 1..0x7F }) { "交接端点必须为 ASCII" }
        return toByteArray(Charsets.US_ASCII).also {
            require(it.size <= 255) { "交接端点过长: ${it.size}" }
        }
    }
}
