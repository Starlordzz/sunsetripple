package host.msknet.sunsetripple

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.content.Intent
import android.location.LocationManager
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.graphics.toArgb
import androidx.core.location.LocationManagerCompat
import androidx.core.view.WindowCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import host.msknet.sunsetripple.audio.LoopbackController
import host.msknet.sunsetripple.audio.AudioFocusController
import host.msknet.sunsetripple.audio.AudioFocusRequestState
import host.msknet.sunsetripple.diagnostics.DiagnosticExporter
import host.msknet.sunsetripple.diagnostics.DiagnosticReport
import host.msknet.sunsetripple.service.CallForegroundService
import host.msknet.sunsetripple.service.ActiveCallControls
import host.msknet.sunsetripple.service.CallMode
import host.msknet.sunsetripple.service.CallNotificationState
import host.msknet.sunsetripple.session.RoomSession
import host.msknet.sunsetripple.session.RoomUiState
import host.msknet.sunsetripple.session.BluetoothRoomSession
import host.msknet.sunsetripple.session.RoomLifecycleCoordinator
import host.msknet.sunsetripple.security.DeviceIdentityStore
import host.msknet.sunsetripple.transport.TransportLog
import host.msknet.sunsetripple.transport.HostTransferSeed
import host.msknet.sunsetripple.transport.bluetooth.BluetoothClientTransport
import host.msknet.sunsetripple.transport.bluetooth.BluetoothHostTransport
import host.msknet.sunsetripple.transport.bluetooth.BluetoothRoomManager
import host.msknet.sunsetripple.transport.nearby.NearbyEndpoint
import host.msknet.sunsetripple.transport.nearby.NearbyRoomManager
import host.msknet.sunsetripple.transport.nearby.NearbyRoomTransport
import host.msknet.sunsetripple.transport.wifi.WifiClientTransport
import host.msknet.sunsetripple.transport.wifi.WifiDirectManager
import host.msknet.sunsetripple.transport.wifi.WifiHostTransport
import host.msknet.sunsetripple.ui.GroupInfo
import host.msknet.sunsetripple.ui.BluetoothRoomRole
import host.msknet.sunsetripple.ui.BluetoothScanScreen
import host.msknet.sunsetripple.ui.EntryTransitionGate
import host.msknet.sunsetripple.ui.HomeScreen
import host.msknet.sunsetripple.ui.AboutUpdateScreen
import host.msknet.sunsetripple.ui.AppNavigationCoordinator
import host.msknet.sunsetripple.ui.AppCoordinator
import host.msknet.sunsetripple.ui.HostTransferAction
import host.msknet.sunsetripple.ui.HostTransferFlow
import host.msknet.sunsetripple.ui.LoopbackScreen
import host.msknet.sunsetripple.ui.rememberPermissionLaunchers
import host.msknet.sunsetripple.ui.rememberDiscoverableLauncher
import host.msknet.sunsetripple.ui.NearbyScanScreen
import host.msknet.sunsetripple.ui.RoomFlow
import host.msknet.sunsetripple.ui.RoomPermissions
import host.msknet.sunsetripple.ui.RoomKind
import host.msknet.sunsetripple.ui.RoomRole
import host.msknet.sunsetripple.ui.RoomScreen
import host.msknet.sunsetripple.ui.RoomStart
import host.msknet.sunsetripple.ui.ScanScreen
import host.msknet.sunsetripple.ui.Screen
import host.msknet.sunsetripple.ui.ScreenRestoration
import host.msknet.sunsetripple.ui.SunsetNightPalette
import host.msknet.sunsetripple.ui.SunsetDayPalette
import host.msknet.sunsetripple.ui.SunsetPalette
import host.msknet.sunsetripple.ui.SunsetRippleTheme
import host.msknet.sunsetripple.ui.ThemeMode
import host.msknet.sunsetripple.ui.ThemeCoordinator
import host.msknet.sunsetripple.ui.ThemeModeResolver
import host.msknet.sunsetripple.ui.ThemeModeStore
import host.msknet.sunsetripple.ui.SunsetColors
import host.msknet.sunsetripple.ui.SunsetMotion
import host.msknet.sunsetripple.update.AboutUpdateCoordinator
import host.msknet.sunsetripple.update.GithubUpdateService
import host.msknet.sunsetripple.update.UpdateChannel
import host.msknet.sunsetripple.update.UpdateState
import host.msknet.sunsetripple.ui.sunsetCircularReveal
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
    private val deviceIdentity by lazy { DeviceIdentityStore(applicationContext).loadOrCreate() }
    private val aboutUpdateCoordinator by lazy {
        AboutUpdateCoordinator(
            updateService = GithubUpdateService(
                context = applicationContext,
                manifestUrl = BuildConfig.UPDATE_MANIFEST_URL,
                publicKeyBase64 = BuildConfig.UPDATE_PUBLIC_KEY,
                channel = UpdateChannel.PRERELEASE,
            ),
            execute = { task ->
                activityScope.launch(Dispatchers.IO) { task() }
                Unit
            },
            isCallActive = {
                ::roomLifecycle.isInitialized && roomLifecycle.roomKind.value != null
            },
        )
    }
    private lateinit var navigation: AppNavigationCoordinator
    private lateinit var appCoordinator: AppCoordinator

    /** 昼夜取向要跨启动记住，否则冷启动会把用户手动选的档位打回跟随系统。 */
    private val themeModeStore by lazy { ThemeModeStore(this) }
    private val themeCoordinator by lazy { ThemeCoordinator(themeModeStore) }

    private lateinit var roomLifecycle: RoomLifecycleCoordinator
    private val sessionFlow: StateFlow<RoomSession?> get() = roomLifecycle.session
    private val bluetoothSessionFlow: StateFlow<BluetoothRoomSession?> get() = roomLifecycle.bluetoothSession
    private val nearbyManagerFlow: StateFlow<NearbyRoomManager?> get() = roomLifecycle.nearbyManager
    private val roomKindFlow: StateFlow<RoomKind?> get() = roomLifecycle.roomKind

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
        val restoredState = ScreenRestoration.restoreState(savedInstanceState?.getString(STATE_SCREEN))
        navigation = AppNavigationCoordinator(restoredState.screen)
        appCoordinator = AppCoordinator(
            Build.MODEL?.take(8)?.trim().orEmpty().ifEmpty { getString(R.string.me) },
            initialStatus = restoredState.message,
        )
        if (AppWindowPolicy.keepScreenOn) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        wifi = WifiDirectManager(this)
        bluetooth = BluetoothRoomManager(this)
        audioFocus = AudioFocusController(this)
        roomLifecycle = RoomLifecycleCoordinator(
            disconnectWifi = wifi::disconnect,
            closeBluetooth = bluetooth::close,
            stopCallRuntime = ::stopCallRuntime,
        )
        wifi.register()
        watchRoomDeath()
        handleLeaveIntent(intent)
        setContent {
            val themeMode = themeCoordinator.mode.collectAsStateWithLifecycle().value
            val palette = if (ThemeModeResolver.isNight(themeMode, isSystemInDarkTheme())) {
                SunsetNightPalette
            } else {
                SunsetDayPalette
            }
            SyncSystemBars(palette)
            SunsetRippleTheme(night = palette.night) {
                App(
                    themeMode = themeMode,
                    onCycleThemeMode = themeCoordinator::cycle,
                )
            }
        }
    }

    /**
     * 系统栏跟着当前调色板走。targetSdk 35 起系统强制边到边、这两个颜色属于空操作，
     * 但在更早的机型上仍然生效，设了无害。
     */
    @Composable
    private fun SyncSystemBars(palette: SunsetPalette) {
        LaunchedEffect(palette) {
            @Suppress("DEPRECATION")
            window.statusBarColor = palette.backdrop.first().toArgb()
            @Suppress("DEPRECATION")
            window.navigationBarColor = palette.canvas.toArgb()
            WindowCompat.getInsetsController(window, window.decorView).apply {
                // 状态栏永远压在头图渐变上，图标恒定用浅色。
                isAppearanceLightStatusBars = false
                isAppearanceLightNavigationBars = !palette.night
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleLeaveIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        if (::roomLifecycle.isInitialized && aboutUpdateCoordinator.state.value == UpdateState.InstallConfirmationOpened) {
            aboutUpdateCoordinator.reportInstallCancelled()
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString(STATE_SCREEN, ScreenRestoration.save(navigation.screen.value))
        super.onSaveInstanceState(outState)
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

    private fun stopCallRuntime() {
        ActiveCallControls.clear()
        audioFocus.abandon()
        CallForegroundService.stop(this)
        setCommunicationMode(false)
    }

    /** 释放当前房型资源：会话 → manager → 前台服务 → 音频模式。幂等，主线程调用。 */
    private fun releaseRoom(keepWifiGroup: Boolean = false) {
        roomLifecycle.release(keepWifiGroup)
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
    @SuppressLint("MissingPermission")
    private fun App(
        themeMode: ThemeMode,
        onCycleThemeMode: () -> Unit,
    ) {
        val context = LocalContext.current
        val sdkInt = Build.VERSION.SDK_INT

        val screen = navigation.screen.collectAsStateWithLifecycle().value
        val versionName = remember {
            packageManager.getPackageInfo(packageName, 0).versionName.orEmpty()
        }
        val appState = appCoordinator.state.collectAsStateWithLifecycle().value
        val nickname = appState.nickname
        val status = appState.status
        val updateState = aboutUpdateCoordinator.state.collectAsStateWithLifecycle().value
        val role = appState.roomRole
        val isHost = appState.isHost
        val speakerOn = appState.speakerOn
        var pendingBluetoothEntryOrigin by remember { mutableStateOf<Offset?>(null) }
        var pendingWifiTransferSeed by remember { mutableStateOf<HostTransferSeed?>(null) }
        var wifiTransferTarget by remember { mutableStateOf<String?>(null) }
        val entryTransition = remember { EntryTransitionGate() }
        val entryTransitionProgress = remember { Animatable(0f) }
        val entryTransitionProgressState = entryTransitionProgress.asState()
        val entryTransitionScope = rememberCoroutineScope()
        var entryTransitionOrigin by remember { mutableStateOf(Offset.Zero) }
        var entryPreviewVisible by remember { mutableStateOf(false) }
        val headerMotion = rememberInfiniteTransition(label = "shared-sunset-header-motion")
        val headerPhase = headerMotion.animateFloat(
            initialValue = 0f,
            targetValue = 1f,
            animationSpec = infiniteRepeatable(
                animation = tween(7_200, easing = FastOutSlowInEasing),
                repeatMode = RepeatMode.Reverse,
            ),
            label = "shared-sunset-header-phase",
        )

        fun runEntryTransition(origin: Offset, action: () -> Unit) {
            if (!entryTransition.tryBegin()) return
            entryTransitionOrigin = origin
            entryTransitionScope.launch {
                try {
                    entryTransitionProgress.snapTo(0f)
                    entryPreviewVisible = true
                    action()
                    withFrameNanos { }
                    entryTransitionProgress.animateTo(
                        targetValue = 1f,
                        animationSpec = tween(560, easing = LinearOutSlowInEasing),
                    )
                    if (entryPreviewVisible) {
                        navigation.navigateTo(Screen.ROOM)
                        withFrameNanos { }
                    }
                } finally {
                    entryPreviewVisible = false
                    entryTransitionProgress.snapTo(0f)
                    entryTransition.finish()
                }
            }
        }

        val connection by wifi.connection.collectAsStateWithLifecycle()
        val peers by wifi.peers.collectAsStateWithLifecycle()
        val wifiDiscovering by wifi.discovering.collectAsStateWithLifecycle()
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
            entryPreviewVisible = false
            pendingWifiTransferSeed = null
            wifiTransferTarget = null
            releaseRoom()
            appCoordinator.resetRoom(message)
            navigation.navigateTo(Screen.HOME)
        }

        fun runWhenLocationReady(action: () -> Unit) {
            if (!RoomPermissions.needsLocationService(sdkInt) || isLocationServiceEnabled()) {
                action()
                return
            }
            appCoordinator.setStatus(getString(R.string.location_service_off))
            Toast.makeText(context, getString(R.string.location_service_off), Toast.LENGTH_LONG).show()
        }

        val permissionLaunchers = rememberPermissionLaunchers(
            context = context,
            sdkInt = sdkInt,
            runWhenLocationReady = ::runWhenLocationReady,
            onDenied = { message ->
                appCoordinator.setStatus(message)
                Toast.makeText(context, message, Toast.LENGTH_LONG).show()
            },
        )

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
            roomLifecycle.publishBluetoothSession(newSession)
            appCoordinator.setHost(true)
            beginCall(bluetoothHostLabel, speakerOn)
            runCatching { newSession.start(transport) }
                .onSuccess {
                    appCoordinator.setStatus(null)
                    if (!entryPreviewVisible) navigation.navigateTo(Screen.ROOM)
                }
                .onFailure { error ->
                    TransportLog.w("蓝牙建房失败: ${error.message}", error)
            Toast.makeText(context, getString(R.string.bluetooth_create_failed, error.message.orEmpty()), Toast.LENGTH_LONG).show()
            goHome(getString(R.string.bluetooth_create_failed, error.message.orEmpty()))
                }
        }

        val launchDiscoverable = rememberDiscoverableLauncher(
            onCanceled = {
                pendingBluetoothEntryOrigin = null
            appCoordinator.setStatus(getString(R.string.bluetooth_discoverable_required))
            },
            onAllowed = {
            val origin = pendingBluetoothEntryOrigin
            pendingBluetoothEntryOrigin = null
            if (origin != null) {
                runEntryTransition(origin) {
                    roomLifecycle.setRoomKind(RoomKind.BLUETOOTH)
                    appCoordinator.setHost(true)
            appCoordinator.setStatus(getString(R.string.establishing_bluetooth))
                    startBluetoothHost()
                }
            }
            },
        )

        fun startNearbyHost() {
            val manager = NearbyRoomManager(this)
            roomLifecycle.publishNearbyManager(manager)
            if (!manager.ensureAvailable()) {
                appCoordinator.setStatus(manager.lastError.value)
                manager.close()
                roomLifecycle.publishNearbyManager(null)
                return
            }
            val port = manager.handoffPort()
            roomLifecycle.publishNearbyManager(null)
            val newSession = RoomSession(nickname)
            val transport = NearbyRoomTransport.host(nickname, newSession, port)
            roomLifecycle.publishSession(newSession, RoomKind.NEARBY)
            appCoordinator.setHost(true)
            beginCall(nearbyHostLabel, speakerOn)
            runCatching {
                newSession.start(transport)
                transport.start()
            }.onSuccess {
                appCoordinator.setStatus(null)
                navigation.navigateTo(Screen.ROOM)
            }.onFailure { error ->
                TransportLog.w("Nearby 建房失败: ${error.message}", error)
            goHome(getString(R.string.nearby_create_failed, error.message.orEmpty()))
            }
        }

        fun startNearbyDiscovery() {
            nearbyManagerFlow.value?.close()
            val manager = NearbyRoomManager(this)
            roomLifecycle.publishNearbyManager(manager)
            roomLifecycle.setRoomKind(RoomKind.NEARBY)
            manager.startDiscovery()
            if (manager.lastError.value == null) {
                appCoordinator.setStatus(null)
                navigation.navigateTo(Screen.NEARBY_SCAN)
            } else {
                appCoordinator.setStatus(manager.lastError.value)
                releaseRoom()
            }
        }

        fun startNearbyGuest(endpoint: NearbyEndpoint) {
            val manager = nearbyManagerFlow.value ?: return
            val port = runCatching { manager.handoffPort() }.getOrElse { error ->
            appCoordinator.setStatus(getString(R.string.nearby_prepare_failed, error.message.orEmpty()))
                return
            }
            roomLifecycle.publishNearbyManager(null)
            val newSession = RoomSession(nickname)
            val transport = NearbyRoomTransport.guest(
                nickname,
                newSession,
                port,
                endpoint.id,
                discoveryAlreadyActive = true,
            )
            roomLifecycle.publishSession(newSession, RoomKind.NEARBY)
            appCoordinator.setHost(false)
            beginCall(nearbyGuestLabel, speakerOn)
            runCatching {
                newSession.start(transport)
                transport.start()
            }.onSuccess {
            appCoordinator.setStatus(getString(R.string.connecting_device, endpoint.name))
                navigation.navigateTo(Screen.ROOM)
            }.onFailure { error ->
                TransportLog.w("Nearby 入房失败: ${error.message}", error)
            goHome(getString(R.string.nearby_join_failed, error.message.orEmpty()))
            }
        }

        fun startBluetoothGuest(device: BluetoothDevice, secure: Boolean = true) {
            val newSession = BluetoothRoomSession(nickname)
            roomLifecycle.publishBluetoothSession(newSession)
            appCoordinator.setHost(false)
            appCoordinator.setStatus(getString(R.string.connecting_device, device.name.orEmpty().ifBlank { device.address }))
            val nick = nickname
            val speaker = speakerOn
            beginCall(bluetoothGuestLabel, speaker)
            thread(name = "bluetooth-join") {
                val transport = BluetoothClientTransport(nick, newSession, device, secure = secure)
                try {
                    newSession.start(transport)
                } catch (error: Exception) {
                    TransportLog.w("蓝牙入房失败: ${error.message}", error)
            runOnUiThread { goHome(getString(R.string.bluetooth_join_failed, error.message.orEmpty())) }
                    return@thread
                }
                runOnUiThread {
                    if (!roomLifecycle.isCurrent(newSession)) {
                        runCatching { newSession.leave() }
                        return@runOnUiThread
                    }
                    appCoordinator.setStatus(null)
                    navigation.navigateTo(Screen.ROOM)
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
            Toast.makeText(context, getString(R.string.room_create_failed, e.message.orEmpty()), Toast.LENGTH_LONG).show()
            goHome(getString(R.string.room_create_failed, e.message.orEmpty()))
                return
            }
            roomLifecycle.publishSession(newSession, RoomKind.WIFI)
            appCoordinator.setHost(true)
            beginCall(wifiHostLabel, speakerOn)
            try {
                newSession.start(transport)
                transport.start()
            } catch (e: Exception) {
                TransportLog.w("房间启动失败: ${e.message}", e)
                runCatching { transport.close() }
            Toast.makeText(context, getString(R.string.room_start_failed, e.message.orEmpty()), Toast.LENGTH_LONG).show()
            goHome(getString(R.string.room_start_failed, e.message.orEmpty()))
                return
            }
            appCoordinator.setStatus(null)
            pendingWifiTransferSeed = null
            if (!entryPreviewVisible) navigation.navigateTo(Screen.ROOM)
        }

        fun startGuest(hostIp: String) {
            val newSession = RoomSession(nickname)
            roomLifecycle.publishSession(newSession, RoomKind.WIFI)
            appCoordinator.setHost(false)
            appCoordinator.setStatus(getString(R.string.joining_room))
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
            Toast.makeText(context, getString(R.string.room_join_failed, e.message.orEmpty()), Toast.LENGTH_LONG).show()
            goHome(getString(R.string.room_join_failed, e.message.orEmpty()))
                    }
                    return@thread
                }
                runOnUiThread {
                    // 用户可能在握手期间就退了：会话已被换掉就地收手，别把 socket 漏在外面。
                    if (!roomLifecycle.isCurrent(newSession)) {
                        runCatching { transport.close() }
                        return@runOnUiThread
                    }
            beginCall(wifiGuestLabel, speaker)
                    try {
                        newSession.start(transport)
                    } catch (e: Exception) {
                        TransportLog.w("房间启动失败: ${e.message}", e)
                        runCatching { transport.close() }
            Toast.makeText(context, getString(R.string.room_start_failed, e.message.orEmpty()), Toast.LENGTH_LONG).show()
            goHome(getString(R.string.room_start_failed, e.message.orEmpty()))
                        return@runOnUiThread
                    }
                    appCoordinator.setStatus(null)
                    wifiTransferTarget = null
                    navigation.navigateTo(Screen.ROOM)
                }
            }
        }

        // 组建立 → 起会话。主客身份与组主地址一律取系统真值，不回落硬编码 IP。
        LaunchedEffect(group, role, session) {
            when (val start = RoomFlow.decide(group, role, session != null)) {
                RoomStart.Idle -> Unit
                RoomStart.AwaitingAddress -> {
            appCoordinator.setStatus(getString(R.string.waiting_group_owner))
                    delay(RoomFlow.ADDRESS_WAIT_TIMEOUT_MILLIS)
                    val reason =
                        RoomFlow.addressTimeoutReason(
                            start,
                            elapsedMillis = RoomFlow.ADDRESS_WAIT_TIMEOUT_MILLIS,
                        ) ?: return@LaunchedEffect
                    TransportLog.w(reason)
                    // 先清入房意图再断连，避免晚到的连接广播重新启动等待。
                    appCoordinator.setRoomRole(RoomRole.NONE)
                    wifi.disconnect()
                    appCoordinator.setStatus(reason)
                    navigation.navigateTo(Screen.HOME)
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
                appCoordinator.setStatus(getString(R.string.host_transfer_discovering))
                    wifi.discoverPeers()
                } else {
                appCoordinator.setStatus(getString(R.string.host_transfer_connecting))
                    wifi.connect(peer)
                }
                delay(HOST_TRANSFER_DISCOVERY_INTERVAL_MS)
                if (attempt == HOST_TRANSFER_DISCOVERY_ATTEMPTS - 1 &&
                    wifiTransferTarget == target &&
                    wifi.connection.value?.groupFormed != true
                ) {
            goHome(getString(R.string.host_transfer_failed))
                }
            }
        }

        LaunchedEffect(roomState.hostTransfer) {
            val plan = roomState.hostTransfer ?: return@LaunchedEffect
            val selfId = roomState.members.firstOrNull { it.isSelf }?.id ?: return@LaunchedEffect
            val action = HostTransferFlow.decide(plan, selfId)
            val previousKind = roomKind
            appCoordinator.setStatus(getString(R.string.host_transfer_in_progress))
            releaseRoom(keepWifiGroup = previousKind == RoomKind.WIFI)
            when (previousKind) {
                RoomKind.BLUETOOTH -> when (action) {
                    is HostTransferAction.BecomeHost ->
                        startBluetoothHost(action.seed, secure = false)
                    is HostTransferAction.JoinHost -> {
                        val adapter = (getSystemService(BLUETOOTH_SERVICE) as BluetoothManager).adapter
                        val device = runCatching { adapter.getRemoteDevice(action.endpoint) }.getOrElse { error ->
                        goHome(getString(R.string.host_transfer_failed_detail, error.message.orEmpty()))
                            return@LaunchedEffect
                        }
                        startBluetoothGuest(device, secure = false)
                    }
                    HostTransferAction.Ignore -> goHome(getString(R.string.host_transfer_expired))
                }
                RoomKind.WIFI -> when (action) {
                    is HostTransferAction.BecomeHost -> {
                        pendingWifiTransferSeed = action.seed
                        wifiTransferTarget = null
                        appCoordinator.setRoomRole(RoomRole.HOST)
                        appCoordinator.setHost(true)
                        roomLifecycle.clearRoomKind()
                        wifi.createGroup()
                        navigation.navigateTo(Screen.ROOM)
                    }
                    is HostTransferAction.JoinHost -> {
                        pendingWifiTransferSeed = null
                        wifiTransferTarget = action.endpoint
                        appCoordinator.setRoomRole(RoomRole.GUEST)
                        appCoordinator.setHost(false)
                        roomLifecycle.clearRoomKind()
                        wifi.disconnectAndDiscoverPeers()
                        navigation.navigateTo(Screen.ROOM)
                    }
                    HostTransferAction.Ignore -> goHome(getString(R.string.host_transfer_expired))
                }
                RoomKind.NEARBY, null -> goHome(getString(R.string.host_transfer_unsupported))
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
                    navigation.navigateTo(Screen.HOME)
                }
                Screen.SCAN -> {
                    // 先清意图再断连：否则晚到的连接广播会把人硬拖进房间。
                    appCoordinator.setRoomRole(RoomRole.NONE)
                    wifi.disconnect()
                    appCoordinator.setStatus(null)
                    navigation.navigateTo(Screen.HOME)
                }
                Screen.BLUETOOTH_SCAN -> {
                    goHome(null)
                }
                Screen.NEARBY_SCAN -> {
                    goHome(null)
                }
                Screen.HOME -> Unit
                Screen.ABOUT_UPDATE -> navigation.navigateTo(Screen.HOME)
            }
        }

        Box(Modifier.fillMaxSize().background(SunsetColors.Canvas)) {
            AnimatedContent(
                targetState = screen,
                transitionSpec = {
                    if (SunsetMotion.useImmediateScreenSwap(entryTransitionProgress.value)) {
                        EnterTransition.None togetherWith ExitTransition.None
                    } else {
                        fadeIn(tween(220, easing = FastOutSlowInEasing)) togetherWith
                            fadeOut(tween(140))
                    }
                },
                label = "app-screen-transition",
            ) { targetScreen ->
                when (targetScreen) {
            Screen.HOME -> HomeScreen(
                versionName = versionName,
                nickname = nickname,
                onNicknameChange = appCoordinator::setNickname,
                onCreateWifiRoom = { origin ->
                    permissionLaunchers.withRoomPreconditions {
                        runEntryTransition(origin) {
                            appCoordinator.setRoomRole(RoomRole.HOST)
                            appCoordinator.setHost(true)
                            roomLifecycle.setRoomKind(RoomKind.WIFI)
                            appCoordinator.setStatus(getString(R.string.establishing_wifi))
                            wifi.createGroup()
                        }
                    }
                },
                onJoinWifiRoom = {
                    permissionLaunchers.withRoomPreconditions {
                        appCoordinator.setRoomRole(RoomRole.GUEST)
                        appCoordinator.setStatus(null)
                        wifi.discoverPeers()
                        navigation.navigateTo(Screen.SCAN)
                    }
                },
                onCreateBluetoothRoom = { origin ->
                    permissionLaunchers.withBluetoothPermissions(BluetoothRoomRole.HOST) {
                        bluetooth.register()
                        val intent = bluetooth.requestDiscoverableIntent(300)
                        if (intent == null) {
                            appCoordinator.setStatus(bluetooth.lastError.value)
                        } else {
                            pendingBluetoothEntryOrigin = origin
                        launchDiscoverable(intent)
                        }
                    }
                },
                onJoinBluetoothRoom = {
                    permissionLaunchers.withBluetoothPermissions(BluetoothRoomRole.GUEST) {
                        bluetooth.register()
                        bluetooth.discoverDevices()
                        appCoordinator.setStatus(null)
                        navigation.navigateTo(Screen.BLUETOOTH_SCAN)
                    }
                },
                onCreateNearbyRoom = {
                    permissionLaunchers.withNearbyPermissions { startNearbyHost() }
                },
                onJoinNearbyRoom = {
                    permissionLaunchers.withNearbyPermissions { startNearbyDiscovery() }
                },
                 onLoopbackTest = {
                    permissionLaunchers.withMicPermission {
                        runCatching { loopback.start() }
                            .onSuccess {
                                appCoordinator.setStatus(null)
                                navigation.navigateTo(Screen.LOOPBACK)
                            }
                            .onFailure {
                                appCoordinator.setStatus(getString(R.string.loopback_failed, it.message.orEmpty()))
                                Toast.makeText(context, getString(R.string.loopback_failed, it.message.orEmpty()), Toast.LENGTH_LONG).show()
                            }
                    }
                 },
                 onAboutUpdate = { navigation.navigateTo(Screen.ABOUT_UPDATE) },
                status = status ?: wifiError ?: nearbyError,
                headerPhase = headerPhase,
                themeMode = themeMode,
                onCycleThemeMode = onCycleThemeMode,
             )

            Screen.ABOUT_UPDATE -> AboutUpdateScreen(
                versionName = versionName,
                updateState = updateState,
                onCheckUpdate = aboutUpdateCoordinator::check,
                onDownloadUpdate = aboutUpdateCoordinator::download,
                onInstallUpdate = aboutUpdateCoordinator::install,
                onExportDiagnostics = {
                    runCatching {
                        DiagnosticExporter(context).share(
                            DiagnosticReport.create(
                                appVersion = versionName,
                                androidApi = Build.VERSION.SDK_INT,
                                roomType = roomKind?.name ?: "NONE",
                                connected = roomState.connected,
                                memberCount = roomState.members.size,
                                audioQuality = roomState.audioQuality,
                                recentErrors = listOfNotNull(status, wifiError, nearbyError),
                            ),
                        )
                    }.onFailure {
                        aboutUpdateCoordinator.reportFailure(getString(R.string.diagnostics_failed, it.message.orEmpty()))
                    }
                },
                onReportIssue = {
                    runCatching {
                        DiagnosticExporter(context).openIssue(
                            DiagnosticReport.create(
                                appVersion = versionName,
                                androidApi = Build.VERSION.SDK_INT,
                                roomType = roomKind?.name ?: "NONE",
                                connected = roomState.connected,
                                memberCount = roomState.members.size,
                                audioQuality = roomState.audioQuality,
                                recentErrors = listOfNotNull(status, wifiError, nearbyError),
                            ),
                        )
                    }.onFailure {
                        aboutUpdateCoordinator.reportFailure(getString(R.string.browser_unavailable))
                    }
                },
                onOpenGithub = {
                    runCatching {
                        context.startActivity(
                            Intent(
                                Intent.ACTION_VIEW,
                                android.net.Uri.parse("https://github.com/Starlordzz/sunsetripple"),
                            ),
                        )
                    }.onFailure {
                        aboutUpdateCoordinator.reportFailure(getString(R.string.browser_unavailable))
                    }
                },
                onClose = { navigation.navigateTo(Screen.HOME) },
            )

            Screen.SCAN -> ScanScreen(
                peers = peers,
                discovering = wifiDiscovering,
                // 发现停了还挂着"扫描中"的提示条，正是让人以为还在搜的那半句。
                status = status ?: wifiError
                    ?: getString(R.string.wifi_scan_hint).takeIf { wifiDiscovering },
                onPick = { device ->
                    appCoordinator.setStatus(getString(R.string.connecting_device, device.deviceName.orEmpty().ifBlank { device.deviceAddress }))
                    wifi.connect(device)
                },
                onScanAgain = {
                    appCoordinator.setStatus(null)
                    wifi.discoverPeers()
                },
                onBack = {
                    appCoordinator.setRoomRole(RoomRole.NONE)
                    wifi.disconnect()
                    appCoordinator.setStatus(null)
                    navigation.navigateTo(Screen.HOME)
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
                    appCoordinator.setStatus(getString(R.string.confirm_system_pairing))
                        runCatching { device.createBond() }
                        .onFailure { appCoordinator.setStatus(getString(R.string.pair_failed, it.message.orEmpty())) }
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
                securityCode = deviceIdentity.shortCode,
                roomLabel = when (roomKind) {
                    RoomKind.BLUETOOTH -> if (isHost) bluetoothHostLabel else bluetoothGuestLabel
                    RoomKind.NEARBY -> if (isHost) nearbyHostLabel else nearbyGuestLabel
                    else -> if (isHost) wifiHostLabel else wifiGuestLabel
                },
                speakerOn = speakerOn,
                onToggleMute = {
                    session?.setMicMuted(!roomState.micMuted)
                    CallForegroundService.refresh()
                },
                onToggleSpeaker = {
                    appCoordinator.setSpeaker(!speakerOn)
                    setSpeaker(!speakerOn)
                },
                onLeave = { goHome(null) },
                onPttChanged = if (roomKind == RoomKind.BLUETOOTH) {
                    { pressed ->
                        bluetoothSession?.setPttPressed(pressed)
                        CallForegroundService.refresh()
                    }
                } else null,
                headerPhase = headerPhase,
            )

            Screen.LOOPBACK -> LoopbackScreen(
                onStop = {
                    loopback.stop()
                    navigation.navigateTo(Screen.HOME)
                },
            )
                }
            }
            if (entryPreviewVisible) {
                RoomScreen(
                    modifier = Modifier
                        .fillMaxSize()
                        .sunsetCircularReveal(
                            progress = entryTransitionProgressState,
                            origin = entryTransitionOrigin,
                            edgeColor = SunsetColors.Sun,
                        )
                        .pointerInput(Unit) {
                            awaitPointerEventScope {
                                while (true) {
                                    awaitPointerEvent().changes.forEach { it.consume() }
                                }
                            }
                        },
                    state = roomState,
                    securityCode = deviceIdentity.shortCode,
                    roomLabel = when (roomKind) {
                        RoomKind.BLUETOOTH -> if (isHost) bluetoothHostLabel else bluetoothGuestLabel
                        RoomKind.NEARBY -> if (isHost) nearbyHostLabel else nearbyGuestLabel
                        else -> if (isHost) wifiHostLabel else wifiGuestLabel
                    },
                    speakerOn = speakerOn,
                    onToggleMute = {},
                    onToggleSpeaker = {},
                    onLeave = {},
                    onPttChanged = if (roomKind == RoomKind.BLUETOOTH) ({ _ -> }) else null,
                    entryProgress = entryTransitionProgressState,
                    headerPhase = headerPhase,
                )
            }
        }
    }

    private val wifiHostLabel get() = getString(R.string.room_wifi_host)
    private val wifiGuestLabel get() = getString(R.string.room_wifi_guest)
    private val bluetoothHostLabel get() = getString(R.string.room_bluetooth_host)
    private val bluetoothGuestLabel get() = getString(R.string.room_bluetooth_guest)
    private val nearbyHostLabel get() = getString(R.string.room_nearby_host)
    private val nearbyGuestLabel get() = getString(R.string.room_nearby_guest)

    private companion object {
        const val STATE_SCREEN = "screen"
        const val UNKNOWN_P2P_ADDRESS = "02:00:00:00:00:00"
        const val HOST_TRANSFER_DISCOVERY_ATTEMPTS = 10
        const val HOST_TRANSFER_DISCOVERY_INTERVAL_MS = 3_000L
    }
}
