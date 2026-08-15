package host.msknet.sunsetripple.transport

import android.util.Log

/**
 * 传输层的告警出口。默认写 Android Logcat，
 * JVM 单元测试可替换 [sink] 断言"错误没有被静默吞掉"。
 */
object TransportLog {

    private const val TAG = "Transport"

    @Volatile
    var sink: (String, Throwable?) -> Unit = { msg, t ->
        runCatching { Log.w(TAG, msg, t) }   // 单测环境无 android.util.Log 实现时退化为静默
            .onFailure { println("[$TAG] $msg${t?.let { e -> " : $e" } ?: ""}") }
    }

    fun w(msg: String, t: Throwable? = null) = sink(msg, t)
}
