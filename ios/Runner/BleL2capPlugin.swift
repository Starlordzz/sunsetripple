import Flutter
import UIKit
import CoreBluetooth

public final class BleL2capPlugin: NSObject, FlutterPlugin {

    private static let methodChannelName = "host.msknet.sunsetripple/ble_l2cap"
    private static let dataChannelName = "host.msknet.sunsetripple/ble_l2cap_data"
    private static let scanChannelName = "host.msknet.sunsetripple/ble_l2cap_scan"

    public static let serviceUuid = CBUUID(string: "7f75d4e0-7a46-4d74-9f8d-1e4bc5e4b004")
    public static let companyId: UInt16 = 0xFFFF

    private var methodChannel: FlutterMethodChannel?
    private var dataEventChannel: FlutterEventChannel?
    private var scanEventChannel: FlutterEventChannel?

    private var dataEventSink: FlutterEventSink?
    private var scanEventSink: FlutterEventSink?

    // CoreBluetooth 管理器
    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?

    // 房主 (Host / Peripheral) 状态
    private var isHosting: Bool = false
    private var publishedPsm: CBL2CAPPSM?
    private var hostRoomName: String = ""
    private var hostChannels: [CBL2CAPChannel] = []
    private var advertisedMemberCount: Int = 1
    private var inputBuffers: [ObjectIdentifier: Data] = [:]
    private var pendingWrites: [ObjectIdentifier: Data] = [:]
    private var streamPeerAddresses: [ObjectIdentifier: String] = [:]

    // 成员 (Client / Central) 状态
    private var isScanning: Bool = false
    private var targetPsm: CBL2CAPPSM?
    private var targetPeripheral: CBPeripheral?
    private var clientChannel: CBL2CAPChannel?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = BleL2capPlugin()
        instance.setupChannels(messenger: registrar.messenger())
    }

    public func setupChannels(messenger: FlutterBinaryMessenger) {
        let mChannel = FlutterMethodChannel(name: BleL2capPlugin.methodChannelName, binaryMessenger: messenger)
        mChannel.setMethodCallHandler(self.handle)
        self.methodChannel = mChannel

        let dChannel = FlutterEventChannel(name: BleL2capPlugin.dataChannelName, binaryMessenger: messenger)
        dChannel.setStreamHandler(DataStreamHandler(plugin: self))
        self.dataEventChannel = dChannel

        let sChannel = FlutterEventChannel(name: BleL2capPlugin.scanChannelName, binaryMessenger: messenger)
        sChannel.setStreamHandler(ScanStreamHandler(plugin: self))
        self.scanEventChannel = sChannel
    }

    public func detachChannels() {
        stopHost()
        disconnect()
        stopScan()
        methodChannel?.setMethodCallHandler(nil)
        methodChannel = nil
        dataEventChannel?.setStreamHandler(nil)
        dataEventChannel = nil
        scanEventChannel?.setStreamHandler(nil)
        scanEventChannel = nil
    }

    // MARK: - FlutterMethodCallHandler

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isSupported":
            let supported = (centralManager?.state == .poweredOn || centralManager == nil)
            result(supported)

        case "startAdvertising", "startHost":
            guard let args = call.arguments as? [String: Any],
                  let roomName = args["roomName"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "缺少房间名称参数", details: nil))
                return
            }
            startHost(roomName: roomName) { success in
                result(success)
            }

        case "stopHost":
            stopHost()
            result(true)

        case "startScan":
            startScan()
            result(true)

        case "stopScan":
            stopScan()
            result(true)

        case "connectL2cap", "connect":
            guard let args = call.arguments as? [String: Any],
                  let address = (args["address"] as? String) ?? (args["deviceAddress"] as? String),
                  let psm = args["psm"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "缺少连接参数", details: nil))
                return
            }
            connect(address: address, psm: psm) { success in
                result(success)
            }

        case "stop":
            stopHost()
            disconnect()
            stopScan()
            result(true)

        case "disconnect":
            disconnect()
            result(true)

        case "sendL2capData", "sendFrame":
            guard let args = call.arguments as? [String: Any],
                  let typedData = args["data"] as? FlutterStandardTypedData else {
                result(false)
                return
            }
            let success = sendFrame(data: typedData.data)
            result(success)

        case "updateMemberCount":
            advertisedMemberCount = max(1, min(6, (call.arguments as? [String: Any])?["memberCount"] as? Int ?? 1))
            if isHosting {
                peripheralManager?.stopAdvertising()
                advertiseHost()
            }
            result(true)

        case "dispose":
            detachChannels()
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - 房主 (Host Peripheral) 逻辑

    private var hostCompletion: ((Bool) -> Void)?

    private func startHost(roomName: String, completion: @escaping (Bool) -> Void) {
        self.hostRoomName = roomName
        self.advertisedMemberCount = 1
        self.hostCompletion = completion
        self.isHosting = true

        if peripheralManager == nil {
            peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        } else if peripheralManager?.state == .poweredOn {
            peripheralManager?.publishL2CAPChannel(withEncryption: false)
        }
    }

    private func stopHost() {
        isHosting = false
        if let psm = publishedPsm {
            peripheralManager?.unpublishL2CAPChannel(psm)
            publishedPsm = nil
        }
        peripheralManager?.stopAdvertising()
        for channel in hostChannels {
            channel.inputStream.close()
            channel.outputStream.close()
            inputBuffers.removeValue(forKey: ObjectIdentifier(channel.inputStream))
            pendingWrites.removeValue(forKey: ObjectIdentifier(channel.outputStream))
            streamPeerAddresses.removeValue(forKey: ObjectIdentifier(channel.inputStream))
        }
        hostChannels.removeAll()
    }

    // MARK: - 成员 (Central Client) 逻辑

    private var connectCompletion: ((Bool) -> Void)?

    private func startScan() {
        isScanning = true
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        } else if centralManager?.state == .poweredOn {
            centralManager?.scanForPeripherals(
                withServices: [BleL2capPlugin.serviceUuid],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
        }
    }

    private func stopScan() {
        isScanning = false
        centralManager?.stopScan()
    }

    private func connect(address: String, psm: Int, completion: @escaping (Bool) -> Void) {
        guard let central = centralManager, central.state == .poweredOn else {
            completion(false)
            return
        }

        self.targetPsm = CBL2CAPPSM(psm)
        self.connectCompletion = completion

        if let uuid = UUID(uuidString: address),
           let peripheral = central.retrievePeripherals(withIdentifiers: [uuid]).first {
            self.targetPeripheral = peripheral
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        } else {
            completion(false)
        }
    }

    private func disconnect() {
        if let client = clientChannel {
            client.inputStream.close()
            client.outputStream.close()
            inputBuffers.removeValue(forKey: ObjectIdentifier(client.inputStream))
            pendingWrites.removeValue(forKey: ObjectIdentifier(client.outputStream))
            streamPeerAddresses.removeValue(forKey: ObjectIdentifier(client.inputStream))
            clientChannel = nil
        }
        if let p = targetPeripheral {
            centralManager?.cancelPeripheralConnection(p)
            targetPeripheral = nil
        }
    }

    // MARK: - 帧发送

    private func sendFrame(data: Data) -> Bool {
        if isHosting {
            var allSent = true
            for channel in hostChannels {
                if !writeToStream(channel.outputStream, data: data) {
                    allSent = false
                }
            }
            return allSent
        } else if let channel = clientChannel {
            return writeToStream(channel.outputStream, data: data)
        }
        return false
    }

    private func writeToStream(_ stream: OutputStream, data: Data) -> Bool {
        let key = ObjectIdentifier(stream)
        var pending = pendingWrites[key] ?? Data()
        pending.append(data)
        pendingWrites[key] = pending
        drainWrites(stream)
        return true
    }

    private func drainWrites(_ stream: OutputStream) {
        let key = ObjectIdentifier(stream)
        while stream.hasSpaceAvailable,
              var pending = pendingWrites[key],
              !pending.isEmpty {
            let written = pending.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> Int in
                guard let baseAddress = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return 0
                }
                return stream.write(baseAddress, maxLength: pending.count)
            }
            if written <= 0 {
                return
            }
            pending.removeFirst(written)
            if pending.isEmpty {
                pendingWrites.removeValue(forKey: key)
            } else {
                pendingWrites[key] = pending
            }
        }
    }

    // MARK: - 数据接收转发

    fileprivate func handleReceivedData(_ data: Data, from inputStream: InputStream) {
        if isHosting {
            for channel in hostChannels where channel.inputStream !== inputStream {
                _ = writeToStream(channel.outputStream, data: data)
            }
        }
        let peerAddress = streamPeerAddresses[ObjectIdentifier(inputStream)] ?? "unknown"
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let sink = self.dataEventSink else { return }
            sink([
                "data": FlutterStandardTypedData(bytes: data),
                "peerAddress": peerAddress,
            ])
        }
    }

    fileprivate func setScanSink(_ sink: FlutterEventSink?) {
        self.scanEventSink = sink
    }

    fileprivate func setDataSink(_ sink: FlutterEventSink?) {
        self.dataEventSink = sink
    }
}

// MARK: - CBPeripheralManagerDelegate (房主模式)

extension BleL2capPlugin: CBPeripheralManagerDelegate {
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn && isHosting {
            peripheral.publishL2CAPChannel(withEncryption: false)
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didPublishL2CAPChannel PSM: CBL2CAPPSM, error: Error?) {
        if let error = error {
            print("[SunsetBLE] 发布 L2CAP 通道失败: \(error)")
            hostCompletion?(false)
            hostCompletion = nil
            return
        }

        self.publishedPsm = PSM
        print("[SunsetBLE] 成功发布 L2CAP PSM: \(PSM)")

        advertiseHost()
        hostCompletion?(true)
        hostCompletion = nil
    }

    private func advertiseHost() {
        guard let psm = publishedPsm, isHosting else { return }
        // 构造广播数据（Service UUID + LocalName 包含房间名、PSM 和人数）
        let advData: [String: Any] = [
            CBAdvertisementDataServiceUUIDsKey: [BleL2capPlugin.serviceUuid],
            CBAdvertisementDataLocalNameKey: "SR_\(psm)_\(advertisedMemberCount)_\(hostRoomName)"
        ]
        peripheralManager?.startAdvertising(advData)
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didOpen channel: CBL2CAPChannel?, error: Error?) {
        guard let channel = channel, error == nil else { return }
        print("[SunsetBLE] 收到成员接入 L2CAP 通道")
        channel.inputStream.delegate = self
        channel.outputStream.delegate = self
        channel.inputStream.schedule(in: .main, forMode: .common)
        channel.outputStream.schedule(in: .main, forMode: .common)
        channel.inputStream.open()
        channel.outputStream.open()
        let key = ObjectIdentifier(channel.inputStream)
        streamPeerAddresses[key] = "host-\(key)"
        hostChannels.append(channel)
    }
}

// MARK: - CBCentralManagerDelegate & CBPeripheralDelegate (成员模式)

extension BleL2capPlugin: CBCentralManagerDelegate, CBPeripheralDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn && isScanning {
            startScan()
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let advertisement = parseAdvertisement(advertisementData) else { return }
        let psm = advertisement.psm
        let memberCount = advertisement.memberCount
        let roomName = advertisement.roomName

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let sink = self.scanEventSink else { return }
            sink([
                "name": roomName,
                "address": peripheral.identifier.uuidString,
                "rssi": RSSI.intValue,
                "psm": psm,
                "memberCount": memberCount
            ])
        }
    }

    private func parseAdvertisement(_ advertisementData: [String: Any]) -> (psm: Int, memberCount: Int, roomName: String)? {
        if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String,
           localName.hasPrefix("SR_") {
            let parts = localName.split(separator: "_", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count >= 3, let psm = Int(parts[1]), psm > 0 else { return nil }
            if parts.count >= 4, let count = Int(parts[2]) {
                return (psm, max(1, min(6, count)), String(parts[3]))
            }
            return (psm, 1, String(parts[2]))
        }

        // 兼容 Android：厂商数据为 [PSM 高字节][PSM 低字节][人数][UTF-8 房名]。
        guard var data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              data.count >= 3 else { return nil }
        if data.count >= 5 {
            let companyId = UInt16(data[0]) | (UInt16(data[1]) << 8)
            if companyId == BleL2capPlugin.companyId {
                data = Data(data.dropFirst(2))
            }
        }
        guard data.count >= 3 else { return nil }
        let psm = (Int(data[0]) << 8) | Int(data[1])
        guard psm > 0 else { return nil }
        let memberCount = max(1, min(6, Int(data[2])))
        let roomName = data.count > 3
            ? String(data: data.dropFirst(3), encoding: .utf8) ?? "蓝牙房"
            : "蓝牙房"
        return (psm, memberCount, roomName)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let psm = targetPsm else { return }
        print("[SunsetBLE] 蓝牙连接建立，正在打开 L2CAP 通道 PSM: \(psm)")
        peripheral.openL2CAPChannel(psm)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("[SunsetBLE] 蓝牙连接失败: \(String(describing: error))")
        connectCompletion?(false)
        connectCompletion = nil
    }

    public func peripheral(_ peripheral: CBPeripheral, didOpen channel: CBL2CAPChannel?, error: Error?) {
        guard let channel = channel, error == nil else {
            print("[SunsetBLE] 打开 L2CAP 通道失败: \(String(describing: error))")
            connectCompletion?(false)
            connectCompletion = nil
            return
        }

        self.clientChannel = channel
        let key = ObjectIdentifier(channel.inputStream)
        streamPeerAddresses[key] = targetPeripheral?.identifier.uuidString ?? "ble-peer"
        channel.inputStream.delegate = self
        channel.outputStream.delegate = self
        channel.inputStream.schedule(in: .main, forMode: .common)
        channel.outputStream.schedule(in: .main, forMode: .common)
        channel.inputStream.open()
        channel.outputStream.open()

        connectCompletion?(true)
        connectCompletion = nil
    }
}

// MARK: - StreamDelegate (L2CAP 双向字节流)

extension BleL2capPlugin: StreamDelegate {
    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .hasBytesAvailable:
            guard let inputStream = aStream as? InputStream else { return }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while inputStream.hasBytesAvailable {
                let bytesRead = inputStream.read(&buffer, maxLength: buffer.count)
                if bytesRead <= 0 { break }
                consumeInput(Data(buffer[0..<bytesRead]), from: inputStream)
                if bytesRead < buffer.count { break }
            }
        case .hasSpaceAvailable:
            guard let outputStream = aStream as? OutputStream else { return }
            drainWrites(outputStream)
        case .errorOccurred:
            print("[SunsetBLE] Stream 异常: \(String(describing: aStream.streamError))")
            cleanupStream(aStream)
        case .endEncountered:
            print("[SunsetBLE] Stream 对端关闭")
            cleanupStream(aStream)
        default:
            break
        }
    }

    private func consumeInput(_ data: Data, from inputStream: InputStream) {
        let key = ObjectIdentifier(inputStream)
        var pending = inputBuffers[key] ?? Data()
        pending.append(data)

        while pending.count >= 6 {
            let payloadLength = (Int(pending[4]) << 8) | Int(pending[5])
            if payloadLength > 512 {
                print("[SunsetBLE] 收到超长帧，丢弃当前输入缓冲")
                pending.removeAll(keepingCapacity: false)
                break
            }
            let totalLength = 6 + payloadLength
            if pending.count < totalLength { break }
            let frame = Data(pending.prefix(totalLength))
            pending.removeFirst(totalLength)
            handleReceivedData(frame, from: inputStream)
        }

        inputBuffers[key] = pending
    }

    private func cleanupStream(_ stream: Stream) {
        if let inputStream = stream as? InputStream {
            let key = ObjectIdentifier(inputStream)
            inputBuffers.removeValue(forKey: key)
            streamPeerAddresses.removeValue(forKey: key)
            hostChannels.removeAll { $0.inputStream === inputStream }
            if clientChannel?.inputStream === inputStream {
                clientChannel = nil
            }
        }
        pendingWrites.removeValue(forKey: ObjectIdentifier(stream))
    }
}

// MARK: - 内部 EventStreamHandler 包装

private final class DataStreamHandler: NSObject, FlutterStreamHandler {
    private weak var plugin: BleL2capPlugin?
    init(plugin: BleL2capPlugin) { self.plugin = plugin }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        plugin?.setDataSink(events)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        plugin?.setDataSink(nil)
        return nil
    }
}

private final class ScanStreamHandler: NSObject, FlutterStreamHandler {
    private weak var plugin: BleL2capPlugin?
    init(plugin: BleL2capPlugin) { self.plugin = plugin }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        plugin?.setScanSink(events)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        plugin?.setScanSink(nil)
        return nil
    }
}
