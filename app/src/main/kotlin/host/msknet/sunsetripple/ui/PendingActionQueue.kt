package host.msknet.sunsetripple.ui

class PendingActionQueue<T> {
    private var pending: T? = null

    fun replace(value: T) {
        pending = value
    }

    fun take(): T? = pending.also { pending = null }
}
