package com.wt.intercom.service

import android.annotation.SuppressLint
import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
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
 * 服务不持有会话对象——它只负责"让系统别把我们冻了"，房间生命周期仍归 [MainActivity]。
 * 通知的「离开」按钮通过 [ACTION_LEAVE] 回到 Activity 走正常离房流程。
 */
class CallForegroundService : Service() {

    private var wifiLock: WifiManager.WifiLock? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val label = intent?.getStringExtra(EXTRA_LABEL) ?: DEFAULT_LABEL
        ensureChannel()
        try {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                buildNotification(label),
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
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
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

    private fun buildNotification(label: String): Notification {
        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        val open = PendingIntent.getActivity(
            this,
            REQ_OPEN,
            Intent(this, MainActivity::class.java)
                .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            flags,
        )
        val leave = PendingIntent.getActivity(
            this,
            REQ_LEAVE,
            Intent(this, MainActivity::class.java)
                .setAction(ACTION_LEAVE)
                .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            flags,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            // 工程没有 res 目录，用系统自带的麦克风图标，避免为一个图标引入资源体系。
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle(APP_NAME)
            .setContentText(label)
            .setOngoing(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(open)
            .addAction(0, "离开", leave)
            .build()
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
        /** 通知栏「离开」按钮回传给 Activity 的动作。 */
        const val ACTION_LEAVE = "com.wt.intercom.action.LEAVE_ROOM"

        private const val APP_NAME = "落日后残波"
        private const val DEFAULT_LABEL = "通话中"
        private const val EXTRA_LABEL = "room_label"
        private const val CHANNEL_ID = "room_call"
        private const val NOTIFICATION_ID = 1001
        private const val REQ_OPEN = 0
        private const val REQ_LEAVE = 1
        private const val LOCK_PREFIX = "SunsetRipple"

        /** 进房时调用；失败只记日志，不能因为通知起不来就把通话掐了。 */
        fun start(context: Context, label: String) {
            val intent = Intent(context, CallForegroundService::class.java).putExtra(EXTRA_LABEL, label)
            runCatching { ContextCompat.startForegroundService(context, intent) }
                .onFailure { TransportLog.w("前台服务拉起失败: ${it.message}", it) }
        }

        /** 离房时调用；幂等。 */
        fun stop(context: Context) {
            runCatching { context.stopService(Intent(context, CallForegroundService::class.java)) }
                .onFailure { TransportLog.w("前台服务停止失败: ${it.message}", it) }
        }
    }
}
