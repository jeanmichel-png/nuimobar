import CoreBluetooth
import Foundation

/// Talks to a Senic Nuimo over Bluetooth LE: finds it, keeps it connected,
/// turns its notifications into gestures and writes frames to its LED matrix.
final class NuimoDevice: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    enum State: String {
        case starting = "Starting…"
        case bluetoothOff = "Bluetooth is off"
        case unauthorized = "Bluetooth permission needed"
        case scanning = "Searching for Nuimo…"
        case connecting = "Connecting…"
        case connected = "Connected"
    }

    /// One full turn of the dial reports roughly this many units.
    static let unitsPerTurn = 2650.0

    @Published private(set) var state: State = .starting
    @Published private(set) var battery: Int?
    @Published private(set) var firmware: String?

    var onGesture: ((Gesture) -> Void)?
    var onRotate: ((Int) -> Void)?
    var onConnect: (() -> Void)?
    /// Height of a hand above the Nuimo, 0...250, while it hovers in range.
    var onHover: ((Int) -> Void)?
    /// Undecoded bytes from the button, touch and fly sensors, for diagnostics.
    var onRaw: ((String, [UInt8]) -> Void)?

    private enum ID {
        static let battery = CBUUID(string: "2A19")
        static let firmware = CBUUID(string: "2A26")
        static let led = CBUUID(string: "F29B1524-CB19-40F3-BE5C-7241ECB82FD1")
        static let button = CBUUID(string: "F29B1529-CB19-40F3-BE5C-7241ECB82FD2")
        static let fly = CBUUID(string: "F29B1526-CB19-40F3-BE5C-7241ECB82FD2")
        static let swipe = CBUUID(string: "F29B1527-CB19-40F3-BE5C-7241ECB82FD2")
        static let rotation = CBUUID(string: "F29B1528-CB19-40F3-BE5C-7241ECB82FD2")
        static let flyCalibration = CBUUID(string: "F29B152C-CB19-40F3-BE5C-7241ECB82FD2")
        // F29B152A in the same service reboots the Nuimo into firmware-update
        // mode. It is deliberately not used anywhere in this app.
    }

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var ledCharacteristic: CBCharacteristic?
    private var flyCalibrationCharacteristic: CBCharacteristic?
    private var longPressTimer: Timer?
    private var lastLEDWrite = Date.distantPast
    private var pendingLED: Data?
    private var ledFlushScheduled = false

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: Hover sensor

    var canCalibrateHover: Bool { state == .connected && flyCalibrationCharacteristic != nil }

    /// Asks the Nuimo to recalibrate its hover sensor against its current
    /// surroundings (per Senic's SDK). Nothing should be above it at the time.
    @discardableResult
    func calibrateHover() -> Bool {
        guard let p = peripheral, state == .connected, let ch = flyCalibrationCharacteristic else { return false }
        p.writeValue(Data([1]), for: ch, type: .withResponse)
        return true
    }

    // MARK: LED

    /// Shows a frame. Writes are throttled so a fast-spinning dial cannot flood the link.
    func show(_ matrix: LEDMatrix, brightness: Double = 1.0, seconds: Double = 1.5, fade: Bool = false) {
        pendingLED = matrix.payload(brightness: brightness, seconds: seconds, fade: fade)
        flushLED()
    }

    private func flushLED() {
        guard let data = pendingLED, let p = peripheral, let ch = ledCharacteristic else { return }
        let wait = 0.06 - Date().timeIntervalSince(lastLEDWrite)
        if wait > 0 {
            guard !ledFlushScheduled else { return }
            ledFlushScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                self?.ledFlushScheduled = false
                self?.flushLED()
            }
            return
        }
        pendingLED = nil
        lastLEDWrite = Date()
        p.writeValue(data, for: ch, type: .withoutResponse)
    }

    // MARK: Central

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn: startScan()
        case .unauthorized: state = .unauthorized
        case .poweredOff, .unsupported, .resetting, .unknown: state = .bluetoothOff
        @unknown default: state = .bluetoothOff
        }
    }

    private func startScan() {
        guard central.state == .poweredOn else { return }
        state = .scanning
        // The Nuimo only advertises the generic battery/device-info services,
        // so scan for everything and match on its name.
        central.scanForPeripherals(withServices: nil)
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData ad: [String: Any], rssi: NSNumber) {
        let name = (ad[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? ""
        guard name == "Nuimo", peripheral == nil else { return }
        peripheral = p
        p.delegate = self
        c.stopScan()
        state = .connecting
        c.connect(p)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.discoverServices(nil)
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        reset()
        startScan()
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        ledCharacteristic = nil
        battery = nil
        longPressTimer?.invalidate()
        guard c.state == .poweredOn else { reset(); return }
        // A pending connect never times out, so this picks the Nuimo back up
        // whenever it wakes or comes back into range.
        state = .connecting
        c.connect(p)
    }

    private func reset() {
        peripheral = nil
        flyCalibrationCharacteristic = nil
        ledCharacteristic = nil
        battery = nil
    }

    // MARK: Peripheral

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] { p.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            switch ch.uuid {
            case ID.battery:
                p.readValue(for: ch)
                p.setNotifyValue(true, for: ch)
            case ID.firmware:
                p.readValue(for: ch)
            case ID.flyCalibration:
                flyCalibrationCharacteristic = ch
            case ID.led:
                ledCharacteristic = ch
                state = .connected
                onConnect?()
            case ID.button, ID.fly, ID.swipe, ID.rotation:
                // Subscribe only. Reading these returns a zero that would be
                // indistinguishable from a real "swipe left".
                p.setNotifyValue(true, for: ch)
            default:
                break
            }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        let short = String(ch.uuid.uuidString.prefix(8))
        let status = error.map { "FAILED \($0.localizedDescription)" } ?? (ch.isNotifying ? "on" : "off")
        onRaw?("subscribe \(short) \(status)", [])
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let d = ch.value, !d.isEmpty else { return }
        let bytes = [UInt8](d)
        switch ch.uuid {
        case ID.button: onRaw?("button", bytes)
        case ID.swipe: onRaw?("touch", bytes)
        case ID.fly: onRaw?("fly", bytes)
        default: break
        }
        switch ch.uuid {
        case ID.battery:
            battery = Int(bytes[0])
        case ID.firmware:
            firmware = String(data: d, encoding: .utf8)
        case ID.rotation where bytes.count >= 2:
            let delta = Int(Int16(bitPattern: UInt16(bytes[0]) | UInt16(bytes[1]) << 8))
            if delta != 0 { onRotate?(delta) }
        case ID.button:
            handleButton(pressed: bytes[0] != 0)
        case ID.swipe:
            if let g = Self.swipeGestures[bytes[0]] { onGesture?(g) }
        case ID.fly:
            switch bytes[0] {
            case 0: onGesture?(.flyLeft)
            case 1: onGesture?(.flyRight)
            case 4 where bytes.count >= 2: onHover?(Int(bytes[1]))
            default: break
            }
        default:
            break
        }
    }

    private static let swipeGestures: [UInt8: Gesture] = [
        0: .swipeLeft, 1: .swipeRight, 2: .swipeUp, 3: .swipeDown,
        4: .touchLeft, 5: .touchRight, 6: .touchTop, 7: .touchBottom,
        8: .longTouchLeft, 9: .longTouchRight, 10: .longTouchTop, 11: .longTouchBottom,
    ]

    /// A short click fires `.press` on release; holding for half a second fires `.longPress`.
    private func handleButton(pressed: Bool) {
        if pressed {
            longPressTimer?.invalidate()
            longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                self?.longPressTimer = nil
                self?.onGesture?(.longPress)
            }
        } else if let t = longPressTimer {
            t.invalidate()
            longPressTimer = nil
            onGesture?(.press)
        }
    }
}
