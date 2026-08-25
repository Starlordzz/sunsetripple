package host.msknet.sunsetripple

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log

/**
 * 通话期间的前台服务。
 *
 * 没有它，应用一退到后台，系统就会在几十秒内回收麦克风采集与网络 socket，
 * 表现为「切出去看一眼消息，回来对讲就断了」。
 *
 * Android 14（API 34）起，microphone 类型的前台服务必须在应用处于前台时启动，
 * 且已经持有 RECORD_AUDIO——这里由「创建/加入房间」这个用户操作触发，满足条件。
 */
class IntercomForegroundService : Service() {

    companion object {
        private const val TAG = "SunsetFgs"
        private const val CHANNEL_ID = "sunsetripple_intercom"
        private const val NOTIFICATION_ID = 4802

        fun start(context: Context) {
            val intent = Intent(context, IntercomForegroundService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                // Android 12+ 有后台启动限制；失败不该让通话本身崩掉。
                Log.e(TAG, "启动前台服务失败，后台可能会被系统掐断音频", e)
            }
        }

        fun stop(context: Context) {
            try {
                context.stopService(Intent(context, IntercomForegroundService::class.java))
            } catch (e: Exception) {
                Log.w(TAG, "停止前台服务失败", e)
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    buildNotification(),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
                )
            } else {
                startForeground(NOTIFICATION_ID, buildNotification())
            }
        } catch (e: Exception) {
            Log.e(TAG, "startForeground 失败", e)
            stopSelf()
            return START_NOT_STICKY
        }
        // 通话是一次性的，被系统杀掉后不要自动重启一个空会话。
        return START_NOT_STICKY
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            "对讲进行中",
            NotificationManager.IMPORTANCE_LOW, // 不出声、不震动，避免干扰通话
        ).apply {
            description = "对讲通话期间保持麦克风与连接不被系统回收"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("落日后残波")
            .setContentText("对讲进行中")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_CALL)
            .build()
    }
}
