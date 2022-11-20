//
//  ViewController.swift
//  AvitoInternship2022
//
//  Created by Игорь Клюжев on 18.10.2022.
//

import UIKit
import SnapKit
import SoundAnalysis
import CoreLocation
import CoreBluetooth

class ViewController: UIViewController {
    private lazy var isSeekerLabel = {
        let label = UILabel()
        label.font = .boldSystemFont(ofSize: 25)
        label.text = "I seek"
        return label
    }()

    private lazy var isSeekerToggle = {
        let toggle = UISwitch()
        toggle.addTarget(self, action: #selector(isSeekerToggled), for: .valueChanged)
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

    private var foundPeripherals = Set<PeripheralInfo>()

    private let serviceUUID = CBUUID(string: "b4250400-fb4b-4746-b2b0-93f0e61122c6")

    private var shouldStartScanOnPowerOn = false
    private var shouldAdvertiseOnPowerOn = false

    private var nearestHiddenDistance = 0.0 {
        didSet {
            if nearestHiddenDistance > 0 {
                DispatchQueue.main.async {
                    self.bleStatusLabel.text = "BLE status: ~\(self.nearestHiddenDistance) m"
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
            make.left.equalToSuperview().offset(20)
            make.width.equalTo(200)
        }

        isSeekerToggle.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(50)
            make.left.equalTo(isSeekerLabel.snp.right).offset(10)
            make.right.lessThanOrEqualToSuperview().inset(20)
        }

        isQuiteLabel.snp.makeConstraints { make in
            make.top.equalTo(isSeekerLabel.snp.bottom).offset(20)
            make.left.equalToSuperview().offset(20)
            make.width.equalTo(200)
        }

        isQuiteToggle.snp.makeConstraints { make in
            make.top.equalTo(isSeekerLabel.snp.bottom).offset(20)
            make.left.equalTo(isQuiteLabel.snp.right).offset(10)
            make.right.lessThanOrEqualToSuperview().inset(20)
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
            stopBLEScanning()
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
                    let distanceCoeff = 2.5
                    let distance = round(distanceCoeff / conf * 100) / 100
                    if distance < 16 {
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
        peripheralManager.stopAdvertising()
    }
}

extension ViewController: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("Central state update")
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
        let info = PeripheralInfo(peripheral: peripheral, rssi: RSSI)
        foundPeripherals.insert(info)
        peripheral.delegate = self
        peripheral.readRSSI()
    }
}

extension ViewController: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        print("New rssi: \(RSSI)")
        let rssi = Int(truncating: RSSI)
        let distance = pow(10.0, Double(-69 - rssi) / Double(10 * 3))
        print("Distance: \(distance)")
        nearestHiddenDistance = min(nearestHiddenDistance, distance)
    }
}

struct PeripheralInfo: Hashable {
    let peripheral: CBPeripheral
    let rssi: NSNumber
}

extension ViewController: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        print("Peripheral state update")
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
