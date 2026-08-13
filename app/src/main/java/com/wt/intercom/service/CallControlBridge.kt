package com.wt.intercom.service

internal class CallControlBridge {
    private var stateProvider: (() -> CallNotificationState?)? = null
    private var onControl: (() -> Unit)? = null
    private var onLeave: (() -> Unit)? = null

    @Synchronized
    fun attach(
        stateProvider: () -> CallNotificationState?,
        onControl: () -> Unit,
        onLeave: () -> Unit,
    ) {
        this.stateProvider = stateProvider
        this.onControl = onControl
        this.onLeave = onLeave
    }

    @Synchronized
    fun clear() {
        stateProvider = null
        onControl = null
        onLeave = null
    }

    fun currentState(): CallNotificationState? = synchronized(this) { stateProvider }?.invoke()

    fun control(): CallNotificationState? {
        synchronized(this) { onControl }?.invoke()
        return currentState()
    }

    fun leave() {
        synchronized(this) { onLeave }?.invoke()
    }
}

internal object ActiveCallControls {
    private val bridge = CallControlBridge()

    fun attach(
        stateProvider: () -> CallNotificationState?,
        onControl: () -> Unit,
        onLeave: () -> Unit,
    ) = bridge.attach(stateProvider, onControl, onLeave)

    fun clear() = bridge.clear()
    fun currentState(): CallNotificationState? = bridge.currentState()
    fun control(): CallNotificationState? = bridge.control()
    fun leave() = bridge.leave()
}
