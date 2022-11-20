//
//  ViewController.swift
//  AvitoInternship2022
//
//  Created by Игорь Клюжев on 18.10.2022.
//

import UIKit
import SnapKit
import SoundAnalysis
import CoreBluetooth

class ViewController: UIViewController {
    private lazy var isSeekerLabel = {
        let label = UILabel()
        label.font = .boldSystemFont(ofSize: 25)
        label.text = "I seek"
        if #unavailable(iOS 15.0) {
            label.textColor = .gray
            label.text = "I seek - needs iOS 15+"
        }
        return label
    }()

    private lazy var isSeekerToggle = {
        let toggle = UISwitch()
        toggle.addTarget(self, action: #selector(isSeekerToggled), for: .valueChanged)
        if #unavailable(iOS 15.0) {
            toggle.tintColor = .gray
            toggle.isUserInteractionEnabled = false
        }
        return toggle
    }()

    private lazy var isQuiteLabel = {
        let label = UILabel()
        label.font = .boldSystemFont(ofSize: 25)
        label.text = "Quite mode"
        return label
    }()

    private lazy var isQuiteToggle = {
        let toggle = UISwitch()
        toggle.addTarget(self, action: #selector(isQuiteToggled), for: .valueChanged)
        toggle.setOn(true, animated: false)
        return toggle
    }()

    private lazy var bleStatusLabel = {
        let label = UILabel()
        label.font = .boldSystemFont(ofSize: 25)
        label.text = "BLE status"
        label.alpha = 0
        return label
    }()

    private lazy var soundStatusLabel = {
        let label = UILabel()
        label.font = .boldSystemFont(ofSize: 25)
        label.text = "Sound status"
        label.alpha = 0
        return label
    }()

    private let analyzer = SystemAudioClassifier.singleton
    private var player: AVAudioPlayer?

    private var centralManager: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!

    private var foundPeripherals = Set<CBPeripheral>()

    private let serviceUUID = CBUUID(string: "b4250400-fb4b-4746-b2b0-93f0e61122c6")

    private var shouldStartScanOnPowerOn = false
    private var shouldAdvertiseOnPowerOn = false

    private var lastDistanceUpdateDate = Date()
    private var nearestHiddenDistance = 0.0 {
        didSet {
            if Date().timeIntervalSince(lastDistanceUpdateDate) >= 0.5 {
                lastDistanceUpdateDate = Date()
                DispatchQueue.main.async {
                    self.bleStatusLabel.text = "BLE status: ~\(round(self.nearestHiddenDistance * 100.0) / 100.0) m"
                }
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .white

        centralManager = CBCentralManager(delegate: self, queue: nil)
        peripheralManager = .init(delegate: self, queue: nil)

        setup()

        isQuiteToggled()
    }

    private func setup() {
        view.addSubview(isSeekerLabel)
        view.addSubview(isSeekerToggle)
        view.addSubview(isQuiteLabel)
        view.addSubview(isQuiteToggle)
        view.addSubview(bleStatusLabel)
        view.addSubview(soundStatusLabel)

        isSeekerLabel.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(50)
            make.left.equalToSuperview().offset(10)
            make.width.equalTo(280)
        }

        isSeekerToggle.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(50)
            make.left.equalTo(isSeekerLabel.snp.right).offset(10)
            make.right.lessThanOrEqualToSuperview().inset(10)
        }

        isQuiteLabel.snp.makeConstraints { make in
            make.top.equalTo(isSeekerLabel.snp.bottom).offset(20)
            make.left.equalToSuperview().offset(10)
            make.width.equalTo(280)
        }

        isQuiteToggle.snp.makeConstraints { make in
            make.top.equalTo(isSeekerLabel.snp.bottom).offset(20)
            make.left.equalTo(isQuiteLabel.snp.right).offset(10)
            make.right.lessThanOrEqualToSuperview().inset(10)
        }

        bleStatusLabel.snp.makeConstraints { make in
            make.top.equalTo(isQuiteLabel.snp.bottom).offset(20)
            make.left.equalToSuperview().offset(20)
            make.right.equalToSuperview().inset(20)
        }

        soundStatusLabel.snp.makeConstraints { make in
            make.top.equalTo(bleStatusLabel.snp.bottom).offset(20)
            make.left.equalToSuperview().offset(20)
            make.right.equalToSuperview().inset(20)
        }
    }

    @objc
    private func isSeekerToggled() {
        updateVisibilityOfQuiteMode()
        if isSeekerToggle.isOn {
            stopPlayingBirdSounds()
            stopBLEStreaming()
            startBLEScanning()
            analyzer.observer = self
            analyzer.startSoundClassification(inferenceWindowSize: 1.5, overlapFactor: 0.9)
        } else {
            stopBLEScanning()
            isQuiteToggled()
            analyzer.stopSoundClassification()
            analyzer.observer = nil
        }
    }

    @objc
    private func isQuiteToggled() {
        if isQuiteToggle.isOn {
            startBLEStreaming()
            stopPlayingBirdSounds()
        } else {
            stopBLEStreaming()
            startPlayingBirdSounds()
        }
    }

    private func updateVisibilityOfQuiteMode() {
        UIView.animate(withDuration: 0.5, delay: 0) {
            let alpha = self.isSeekerToggle.isOn ? 0.0 : 1.0
            let invertedAlpha = 1.0 - alpha
            self.isQuiteLabel.alpha = alpha
            self.isQuiteToggle.alpha = alpha
            self.bleStatusLabel.alpha = invertedAlpha
            self.soundStatusLabel.alpha = invertedAlpha
        }
    }
}

extension ViewController: SNResultsObserving {
    func request(_ request: SNRequest, didProduce result: SNResult) {
        if let result = result as? SNClassificationResult {
            let clas = result.classifications.filter { $0.identifier == "bird" }
            if !clas.isEmpty {
                guard let conf = clas.first?.confidence else { return }
                DispatchQueue.main.async {
                    let distanceCoeff = 2.0
                    let distance = round(distanceCoeff / conf * 100) / 100
                    if distance < 12 {
                        self.soundStatusLabel.text = "Sound status: ~\(distance) m"
                    } else {
                        self.soundStatusLabel.text = "Sound status"
                    }
                }
            }
        }
    }
}

extension ViewController {
    private func startPlayingBirdSounds() {
        guard let soundFileURL = Bundle.main.url(
            forResource: "birds", withExtension: "mp3"
        ) else {
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(
                AVAudioSession.Category.playback
            )

            try AVAudioSession.sharedInstance().setActive(true)

            player = try AVAudioPlayer(contentsOf: soundFileURL)
            player?.numberOfLoops = -1
            player?.play()
        } catch {
            print(error.localizedDescription)
        }
    }

    private func stopPlayingBirdSounds() {
        player?.stop()
    }
}

extension ViewController {
    private func startBLEScanning() {
        if centralManager.state != .poweredOn {
            shouldStartScanOnPowerOn = true
        } else {
            startScanForPeripherals()
        }
    }

    private func stopBLEScanning() {
        shouldStartScanOnPowerOn = false
        centralManager.stopScan()
    }

    private func startBLEStreaming() {
        if peripheralManager.state != .poweredOn {
            shouldAdvertiseOnPowerOn = true
        } else {
            startAdvertising()
        }
    }

    private func stopBLEStreaming() {
        shouldAdvertiseOnPowerOn = false
        peripheralManager.removeAllServices()
        peripheralManager.stopAdvertising()
    }
}

extension ViewController: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            print("Central is not powered on")
        } else {
            if shouldStartScanOnPowerOn {
                startScanForPeripherals()
                shouldStartScanOnPowerOn = false
            }
        }
    }

    private func startScanForPeripherals() {
        centralManager.scanForPeripherals(withServices: [serviceUUID],
                                          options: [CBCentralManagerScanOptionAllowDuplicatesKey : true])
    }

    // Handles the result of the scan
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        foundPeripherals.insert(peripheral)
        central.connect(peripheral)

        let rssi = Int(truncating: RSSI)
        let distance = pow(10.0, Double(-60 - rssi) / Double(10 * 2))
        nearestHiddenDistance = distance
    }

    func centralManager(_ central: CBCentralManager, connectionEventDidOccur event: CBConnectionEvent, for peripheral: CBPeripheral) {
        switch event {
        case .peerDisconnected:
            foundPeripherals.remove(peripheral)
            if foundPeripherals.isEmpty {
                DispatchQueue.main.async {
                    self.bleStatusLabel.text = "BLE status"
                }
            }
        default:
            break
        }
    }
}

struct PeripheralInfo: Hashable {
    let peripheral: CBPeripheral
    let rssi: NSNumber
}

extension ViewController: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state != .poweredOn {
            print("Peripheral is not powered on")
        } else {
            if shouldAdvertiseOnPowerOn {
                startAdvertising()
                shouldAdvertiseOnPowerOn = false
            }
        }
    }

    private func startAdvertising() {
        self.peripheralManager.startAdvertising([CBAdvertisementDataLocalNameKey: UUID().uuidString,
                                                 CBAdvertisementDataServiceUUIDsKey: [serviceUUID]])
        peripheralManager.startAdvertising(nil)
    }
}
