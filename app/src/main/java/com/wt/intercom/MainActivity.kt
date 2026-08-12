package com.wt.intercom

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import androidx.core.location.LocationManagerCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.wt.intercom.audio.LoopbackController
import com.wt.intercom.service.CallForegroundService
import com.wt.intercom.session.RoomSession
import com.wt.intercom.session.RoomUiState
import com.wt.intercom.transport.TransportLog
import com.wt.intercom.transport.wifi.WifiClientTransport
import com.wt.intercom.transport.wifi.WifiDirectManager
import com.wt.intercom.transport.wifi.WifiHostTransport
import com.wt.intercom.ui.GroupInfo
import com.wt.intercom.ui.HomeScreen
import com.wt.intercom.ui.LoopbackScreen
import com.wt.intercom.ui.RoomFlow
import com.wt.intercom.ui.RoomPermissions
import com.wt.intercom.ui.RoomRole
import com.wt.intercom.ui.RoomScreen
import com.wt.intercom.ui.RoomStart
import com.wt.intercom.ui.ScanScreen
import com.wt.intercom.ui.Screen
import kotlin.concurrent.thread
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : ComponentActivity() {

    private lateinit var wifi: WifiDirectManager
    private val loopback = LoopbackController()

    /** 会话得让 Compose 观察得到（建/散都要触发重组），所以用 StateFlow 而不是裸字段。 */
    private val sessionFlow = MutableStateFlow<RoomSession?>(null)

    /** 通知栏「离开」按钮的请求计数：自增一次＝要求离房一次。 */
    private val leaveRequests = MutableStateFlow(0)

    /**
     * 与 Activity 同生命周期的作用域。断链监听不能挂在 Compose 里：
     * collectAsStateWithLifecycle 在后台会停收，而通话恰恰要在后台继续跑
     * （前台服务保活），房间死了却没人停机。
     */
    private val activityScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        wifi = WifiDirectManager(this)
        wifi.register()
        watchRoomDeath()
        handleLeaveIntent(intent)
        setContent { MaterialTheme { App() } }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleLeaveIntent(intent)
    }

    override fun onDestroy() {
        loopback.stop()
        releaseRoom()
        wifi.unregister()
        activityScope.cancel()
        super.onDestroy()
    }

    private fun handleLeaveIntent(intent: Intent?) {
        if (intent?.action == CallForegroundService.ACTION_LEAVE) {
            leaveRequests.value = leaveRequests.value + 1
        }
    }

    /**
     * P2P 组解散 / channel 断开 → 驱动会话停机。
     *
     * 组主侧的传输层没有任何 onDisconnected 路径（客户端走光也只是空房），
     * 这两个信号是那一侧仅有的房间死亡来源；缺了它，房主会对着死房间继续说话。
     */
    private fun watchRoomDeath() {
        activityScope.launch {
            combine(sessionFlow, wifi.connection, wifi.channelLost) { session, info, channelLost ->
                val group = info?.let {
                    GroupInfo(it.groupFormed, it.isGroupOwner, it.groupOwnerAddress?.hostAddress)
                }
                Triple(session, group, channelLost)
            }.collect { (session, group, channelLost) ->
                if (session == null) return@collect
                val reason =
                    RoomFlow.deathReason(sessionActive = true, group = group, channelLost = channelLost)
                        ?: return@collect
                TransportLog.w("P2P 组网中断，停机：$reason")
                // 停机要 join 播放线程，别压在主线程上。
                withContext(Dispatchers.Default) { session.onDisconnected(reason) }
            }
        }
    }

    /** 进房/离房时切换通信音频模式，保证 AEC 与音量路由正确。 */
    private fun setCommunicationMode(on: Boolean) {
        val am = getSystemService(AUDIO_SERVICE) as AudioManager
        am.mode = if (on) AudioManager.MODE_IN_COMMUNICATION else AudioManager.MODE_NORMAL
    }

    private fun setSpeaker(on: Boolean) {
        val am = getSystemService(AUDIO_SERVICE) as AudioManager
        @Suppress("DEPRECATION")
        am.isSpeakerphoneOn = on
    }

    /** 进房副作用：通信音频模式 + microphone 前台服务（服务内持 WifiLock/WakeLock）。 */
    private fun beginCall(label: String, speakerOn: Boolean) {
        setCommunicationMode(true)
        setSpeaker(speakerOn)
        CallForegroundService.start(this, label)
    }

    /** 释放房间：会话 → P2P 组 → 前台服务 → 音频模式。幂等，主线程调用。 */
    private fun releaseRoom() {
        val session = sessionFlow.value
        sessionFlow.value = null
        session?.let { runCatching { it.leave() }.onFailure { e -> TransportLog.w("离房异常: ${e.message}", e) } }
        wifi.disconnect()
        CallForegroundService.stop(this)
        setCommunicationMode(false)
    }

    /** Android 9~12 上定位服务关着时 WiFi Direct 扫描静默返回空列表。读不到开关状态就不拦人。 */
    private fun isLocationServiceEnabled(): Boolean = runCatching {
        LocationManagerCompat.isLocationEnabled(getSystemService(LOCATION_SERVICE) as LocationManager)
    }.getOrElse {
        TransportLog.w("读取定位服务开关失败: ${it.message}", it)
        true
    }

    /** 会话为空时退化成一条恒定的空状态流，免得条件式调用 Composable。 */
    @Composable
    private fun rememberRoomState(session: RoomSession?): RoomUiState {
        val flow: StateFlow<RoomUiState> =
            remember(session) { session?.state ?: MutableStateFlow(RoomUiState()) }
        return flow.collectAsStateWithLifecycle().value
    }

    @Composable
    private fun App() {
        val context = LocalContext.current
        val sdkInt = Build.VERSION.SDK_INT

        var screen by remember { mutableStateOf(Screen.HOME) }
        var nickname by remember { mutableStateOf(Build.MODEL?.take(8)?.trim().orEmpty().ifEmpty { "我" }) }
        var status by remember { mutableStateOf<String?>(null) }
        var role by remember { mutableStateOf(RoomRole.NONE) }
        var isHost by remember { mutableStateOf(false) }
        var speakerOn by remember { mutableStateOf(true) }
        var pendingAction by remember { mutableStateOf<(() -> Unit)?>(null) }

        val required = remember(sdkInt) { RoomPermissions.required(sdkInt) }
        val requested = remember(sdkInt) { RoomPermissions.requested(sdkInt).toTypedArray() }

        val connection by wifi.connection.collectAsStateWithLifecycle()
        val peers by wifi.peers.collectAsStateWithLifecycle()
        val wifiError by wifi.lastError.collectAsStateWithLifecycle()
        val session by sessionFlow.collectAsStateWithLifecycle()
        val leaveRequest by leaveRequests.collectAsStateWithLifecycle()
        val roomState = rememberRoomState(session)
        val group = connection?.let {
            GroupInfo(it.groupFormed, it.isGroupOwner, it.groupOwnerAddress?.hostAddress)
        }

        fun goHome(message: String?) {
            releaseRoom()
            role = RoomRole.NONE
            status = message
            screen = Screen.HOME
        }

        fun runWhenLocationReady(action: () -> Unit) {
            if (!RoomPermissions.needsLocationService(sdkInt) || isLocationServiceEnabled()) {
                action()
                return
            }
            status = RoomPermissions.LOCATION_SERVICE_OFF_HINT
            Toast.makeText(context, RoomPermissions.LOCATION_SERVICE_OFF_HINT, Toast.LENGTH_LONG).show()
        }

        val roomPermLauncher = rememberLauncherForActivityResult(
            ActivityResultContracts.RequestMultiplePermissions()
        ) { result ->
            val action = pendingAction
            pendingAction = null
            val denied = RoomPermissions.blockingDenied(result, sdkInt)
            if (denied.isEmpty()) {
                action?.let { runWhenLocationReady(it) }
            } else {
                val message = RoomPermissions.deniedMessage(denied)
                status = message
                Toast.makeText(context, message, Toast.LENGTH_LONG).show()
            }
        }

        val micPermLauncher = rememberLauncherForActivityResult(
            ActivityResultContracts.RequestPermission()
        ) { granted ->
            val action = pendingAction
            pendingAction = null
            if (granted) {
                action?.invoke()
            } else {
                status = "缺少麦克风权限，无法录音"
                Toast.makeText(context, "缺少麦克风权限，无法录音", Toast.LENGTH_LONG).show()
            }
        }

        /** 进房前置条件：权限齐 +（旧版本上）系统定位服务开着。 */
        fun withRoomPreconditions(action: () -> Unit) {
            val missing = required.any {
                ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED
            }
            if (missing) {
                pendingAction = action
                roomPermLauncher.launch(requested)
            } else {
                runWhenLocationReady(action)
            }
        }

        /** 回环自测只碰麦克风，不该被 WiFi 权限或定位开关挡住。 */
        fun withMicPermission(action: () -> Unit) {
            val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED
            if (granted) {
                action()
            } else {
                pendingAction = action
                micPermLauncher.launch(Manifest.permission.RECORD_AUDIO)
            }
        }

        fun startHost(hostIp: String) {
            val newSession = RoomSession(nickname)
            // 构造即绑端口，失败要让用户看见（8988/8989 被占）。
            val transport = try {
                WifiHostTransport(nickname, newSession, hostIp)
            } catch (e: Exception) {
                TransportLog.w("建房失败: ${e.message}", e)
                Toast.makeText(context, "建房失败：${e.message}", Toast.LENGTH_LONG).show()
                goHome("建房失败：${e.message}")
                return
            }
            sessionFlow.value = newSession
            isHost = true
            beginCall(HOST_LABEL, speakerOn)
            try {
                newSession.start(transport)
                transport.start()
            } catch (e: Exception) {
                TransportLog.w("房间启动失败: ${e.message}", e)
                runCatching { transport.close() }
                Toast.makeText(context, "房间启动失败：${e.message}", Toast.LENGTH_LONG).show()
                goHome("房间启动失败：${e.message}")
                return
            }
            status = null
            screen = Screen.ROOM
        }

        fun startGuest(hostIp: String) {
            val newSession = RoomSession(nickname)
            sessionFlow.value = newSession
            isHost = false
            status = "正在入房……"
            val nick = nickname
            val speaker = speakerOn
            // TCP 连接是阻塞的（5s 超时），不能占主线程。
            thread(name = "wifi-join") {
                val transport = try {
                    WifiClientTransport(nick, hostIp, newSession).also { it.start() }
                } catch (e: Exception) {
                    TransportLog.w("入房失败: ${e.message}", e)
                    runOnUiThread {
                        Toast.makeText(context, "入房失败：${e.message}", Toast.LENGTH_LONG).show()
                        goHome("入房失败：${e.message}")
                    }
                    return@thread
                }
                runOnUiThread {
                    // 用户可能在握手期间就退了：会话已被换掉就地收手，别把 socket 漏在外面。
                    if (sessionFlow.value !== newSession) {
                        runCatching { transport.close() }
                        return@runOnUiThread
                    }
                    beginCall(GUEST_LABEL, speaker)
                    try {
                        newSession.start(transport)
                    } catch (e: Exception) {
                        TransportLog.w("房间启动失败: ${e.message}", e)
                        runCatching { transport.close() }
                        Toast.makeText(context, "房间启动失败：${e.message}", Toast.LENGTH_LONG).show()
                        goHome("房间启动失败：${e.message}")
                        return@runOnUiThread
                    }
                    status = null
                    screen = Screen.ROOM
                }
            }
        }

        // 组建立 → 起会话。主客身份与组主地址一律取系统真值，不回落硬编码 IP。
        LaunchedEffect(group, role, session) {
            when (val start = RoomFlow.decide(group, role, session != null)) {
                RoomStart.Idle -> Unit
                RoomStart.AwaitingAddress -> status = "组已建立，正在获取组主地址……"
                is RoomStart.Host -> startHost(start.hostIp)
                is RoomStart.Guest -> startGuest(start.hostIp)
            }
        }

        // 会话结束（对端散会、断线、连续发送失败、P2P 组消失）→ 提示并回首页。
        LaunchedEffect(roomState.endedReason) {
            val reason = roomState.endedReason ?: return@LaunchedEffect
            Toast.makeText(context, reason, Toast.LENGTH_LONG).show()
            goHome(reason)
        }

        // 通知栏「离开」按钮。
        LaunchedEffect(leaveRequest) {
            if (leaveRequest > 0 && sessionFlow.value != null) goHome(null)
        }

        BackHandler(enabled = screen != Screen.HOME) {
            when (screen) {
                Screen.ROOM -> goHome(null)
                Screen.LOOPBACK -> {
                    loopback.stop()
                    screen = Screen.HOME
                }
                Screen.SCAN -> {
                    // 先清意图再断连：否则晚到的连接广播会把人硬拖进房间。
                    role = RoomRole.NONE
                    wifi.disconnect()
                    status = null
                    screen = Screen.HOME
                }
                Screen.HOME -> Unit
            }
        }

        when (screen) {
            Screen.HOME -> HomeScreen(
                nickname = nickname,
                onNicknameChange = { nickname = it.take(16) },
                onCreateWifiRoom = {
                    withRoomPreconditions {
                        role = RoomRole.HOST
                        status = "正在建房……"
                        wifi.createGroup()
                    }
                },
                onJoinWifiRoom = {
                    withRoomPreconditions {
                        role = RoomRole.GUEST
                        status = null
                        wifi.discoverPeers()
                        screen = Screen.SCAN
                    }
                },
                onLoopbackTest = {
                    withMicPermission {
                        runCatching { loopback.start() }
                            .onSuccess {
                                status = null
                                screen = Screen.LOOPBACK
                            }
                            .onFailure {
                                status = "回环启动失败：${it.message}"
                                Toast.makeText(context, "回环启动失败：${it.message}", Toast.LENGTH_LONG).show()
                            }
                    }
                },
                status = status ?: wifiError,
            )

            Screen.SCAN -> ScanScreen(
                peers = peers,
                status = status ?: wifiError ?: "扫描中……选择对方后手机会弹出连接确认",
                onPick = { device ->
                    status = "正在连接 ${device.deviceName.orEmpty().ifBlank { device.deviceAddress }}……"
                    wifi.connect(device)
                },
                onBack = {
                    role = RoomRole.NONE
                    wifi.disconnect()
                    status = null
                    screen = Screen.HOME
                },
            )

            Screen.ROOM -> RoomScreen(
                state = roomState,
                roomLabel = if (isHost) HOST_LABEL else GUEST_LABEL,
                speakerOn = speakerOn,
                onToggleMute = { session?.setMicMuted(!roomState.micMuted) },
                onToggleSpeaker = {
                    speakerOn = !speakerOn
                    setSpeaker(speakerOn)
                },
                onLeave = { goHome(null) },
            )

            Screen.LOOPBACK -> LoopbackScreen(
                onStop = {
                    loopback.stop()
                    screen = Screen.HOME
                },
            )
        }
    }

    private companion object {
        const val HOST_LABEL = "WiFi 房（我是房主）"
        const val GUEST_LABEL = "WiFi 房"
    }
}
