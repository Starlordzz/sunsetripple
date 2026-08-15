package com.wt.intercom

import android.Manifest
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
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
import com.wt.intercom.audio.AudioFocusController
import com.wt.intercom.audio.AudioFocusRequestState
import com.wt.intercom.service.CallForegroundService
import com.wt.intercom.service.ActiveCallControls
import com.wt.intercom.service.CallMode
import com.wt.intercom.service.CallNotificationState
import com.wt.intercom.session.RoomSession
import com.wt.intercom.session.RoomUiState
import com.wt.intercom.session.BluetoothRoomSession
import com.wt.intercom.transport.TransportLog
import com.wt.intercom.transport.HostTransferSeed
import com.wt.intercom.transport.bluetooth.BluetoothClientTransport
import com.wt.intercom.transport.bluetooth.BluetoothHostTransport
import com.wt.intercom.transport.bluetooth.BluetoothRoomManager
import com.wt.intercom.transport.nearby.NearbyEndpoint
import com.wt.intercom.transport.nearby.NearbyRoomManager
import com.wt.intercom.transport.nearby.NearbyRoomTransport
import com.wt.intercom.transport.wifi.WifiClientTransport
import com.wt.intercom.transport.wifi.WifiDirectManager
import com.wt.intercom.transport.wifi.WifiHostTransport
import com.wt.intercom.ui.GroupInfo
import com.wt.intercom.ui.BluetoothPermissions
import com.wt.intercom.ui.BluetoothRoomRole
import com.wt.intercom.ui.BluetoothScanScreen
import com.wt.intercom.ui.HomeScreen
import com.wt.intercom.ui.HostTransferAction
import com.wt.intercom.ui.HostTransferFlow
import com.wt.intercom.ui.LoopbackScreen
import com.wt.intercom.ui.NearbyPermissions
import com.wt.intercom.ui.NearbyScanScreen
import com.wt.intercom.ui.RoomFlow
import com.wt.intercom.ui.RoomPermissions
import com.wt.intercom.ui.RoomKind
import com.wt.intercom.ui.RoomRole
import com.wt.intercom.ui.RoomScreen
import com.wt.intercom.ui.RoomStart
import com.wt.intercom.ui.ScanScreen
import com.wt.intercom.ui.Screen
import com.wt.intercom.ui.SunsetRippleTheme
import kotlin.concurrent.thread
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : ComponentActivity() {

    private data class WifiRoomSnapshot(
        val session: RoomSession?,
        val group: GroupInfo?,
        val channelLost: Boolean,
        val kind: RoomKind?,
    )

    private lateinit var wifi: WifiDirectManager
    private lateinit var bluetooth: BluetoothRoomManager
    private lateinit var audioFocus: AudioFocusController
    private val loopback = LoopbackController()

    /** 会话得让 Compose 观察得到（建/散都要触发重组），所以用 StateFlow 而不是裸字段。 */
    private val sessionFlow = MutableStateFlow<RoomSession?>(null)
    private val bluetoothSessionFlow = MutableStateFlow<BluetoothRoomSession?>(null)
    private val nearbyManagerFlow = MutableStateFlow<NearbyRoomManager?>(null)
    private val roomKindFlow = MutableStateFlow<RoomKind?>(null)

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
        bluetooth = BluetoothRoomManager(this)
        audioFocus = AudioFocusController(this)
        wifi.register()
        watchRoomDeath()
        handleLeaveIntent(intent)
        setContent { SunsetRippleTheme { App() } }
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
        bluetooth.close()
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
            combine(sessionFlow, wifi.connection, wifi.channelLost, roomKindFlow) { session, info, channelLost, kind ->
                val group = info?.let {
                    GroupInfo(it.groupFormed, it.isGroupOwner, it.groupOwnerAddress?.hostAddress)
                }
                WifiRoomSnapshot(session, group, channelLost, kind)
            }.collect { snapshot ->
                val session = snapshot.session ?: return@collect
                if (snapshot.kind != RoomKind.WIFI) return@collect
                val reason =
                    RoomFlow.deathReason(
                        sessionActive = true,
                        group = snapshot.group,
                        channelLost = snapshot.channelLost,
                    )
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
        ActiveCallControls.attach(
            stateProvider = {
                when (roomKindFlow.value) {
                    RoomKind.BLUETOOTH -> bluetoothSessionFlow.value?.state?.value?.let { state ->
                        CallNotificationState(
                            label = label,
                            mode = CallMode.PUSH_TO_TALK,
                            pttActive = state.pttPressed,
                            audioFocusInterrupted = state.audioFocusInterrupted,
                        )
                    }
                    RoomKind.WIFI, RoomKind.NEARBY -> sessionFlow.value?.state?.value?.let { state ->
                        CallNotificationState(
                            label = label,
                            mode = CallMode.FULL_DUPLEX,
                            micMuted = state.micMuted,
                            audioFocusInterrupted = state.audioFocusInterrupted,
                        )
                    }
                    null -> null
                }
            },
            onControl = {
                when (roomKindFlow.value) {
                    RoomKind.BLUETOOTH -> bluetoothSessionFlow.value?.let { session ->
                        session.setPttPressed(!session.state.value.pttPressed)
                    }
                    RoomKind.WIFI, RoomKind.NEARBY -> sessionFlow.value?.let { session ->
                        session.setMicMuted(!session.state.value.micMuted)
                    }
                    null -> Unit
                }
            },
            onLeave = {
                leaveRequests.value += 1
                releaseRoom()
            },
        )
        val focusState = audioFocus.request(::setAudioFocusInterrupted)
        setAudioFocusInterrupted(focusState != AudioFocusRequestState.GRANTED)
        val notificationState = ActiveCallControls.currentState()
            ?: CallNotificationState(
                label,
                if (roomKindFlow.value == RoomKind.BLUETOOTH) CallMode.PUSH_TO_TALK else CallMode.FULL_DUPLEX,
            )
        CallForegroundService.start(this, notificationState)
    }

    private fun setAudioFocusInterrupted(interrupted: Boolean) {
        sessionFlow.value?.setAudioFocusInterrupted(interrupted)
        bluetoothSessionFlow.value?.setAudioFocusInterrupted(interrupted)
        CallForegroundService.refresh()
    }

    /** 释放当前房型资源：会话 → manager → 前台服务 → 音频模式。幂等，主线程调用。 */
    private fun releaseRoom(keepWifiGroup: Boolean = false) {
        when (roomKindFlow.value) {
            RoomKind.WIFI -> {
                val session = sessionFlow.value
                sessionFlow.value = null
                session?.let { runCatching { it.leave() }.onFailure { e -> TransportLog.w("WiFi 离房异常: ${e.message}", e) } }
                if (!keepWifiGroup) wifi.disconnect()
            }
            RoomKind.BLUETOOTH -> {
                val session = bluetoothSessionFlow.value
                bluetoothSessionFlow.value = null
                session?.let { runCatching { it.leave() }.onFailure { e -> TransportLog.w("蓝牙离房异常: ${e.message}", e) } }
                bluetooth.close()
            }
            RoomKind.NEARBY -> {
                val session = sessionFlow.value
                sessionFlow.value = null
                session?.let {
                    runCatching { it.leave() }
                        .onFailure { error -> TransportLog.w("Nearby 离房异常: ${error.message}", error) }
                }
                nearbyManagerFlow.value?.close()
                nearbyManagerFlow.value = null
            }
            null -> Unit
        }
        roomKindFlow.value = null
        ActiveCallControls.clear()
        audioFocus.abandon()
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
    private fun rememberRoomState(session: RoomSession?, bluetoothSession: BluetoothRoomSession?): RoomUiState {
        val flow: StateFlow<RoomUiState> =
            remember(session, bluetoothSession) {
                session?.state ?: bluetoothSession?.state ?: MutableStateFlow(RoomUiState())
            }
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
        var pendingBluetoothRole by remember { mutableStateOf<BluetoothRoomRole?>(null) }
        var pendingBluetoothAction by remember { mutableStateOf<(() -> Unit)?>(null) }
        var pendingNearbyAction by remember { mutableStateOf<(() -> Unit)?>(null) }
        var pendingWifiTransferSeed by remember { mutableStateOf<HostTransferSeed?>(null) }
        var wifiTransferTarget by remember { mutableStateOf<String?>(null) }

        val required = remember(sdkInt) { RoomPermissions.required(sdkInt) }
        val requested = remember(sdkInt) { RoomPermissions.requested(sdkInt).toTypedArray() }

        val connection by wifi.connection.collectAsStateWithLifecycle()
        val peers by wifi.peers.collectAsStateWithLifecycle()
        val wifiError by wifi.lastError.collectAsStateWithLifecycle()
        val session by sessionFlow.collectAsStateWithLifecycle()
        val bluetoothSession by bluetoothSessionFlow.collectAsStateWithLifecycle()
        val roomKind by roomKindFlow.collectAsStateWithLifecycle()
        val bondedDevices by bluetooth.bondedDevices.collectAsStateWithLifecycle()
        val discoveredDevices by bluetooth.discoveredDevices.collectAsStateWithLifecycle()
        val bluetoothDiscovering by bluetooth.discovering.collectAsStateWithLifecycle()
        val bluetoothError by bluetooth.lastError.collectAsStateWithLifecycle()
        val nearbyManager by nearbyManagerFlow.collectAsStateWithLifecycle()
        val nearbyEndpointsFlow: StateFlow<List<NearbyEndpoint>> = remember(nearbyManager) {
            nearbyManager?.endpoints ?: MutableStateFlow(emptyList())
        }
        val nearbyDiscoveringFlow: StateFlow<Boolean> = remember(nearbyManager) {
            nearbyManager?.discovering ?: MutableStateFlow(false)
        }
        val nearbyErrorFlow: StateFlow<String?> = remember(nearbyManager) {
            nearbyManager?.lastError ?: MutableStateFlow(null)
        }
        val nearbyEndpoints by nearbyEndpointsFlow.collectAsStateWithLifecycle()
        val nearbyDiscovering by nearbyDiscoveringFlow.collectAsStateWithLifecycle()
        val nearbyError by nearbyErrorFlow.collectAsStateWithLifecycle()
        val leaveRequest by leaveRequests.collectAsStateWithLifecycle()
        val roomState = rememberRoomState(session, bluetoothSession)
        val group = connection?.let {
            GroupInfo(it.groupFormed, it.isGroupOwner, it.groupOwnerAddress?.hostAddress)
        }

        fun goHome(message: String?) {
            pendingWifiTransferSeed = null
            wifiTransferTarget = null
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

        val bluetoothPermLauncher = rememberLauncherForActivityResult(
            ActivityResultContracts.RequestMultiplePermissions()
        ) { result ->
            val action = pendingBluetoothAction
            val bluetoothRole = pendingBluetoothRole
            pendingBluetoothAction = null
            pendingBluetoothRole = null
            if (bluetoothRole == null) return@rememberLauncherForActivityResult
            val denied = BluetoothPermissions.blockingDenied(result, sdkInt, bluetoothRole)
            if (denied.isEmpty()) {
                action?.invoke()
            } else {
                val message = BluetoothPermissions.deniedMessage(denied)
                status = message
                Toast.makeText(context, message, Toast.LENGTH_LONG).show()
            }
        }

        val nearbyPermLauncher = rememberLauncherForActivityResult(
            ActivityResultContracts.RequestMultiplePermissions()
        ) { result ->
            val action = pendingNearbyAction
            pendingNearbyAction = null
            val denied = NearbyPermissions.blockingDenied(result, sdkInt)
            if (denied.isEmpty()) {
                action?.invoke()
            } else {
                val message = NearbyPermissions.deniedMessage(denied)
                status = message
                Toast.makeText(context, message, Toast.LENGTH_LONG).show()
            }
        }

        fun startBluetoothHost(
            transferSeed: HostTransferSeed? = null,
            secure: Boolean = true,
        ) {
            val adapter = (getSystemService(BLUETOOTH_SERVICE) as BluetoothManager).adapter
            val newSession = BluetoothRoomSession(nickname)
            val transport = BluetoothHostTransport(
                nickname,
                newSession,
                adapter,
                transferSeed = transferSeed,
                secure = secure,
            )
            bluetoothSessionFlow.value = newSession
            roomKindFlow.value = RoomKind.BLUETOOTH
            isHost = true
            beginCall(BLUETOOTH_HOST_LABEL, speakerOn)
            runCatching { newSession.start(transport) }
                .onSuccess {
                    status = null
                    screen = Screen.ROOM
                }
                .onFailure { error ->
                    TransportLog.w("蓝牙建房失败: ${error.message}", error)
                    Toast.makeText(context, "蓝牙建房失败：${error.message}", Toast.LENGTH_LONG).show()
                    goHome("蓝牙建房失败：${error.message}")
                }
        }

        val discoverableLauncher = rememberLauncherForActivityResult(
            ActivityResultContracts.StartActivityForResult()
        ) { result ->
            if (result.resultCode == RESULT_CANCELED) {
                status = "需要允许蓝牙可发现才能创建房间"
            } else {
                startBluetoothHost()
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

        fun withBluetoothPermissions(bluetoothRole: BluetoothRoomRole, action: () -> Unit) {
            val requiredPermissions = BluetoothPermissions.required(sdkInt, bluetoothRole)
            val missing = requiredPermissions.any {
                ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED
            }
            if (missing) {
                pendingBluetoothRole = bluetoothRole
                pendingBluetoothAction = action
                bluetoothPermLauncher.launch(requiredPermissions.toTypedArray())
            } else {
                action()
            }
        }

        fun withNearbyPermissions(action: () -> Unit) {
            val permissions = NearbyPermissions.required(sdkInt)
            val missing = permissions.any {
                ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED
            }
            if (missing) {
                pendingNearbyAction = action
                nearbyPermLauncher.launch(permissions.toTypedArray())
            } else {
                action()
            }
        }

        fun startNearbyHost() {
            val manager = NearbyRoomManager(this)
            nearbyManagerFlow.value = manager
            if (!manager.ensureAvailable()) {
                status = manager.lastError.value
                manager.close()
                nearbyManagerFlow.value = null
                return
            }
            val port = manager.handoffPort()
            nearbyManagerFlow.value = null
            val newSession = RoomSession(nickname)
            val transport = NearbyRoomTransport.host(nickname, newSession, port)
            sessionFlow.value = newSession
            roomKindFlow.value = RoomKind.NEARBY
            isHost = true
            beginCall(NEARBY_HOST_LABEL, speakerOn)
            runCatching {
                newSession.start(transport)
                transport.start()
            }.onSuccess {
                status = null
                screen = Screen.ROOM
            }.onFailure { error ->
                TransportLog.w("Nearby 建房失败: ${error.message}", error)
                goHome("Nearby 建房失败：${error.message}")
            }
        }

        fun startNearbyDiscovery() {
            nearbyManagerFlow.value?.close()
            val manager = NearbyRoomManager(this)
            nearbyManagerFlow.value = manager
            roomKindFlow.value = RoomKind.NEARBY
            manager.startDiscovery()
            if (manager.lastError.value == null) {
                status = null
                screen = Screen.NEARBY_SCAN
            } else {
                status = manager.lastError.value
                releaseRoom()
            }
        }

        fun startNearbyGuest(endpoint: NearbyEndpoint) {
            val manager = nearbyManagerFlow.value ?: return
            val port = runCatching { manager.handoffPort() }.getOrElse { error ->
                status = "Nearby 连接准备失败：${error.message}"
                return
            }
            nearbyManagerFlow.value = null
            val newSession = RoomSession(nickname)
            val transport = NearbyRoomTransport.guest(
                nickname,
                newSession,
                port,
                endpoint.id,
                discoveryAlreadyActive = true,
            )
            sessionFlow.value = newSession
            roomKindFlow.value = RoomKind.NEARBY
            isHost = false
            beginCall(NEARBY_GUEST_LABEL, speakerOn)
            runCatching {
                newSession.start(transport)
                transport.start()
            }.onSuccess {
                status = "正在连接 ${endpoint.name}……"
                screen = Screen.ROOM
            }.onFailure { error ->
                TransportLog.w("Nearby 入房失败: ${error.message}", error)
                goHome("Nearby 入房失败：${error.message}")
            }
        }

        fun startBluetoothGuest(device: BluetoothDevice, secure: Boolean = true) {
            val newSession = BluetoothRoomSession(nickname)
            bluetoothSessionFlow.value = newSession
            roomKindFlow.value = RoomKind.BLUETOOTH
            isHost = false
            status = "正在连接 ${device.name.orEmpty().ifBlank { device.address }}……"
            val nick = nickname
            val speaker = speakerOn
            beginCall(BLUETOOTH_GUEST_LABEL, speaker)
            thread(name = "bluetooth-join") {
                val transport = BluetoothClientTransport(nick, newSession, device, secure = secure)
                try {
                    newSession.start(transport)
                } catch (error: Exception) {
                    TransportLog.w("蓝牙入房失败: ${error.message}", error)
                    runOnUiThread { goHome("蓝牙入房失败：${error.message}") }
                    return@thread
                }
                runOnUiThread {
                    if (bluetoothSessionFlow.value !== newSession) {
                        runCatching { newSession.leave() }
                        return@runOnUiThread
                    }
                    status = null
                    screen = Screen.ROOM
                }
            }
        }

        fun startHost(hostIp: String, transferSeed: HostTransferSeed? = null) {
            val newSession = RoomSession(nickname)
            // 构造即绑端口，失败要让用户看见（8988/8989 被占）。
            val transport = try {
                WifiHostTransport(nickname, newSession, hostIp, transferSeed = transferSeed)
            } catch (e: Exception) {
                TransportLog.w("建房失败: ${e.message}", e)
                Toast.makeText(context, "建房失败：${e.message}", Toast.LENGTH_LONG).show()
                goHome("建房失败：${e.message}")
                return
            }
            sessionFlow.value = newSession
            roomKindFlow.value = RoomKind.WIFI
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
            pendingWifiTransferSeed = null
            screen = Screen.ROOM
        }

        fun startGuest(hostIp: String) {
            val newSession = RoomSession(nickname)
            sessionFlow.value = newSession
            roomKindFlow.value = RoomKind.WIFI
            isHost = false
            status = "正在入房……"
            val nick = nickname
            val speaker = speakerOn
            // TCP 连接是阻塞的（5s 超时），不能占主线程。
            thread(name = "wifi-join") {
                val transport = try {
                    WifiClientTransport(
                        nick,
                        hostIp,
                        newSession,
                        localEndpoint = wifi.thisDevice.value?.deviceAddress
                            ?.takeUnless { it.isBlank() || it == UNKNOWN_P2P_ADDRESS },
                    ).also { it.start() }
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
                    wifiTransferTarget = null
                    screen = Screen.ROOM
                }
            }
        }

        // 组建立 → 起会话。主客身份与组主地址一律取系统真值，不回落硬编码 IP。
        LaunchedEffect(group, role, session) {
            when (val start = RoomFlow.decide(group, role, session != null)) {
                RoomStart.Idle -> Unit
                RoomStart.AwaitingAddress -> {
                    status = "组已建立，正在获取组主地址……"
                    delay(RoomFlow.ADDRESS_WAIT_TIMEOUT_MILLIS)
                    val reason =
                        RoomFlow.addressTimeoutReason(
                            start,
                            elapsedMillis = RoomFlow.ADDRESS_WAIT_TIMEOUT_MILLIS,
                        ) ?: return@LaunchedEffect
                    TransportLog.w(reason)
                    // 先清入房意图再断连，避免晚到的连接广播重新启动等待。
                    role = RoomRole.NONE
                    wifi.disconnect()
                    status = reason
                    screen = Screen.HOME
                    Toast.makeText(context, reason, Toast.LENGTH_LONG).show()
                }
                is RoomStart.Host -> startHost(start.hostIp, pendingWifiTransferSeed)
                is RoomStart.Guest -> startGuest(start.hostIp)
            }
        }

        LaunchedEffect(wifiTransferTarget) {
            val target = wifiTransferTarget ?: return@LaunchedEffect
            repeat(HOST_TRANSFER_DISCOVERY_ATTEMPTS) { attempt ->
                if (wifiTransferTarget != target || sessionFlow.value != null) return@LaunchedEffect
                if (wifi.connection.value?.groupFormed == true) return@LaunchedEffect
                val peer = wifi.peers.value.firstOrNull {
                    it.deviceAddress.equals(target, ignoreCase = true)
                }
                if (peer == null) {
                    status = "房主交接中，正在发现新房主……"
                    wifi.discoverPeers()
                } else {
                    status = "房主交接中，正在连接新房主……"
                    wifi.connect(peer)
                }
                delay(HOST_TRANSFER_DISCOVERY_INTERVAL_MS)
                if (attempt == HOST_TRANSFER_DISCOVERY_ATTEMPTS - 1 &&
                    wifiTransferTarget == target &&
                    wifi.connection.value?.groupFormed != true
                ) {
                    goHome("房主交接失败，请重新加入房间")
                }
            }
        }

        LaunchedEffect(roomState.hostTransfer) {
            val plan = roomState.hostTransfer ?: return@LaunchedEffect
            val selfId = roomState.members.firstOrNull { it.isSelf }?.id ?: return@LaunchedEffect
            val action = HostTransferFlow.decide(plan, selfId)
            val previousKind = roomKind
            status = "房主交接中……"
            releaseRoom(keepWifiGroup = previousKind == RoomKind.WIFI)
            when (previousKind) {
                RoomKind.BLUETOOTH -> when (action) {
                    is HostTransferAction.BecomeHost ->
                        startBluetoothHost(action.seed, secure = false)
                    is HostTransferAction.JoinHost -> {
                        val adapter = (getSystemService(BLUETOOTH_SERVICE) as BluetoothManager).adapter
                        val device = runCatching { adapter.getRemoteDevice(action.endpoint) }.getOrElse { error ->
                            goHome("房主交接失败：${error.message}")
                            return@LaunchedEffect
                        }
                        startBluetoothGuest(device, secure = false)
                    }
                    HostTransferAction.Ignore -> goHome("房主交接信息已失效")
                }
                RoomKind.WIFI -> when (action) {
                    is HostTransferAction.BecomeHost -> {
                        pendingWifiTransferSeed = action.seed
                        wifiTransferTarget = null
                        role = RoomRole.HOST
                        isHost = true
                        roomKindFlow.value = null
                        wifi.createGroup()
                        screen = Screen.ROOM
                    }
                    is HostTransferAction.JoinHost -> {
                        pendingWifiTransferSeed = null
                        wifiTransferTarget = action.endpoint
                        role = RoomRole.GUEST
                        isHost = false
                        roomKindFlow.value = null
                        wifi.disconnectAndDiscoverPeers()
                        screen = Screen.ROOM
                    }
                    HostTransferAction.Ignore -> goHome("房主交接信息已失效")
                }
                RoomKind.NEARBY, null -> goHome("当前房型不支持房主交接")
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
            if (leaveRequest > 0) goHome(null)
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
                Screen.BLUETOOTH_SCAN -> {
                    goHome(null)
                }
                Screen.NEARBY_SCAN -> {
                    goHome(null)
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
                onCreateBluetoothRoom = {
                    withBluetoothPermissions(BluetoothRoomRole.HOST) {
                        bluetooth.register()
                        val intent = bluetooth.requestDiscoverableIntent(300)
                        if (intent == null) {
                            status = bluetooth.lastError.value
                        } else {
                            discoverableLauncher.launch(intent)
                        }
                    }
                },
                onJoinBluetoothRoom = {
                    withBluetoothPermissions(BluetoothRoomRole.GUEST) {
                        bluetooth.register()
                        bluetooth.discoverDevices()
                        status = null
                        screen = Screen.BLUETOOTH_SCAN
                    }
                },
                onCreateNearbyRoom = {
                    withNearbyPermissions { startNearbyHost() }
                },
                onJoinNearbyRoom = {
                    withNearbyPermissions { startNearbyDiscovery() }
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
                status = status ?: wifiError ?: nearbyError,
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

            Screen.BLUETOOTH_SCAN -> BluetoothScanScreen(
                bondedDevices = bondedDevices,
                discoveredDevices = discoveredDevices,
                discovering = bluetoothDiscovering,
                status = status ?: bluetoothError,
                onPick = { device ->
                    if (device.bondState == BluetoothDevice.BOND_BONDED) {
                        bluetooth.close()
                        startBluetoothGuest(device)
                    } else {
                        status = "请在系统配对弹窗中确认"
                        runCatching { device.createBond() }
                            .onFailure { status = "发起配对失败：${it.message}" }
                    }
                },
                onScanAgain = { bluetooth.discoverDevices() },
                onBack = {
                    goHome(null)
                },
            )

            Screen.NEARBY_SCAN -> NearbyScanScreen(
                endpoints = nearbyEndpoints,
                discovering = nearbyDiscovering,
                status = status ?: nearbyError,
                onPick = ::startNearbyGuest,
                onScanAgain = {
                    nearbyManager?.startDiscovery()
                },
                onBack = { goHome(null) },
            )

            Screen.ROOM -> RoomScreen(
                state = roomState,
                roomLabel = when (roomKind) {
                    RoomKind.BLUETOOTH -> if (isHost) BLUETOOTH_HOST_LABEL else BLUETOOTH_GUEST_LABEL
                    RoomKind.NEARBY -> if (isHost) NEARBY_HOST_LABEL else NEARBY_GUEST_LABEL
                    else -> if (isHost) HOST_LABEL else GUEST_LABEL
                },
                speakerOn = speakerOn,
                onToggleMute = {
                    session?.setMicMuted(!roomState.micMuted)
                    CallForegroundService.refresh()
                },
                onToggleSpeaker = {
                    speakerOn = !speakerOn
                    setSpeaker(speakerOn)
                },
                onLeave = { goHome(null) },
                onPttChanged = if (roomKind == RoomKind.BLUETOOTH) {
                    { pressed ->
                        bluetoothSession?.setPttPressed(pressed)
                        CallForegroundService.refresh()
                    }
                } else null,
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
        const val BLUETOOTH_HOST_LABEL = "蓝牙房（我是房主）"
        const val BLUETOOTH_GUEST_LABEL = "蓝牙房"
        const val NEARBY_HOST_LABEL = "Nearby 房（我是房主）"
        const val NEARBY_GUEST_LABEL = "Nearby 房"
        const val UNKNOWN_P2P_ADDRESS = "02:00:00:00:00:00"
        const val HOST_TRANSFER_DISCOVERY_ATTEMPTS = 10
        const val HOST_TRANSFER_DISCOVERY_INTERVAL_MS = 3_000L
    }
}
