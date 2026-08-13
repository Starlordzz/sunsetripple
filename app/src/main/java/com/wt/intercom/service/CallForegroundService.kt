package com.wt.intercom.service

import android.Manifest
import android.annotation.SuppressLint
import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.wt.intercom.MainActivity
import com.wt.intercom.transport.TransportLog

/**
 * 通话期间的 microphone 类型前台服务（规格 5.1）：
 * 锁屏/切后台仍持续对讲，通知栏常驻房间名与「离开」按钮，并持有 WifiLock + 部分 WakeLock。
 *
 * 服务不持有会话对象；通知动作通过进程内控制桥调用当前会话，房间资源所有权仍归 [MainActivity]。
 */
class CallForegroundService : Service() {

    private var wifiLock: WifiManager.WifiLock? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        activeService = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONTROL -> {
                val state = ActiveCallControls.control()
                if (state != null) refreshNotification(state) else stopSelf()
                return START_NOT_STICKY
            }
            ACTION_LEAVE -> {
                ActiveCallControls.leave()
                stopSelf()
                return START_NOT_STICKY
            }
        }
        val fallback = intent?.toNotificationState()
            ?: CallNotificationState(DEFAULT_LABEL, CallMode.FULL_DUPLEX)
        val state = initialNotificationState(ActiveCallControls.currentState(), fallback)
        ensureChannel()
        try {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                buildNotification(state),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } catch (e: Exception) {
            // Android 12+ 的后台启动限制、14+ 缺 RECORD_AUDIO 都会在这里抛。
            // 通话本身还能继续（Activity 在前台），但服务必须自己退干净，否则 5s 内没
            // startForeground 会被系统判为 ANR/崩溃。
            TransportLog.w("前台服务启动失败: ${e.message}", e)
            stopSelf()
            return START_NOT_STICKY
        }
        acquireLocks()
        return START_NOT_STICKY
    }

    /** 用户从最近任务划掉 App：Activity 可能来不及 onDestroy，服务自己收尸，别留僵尸通知。 */
    override fun onTaskRemoved(rootIntent: Intent?) {
        ActiveCallControls.leave()
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        if (activeService === this) activeService = null
        releaseLocks()
        super.onDestroy()
    }

    private fun ensureChannel() {
        val channel = NotificationChannelCompat.Builder(CHANNEL_ID, NotificationManagerCompat.IMPORTANCE_LOW)
            .setName("通话中")
            .setDescription("对讲进行中的常驻通知")
            .setShowBadge(false)
            .build()
        NotificationManagerCompat.from(this).createNotificationChannel(channel)
    }

    private fun buildNotification(state: CallNotificationState): Notification {
        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        val open = PendingIntent.getActivity(
            this,
            REQ_OPEN,
            Intent(this, MainActivity::class.java)
                .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            flags,
        )
        val leave = PendingIntent.getService(
            this,
            REQ_LEAVE,
            Intent(this, CallForegroundService::class.java).setAction(ACTION_LEAVE),
            flags,
        )
        val control = PendingIntent.getService(
            this,
            REQ_CONTROL,
            Intent(this, CallForegroundService::class.java).setAction(ACTION_CONTROL),
            flags,
        )
        val content = when {
            state.audioFocusInterrupted -> "只听模式 · ${state.label}"
            state.mode == CallMode.PUSH_TO_TALK && state.pttActive -> "正在说话 · ${state.label}"
            state.mode == CallMode.FULL_DUPLEX && state.micMuted -> "麦克风已静音 · ${state.label}"
            else -> state.label
        }
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle(APP_NAME)
            .setContentText(content)
            .setOngoing(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(open)
        state.controlLabel()?.let { builder.addAction(0, it, control) }
        return builder.addAction(0, "离开", leave).build()
    }

    private fun refreshNotification(state: CallNotificationState) {
        ensureChannel()
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            TransportLog.w("通知权限已撤销，无法刷新锁屏对讲控制")
            return
        }
        runCatching {
            NotificationManagerCompat.from(this).notify(NOTIFICATION_ID, buildNotification(state))
        }.onFailure { TransportLog.w("通话通知刷新失败: ${it.message}", it) }
    }

    private fun Intent.toNotificationState(): CallNotificationState? {
        val label = getStringExtra(EXTRA_LABEL) ?: return null
        val mode = getStringExtra(EXTRA_MODE)?.let { runCatching { CallMode.valueOf(it) }.getOrNull() }
            ?: return null
        return CallNotificationState(label, mode)
    }

    /**
     * WifiLock 保住 WiFi 不在灭屏后降频/断开，WakeLock 保住 CPU 跑得动音频线程。
     * 两者都是 acquire 一次、随服务销毁释放，所以关掉引用计数。
     */
    @SuppressLint("WakelockTimeout")
    private fun acquireLocks() {
        if (wifiLock == null) {
            runCatching {
                val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                } else {
                    @Suppress("DEPRECATION")
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF
                }
                wm.createWifiLock(mode, "$LOCK_PREFIX:wifi").apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }.onSuccess { wifiLock = it }
                .onFailure { TransportLog.w("WifiLock 获取失败: ${it.message}", it) }
        }
        if (wakeLock == null) {
            runCatching {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$LOCK_PREFIX:call").apply {
                    setReferenceCounted(false)
                    // 无超时：通话时长不可预知，释放靠 onDestroy（服务随离房停止）。
                    acquire()
                }
            }.onSuccess { wakeLock = it }
                .onFailure { TransportLog.w("WakeLock 获取失败: ${it.message}", it) }
        }
    }

    private fun releaseLocks() {
        wifiLock?.let { lock ->
            runCatching { if (lock.isHeld) lock.release() }
                .onFailure { TransportLog.w("WifiLock 释放失败: ${it.message}", it) }
        }
        wifiLock = null
        wakeLock?.let { lock ->
            runCatching { if (lock.isHeld) lock.release() }
                .onFailure { TransportLog.w("WakeLock 释放失败: ${it.message}", it) }
        }
        wakeLock = null
    }

    companion object {
        /** 通知栏「离开」按钮直接交给前台服务处理。 */
        const val ACTION_LEAVE = "com.wt.intercom.action.LEAVE_ROOM"
        private const val ACTION_CONTROL = "com.wt.intercom.action.TOGGLE_CALL_CONTROL"

        private const val APP_NAME = "落日后残波"
        private const val DEFAULT_LABEL = "通话中"
        private const val EXTRA_LABEL = "room_label"
        private const val EXTRA_MODE = "call_mode"
        private const val CHANNEL_ID = "room_call"
        private const val NOTIFICATION_ID = 1001
        private const val REQ_OPEN = 0
        private const val REQ_LEAVE = 1
        private const val REQ_CONTROL = 2
        private const val LOCK_PREFIX = "SunsetRipple"
        @Volatile private var activeService: CallForegroundService? = null

        /** 进房时调用；失败只记日志，不能因为通知起不来就把通话掐了。 */
        fun start(context: Context, state: CallNotificationState) {
            val intent = Intent(context, CallForegroundService::class.java)
                .putExtra(EXTRA_LABEL, state.label)
                .putExtra(EXTRA_MODE, state.mode.name)
            runCatching { ContextCompat.startForegroundService(context, intent) }
                .onFailure { TransportLog.w("前台服务拉起失败: ${it.message}", it) }
        }

        fun refresh() {
            val update = Runnable {
                val service = activeService ?: return@Runnable
                ActiveCallControls.currentState()?.let(service::refreshNotification)
            }
            if (Looper.myLooper() == Looper.getMainLooper()) update.run()
            else Handler(Looper.getMainLooper()).post(update)
        }

        /** 离房时调用；幂等。 */
        fun stop(context: Context) {
            runCatching { context.stopService(Intent(context, CallForegroundService::class.java)) }
                .onFailure { TransportLog.w("前台服务停止失败: ${it.message}", it) }
        }
    }
}
