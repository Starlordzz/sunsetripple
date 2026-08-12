package com.wt.intercom.transport.bluetooth

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import androidx.annotation.RequiresPermission
import com.wt.intercom.protocol.Frame
import com.wt.intercom.session.Roster
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID

interface BluetoothRoomTransport {
    val isHost: Boolean
    fun start()
    fun sendTo(memberId: Int, frame: Frame)
    fun broadcastSignal(frame: Frame)
    fun close()
}

interface BluetoothRoomTransportListener {
    fun onFrame(frame: Frame)
    fun onRoster(roster: Roster)
    fun onDisconnected(reason: String)
}

internal interface BluetoothConnection {
    val remoteAddress: String
    val input: InputStream
    val output: OutputStream
    fun close()
}

internal interface BluetoothConnectionServer {
    fun accept(): BluetoothConnection
    fun close()
}

internal class AndroidBluetoothConnection(
    private val socket: BluetoothSocket,
) : BluetoothConnection {
    override val remoteAddress: String get() = socket.remoteDevice.address
    override val input: InputStream get() = socket.inputStream
    override val output: OutputStream get() = socket.outputStream
    override fun close() = socket.close()
}

internal class AndroidBluetoothConnectionServer(
    private val server: BluetoothServerSocket,
) : BluetoothConnectionServer {
    override fun accept(): BluetoothConnection = AndroidBluetoothConnection(server.accept())
    override fun close() = server.close()
}

internal object BluetoothRoomRfcomm {
    val UUID: UUID = java.util.UUID.fromString("7f75d4e0-7a46-4d74-9f8d-1e4bc5e4b003")
    const val SERVICE_NAME = "SunsetRipple Bluetooth Room"

    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    fun server(adapter: BluetoothAdapter): BluetoothConnectionServer = AndroidBluetoothConnectionServer(
        adapter.listenUsingRfcommWithServiceRecord(SERVICE_NAME, UUID),
    )

    @RequiresPermission(Manifest.permission.BLUETOOTH_CONNECT)
    fun client(device: BluetoothDevice): BluetoothConnection = AndroidBluetoothConnection(
        device.createRfcommSocketToServiceRecord(UUID).apply { connect() },
    )
}
