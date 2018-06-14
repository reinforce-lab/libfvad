//
//  ViewController.swift
//  iOSlibfvadExample
//
//  Created by akihiro uehara on 2018/06/14.
//  Copyright © 2018年 akihiro uehara. All rights reserved.
//

import UIKit
import AVFoundation

class ViewController: UIViewController {

    @IBOutlet var cameraView: UIView!
    @IBOutlet var label: UILabel!
    
    var session: AVCaptureSession?
    
    let audioEngine = AVAudioEngine()
    var inputNode: AVAudioInputNode?
    let fvadInstance: OpaquePointer = fvad_new()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // starting camera.
        session = AVCaptureSession()
        
        let discovertySession = AVCaptureDevice.DiscoverySession.init(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .front)
        if let device = discovertySession.devices.first {
            do {
                let inputDevice = try AVCaptureDeviceInput(device: device)
                session?.addInput(inputDevice)
            } catch let error as NSError {
                print(error)
            }
        }
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session!)
        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        previewLayer.connection?.videoOrientation = .portrait
        previewLayer.frame = cameraView.bounds
        cameraView.layer.addSublayer(previewLayer)
        
        session?.startRunning()
        
        // starting voice detection.
        
        inputNode = audioEngine.inputNode
//        let recordingFormat = inputNode!.outputFormat(forBus: 0)
        fvad_reset(fvadInstance)
        fvad_set_mode(fvadInstance, 1) //0 ("quality"), 1 ("low bitrate"), 2 ("aggressive"), and 3 ("very aggressive"). The default mode is 0.

        let micOutputFormat = inputNode!.outputFormat(forBus: 0)
        let toFormat  = AVAudioFormat(commonFormat: AVAudioCommonFormat.pcmFormatInt16, sampleRate: 8000, channels: 1, interleaved: false)!
        let converter = AVAudioConverter(from: micOutputFormat, to: toFormat)!

        print("sampling rate: \(toFormat.sampleRate).")
        fvad_set_sample_rate(fvadInstance, Int32(toFormat.sampleRate)) // Valid values are 8000, 16000, 32000 and 48000.
        // 10msごとに処理を走らせる。
        inputNode?.installTap(onBus: 0, bufferSize: AVAudioFrameCount(micOutputFormat.sampleRate * 10e-3), format: micOutputFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            // サンプリングレート 8kHz で 30msごとに処理を走らせるから、バッファ長は240。
            let toBuffer = AVAudioPCMBuffer(pcmFormat: toFormat, frameCapacity: 240)!
            var error: NSError? = nil
            let _ = converter.convert(to: toBuffer, error: &error, withInputFrom: {(packetCount, inputStatus) in
                //(AVAudioPacketCount, UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer?
                inputStatus.pointee = AVAudioConverterInputStatus.haveData
                return buffer
            })
//            print("status: \(status) toBuffer.frameLength: \(toBuffer.frameLength).")
            if toBuffer.frameLength == 240, let ptr = toBuffer.int16ChannelData {
                let framePtr = ptr[0]
                let result = fvad_process(self.fvadInstance, framePtr, 240)
                // 1  active, 0 non-active, -1 invalid frame length
                DispatchQueue.main.async {
                    self.label.isHidden = (result != 1)
                }
            }
        }
        
        audioEngine.prepare()
        try! audioEngine.start()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        audioEngine.stop()
        inputNode?.removeTap(onBus: 0)
    }
            
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

