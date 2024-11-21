//
//  ViewController.swift
//
//  Alex Geer, Hamna Tameez, Zareenah Murad
// This example is meant to be run with:
//              fastapi_turicreate.py



import UIKit
import CoreMotion

class ViewController: UIViewController, ClientDelegate, UITextFieldDelegate {
    
    // MARK: Class Properties
    
    // interacting with server
    let client = MlaasModel() // how we will interact with the server
    
    
    // operation queues
    let motionOperationQueue = OperationQueue()
    let calibrationOperationQueue = OperationQueue()
    
    // motion data properties
    var ringBuffer = RingBuffer()
    let motion = CMMotionManager()
    var magThreshold = 0.1
    
    // state variables
    var isCalibrating = false
    var isWaitingForMotionData = false
    
    // User Interface properties
    let animation = CATransition()
    @IBOutlet weak var dsidLabel: UILabel!
    @IBOutlet weak var upArrow: UILabel!
    @IBOutlet weak var rightArrow: UILabel!
    @IBOutlet weak var downArrow: UILabel!
    @IBOutlet weak var leftArrow: UILabel!
    @IBOutlet weak var largeMotionMagnitude: UIProgressView!
    @IBOutlet weak var enterURL: UITextField!
    
    // MARK: Class Properties with Observers
    enum CalibrationStage:String {
        case notCalibrating = "notCalibrating"
        case up = "up"
        case right = "right"
        case down = "down"
        case left = "left"
    }
    
    var calibrationStage:CalibrationStage = .notCalibrating {
        didSet{
            self.setInterfaceForCalibrationStage()
        }
    }
        
    @IBAction func magnitudeChanged(_ sender: UISlider) {
        self.magThreshold = Double(sender.value)
    }
       
    
    // MARK: View Controller Life Cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        client.testConnection { isConnected in
                    DispatchQueue.main.async {
                        if isConnected {
                            print("Successfully connected to the server.")
                        } else {
                            print("Failed to connect to the server.")
                        }
                    }
                }
        
        enterURL.delegate = self


        // create reusable animation
        animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
        animation.type = CATransitionType.fade
        animation.duration = 0.5
        
        // setup core motion handlers
        startMotionUpdates()
        
        // use delegation for interacting with client 
        client.delegate = self
        client.updateDsid(5) // set default dsid to start with

    }
    
    // UITextFieldDelegate method to handle "Return" key press
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        // Dismiss the keyboard
        textField.resignFirstResponder()
        
        // Update the IP in the model
        if let ipText = textField.text {
            _ = client.setServerIp(ip: ipText)
            print("Server IP updated to: \(ipText)")
        }
            
        return true
    }
    
    //MARK: UI Buttons
    @IBAction func getDataSetId(_ sender: AnyObject) {
        client.getNewDsid() // protocol used to update dsid
    }
    
    @IBAction func startCalibration(_ sender: AnyObject) {
        self.isWaitingForMotionData = false // dont do anything yet
        nextCalibrationStage() // kick off the calibration stages
        
    }
    
    @IBAction func makeModel(_ sender: AnyObject) {
        client.trainModel()
    }

}

//MARK: Protocol Required Functions
extension ViewController {
    func updateDsid(_ newDsid:Int){
        // delegate function completion handler
        DispatchQueue.main.async{
            // update label when set
            self.dsidLabel.layer.add(self.animation, forKey: nil)
            self.dsidLabel.text = "Current DSID: \(newDsid)"
        }
    }
    
    func receivedPrediction(_ prediction:[String:Any]){
        if let labelResponse = prediction["prediction"] as? String{
                print(labelResponse)
                self.displayLabelResponse(labelResponse)
            }
            else{
                print("Received prediction data without label.")
            }
        }
}


//MARK: Motion Extension Functions
extension ViewController {
    // Core Motion Updates
    func startMotionUpdates(){
        // some internal inconsistency here: we need to ask the device manager for device
        
        if self.motion.isDeviceMotionAvailable{
            self.motion.deviceMotionUpdateInterval = 1.0/200
            self.motion.startDeviceMotionUpdates(to: motionOperationQueue, withHandler: self.handleMotion )
        }
    }
    
    func handleMotion(_ motionData:CMDeviceMotion?, error:Error?){
        if let accel = motionData?.userAcceleration {
            self.ringBuffer.addNewData(xData: accel.x, yData: accel.y, zData: accel.z)
            let mag = fabs(accel.x)+fabs(accel.y)+fabs(accel.z)
            
            DispatchQueue.main.async{
                //show magnitude via indicator
                self.largeMotionMagnitude.progress = Float(mag)/0.2
            }
            
            if mag > self.magThreshold {
                // buffer up a bit more data and then notify of occurrence
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: {
                    self.calibrationOperationQueue.addOperation {
                        // something large enough happened to warrant
                        self.largeMotionEventOccurred()
                    }
                })
            }
        }
    }
    
    // Calibration event has occurred, send to server
    func largeMotionEventOccurred() {
        if self.isCalibrating {
            // Send a labeled example
            if self.calibrationStage != .notCalibrating && self.isWaitingForMotionData {
                self.isWaitingForMotionData = false
                
                // Convert the ring buffer data to a suitable format
                let featureData = self.ringBuffer.getDataAsVector()
                let label = self.calibrationStage.rawValue
                
                // Prepare JSON payload
                let payload: [String: Any] = [
                    "feature": featureData,
                    "label": label
                ]
                
                // Serialize to JSON data
                if let jsonData = try? JSONSerialization.data(withJSONObject: payload) {
                    // Send labeled data to the server
                    self.client.sendHandwritingData(imageData: jsonData) { success in
                        if success {
                            print("Labeled data sent successfully for label: \(label)")
                        } else {
                            print("Failed to send labeled data for label: \(label)")
                        }
                    }
                }
                
                // Proceed to the next calibration stage
                self.nextCalibrationStage()
            }
        } else {
            if self.isWaitingForMotionData {
                self.isWaitingForMotionData = false
                
                // Convert the ring buffer data to a suitable format
                let featureData = self.ringBuffer.getDataAsVector()
                
                // Send unlabeled data to the server for prediction
                self.client.sendData(featureData)
                
                // Prevent another prediction for 2 seconds
                setDelayedWaitingToTrue(2.0)
            }
        }
    }

}

//MARK: Calibration UI Functions
extension ViewController {
    
    func setDelayedWaitingToTrue(_ time:Double){
        DispatchQueue.main.asyncAfter(deadline: .now() + time, execute: {
            self.isWaitingForMotionData = true
        })
    }
    
    func setAsCalibrating(_ label: UILabel){
        label.layer.add(animation, forKey:nil)
        label.backgroundColor = UIColor.red
    }
    
    func setAsNormal(_ label: UILabel){
        label.layer.add(animation, forKey:nil)
        label.backgroundColor = UIColor.white
    }
    
    // blink the UILabel
    func blinkLabel(_ label:UILabel){
        DispatchQueue.main.async {
            self.setAsCalibrating(label)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: {
                self.setAsNormal(label)
            })
        }
    }
    
    func displayLabelResponse(_ response:String){
        switch response {
        case "['up']","up":
            blinkLabel(upArrow)
            break
        case "['down']","down":
            blinkLabel(downArrow)
            break
        case "['left']","left":
            blinkLabel(leftArrow)
            break
        case "['right']","right":
            blinkLabel(rightArrow)
            break
        default:
            print("Unknown")
            break
        }
    }
    
    func setInterfaceForCalibrationStage(){
        switch calibrationStage {
        case .up:
            self.isCalibrating = true
            DispatchQueue.main.async{
                self.setAsCalibrating(self.upArrow)
                self.setAsNormal(self.rightArrow)
                self.setAsNormal(self.leftArrow)
                self.setAsNormal(self.downArrow)
            }
            break
        case .left:
            self.isCalibrating = true
            DispatchQueue.main.async{
                self.setAsNormal(self.upArrow)
                self.setAsNormal(self.rightArrow)
                self.setAsCalibrating(self.leftArrow)
                self.setAsNormal(self.downArrow)
            }
            break
        case .down:
            self.isCalibrating = true
            DispatchQueue.main.async{
                self.setAsNormal(self.upArrow)
                self.setAsNormal(self.rightArrow)
                self.setAsNormal(self.leftArrow)
                self.setAsCalibrating(self.downArrow)
            }
            break
            
        case .right:
            self.isCalibrating = true
            DispatchQueue.main.async{
                self.setAsNormal(self.upArrow)
                self.setAsCalibrating(self.rightArrow)
                self.setAsNormal(self.leftArrow)
                self.setAsNormal(self.downArrow)
            }
            break
        case .notCalibrating:
            self.isCalibrating = false
            DispatchQueue.main.async{
                self.setAsNormal(self.upArrow)
                self.setAsNormal(self.rightArrow)
                self.setAsNormal(self.leftArrow)
                self.setAsNormal(self.downArrow)
            }
            break
        }
    }
    
    func nextCalibrationStage(){
        switch self.calibrationStage {
        case .notCalibrating:
            //start with up arrow
            self.calibrationStage = .up
            setDelayedWaitingToTrue(1.0)
            break
        case .up:
            //go to right arrow
            self.calibrationStage = .right
            setDelayedWaitingToTrue(1.0)
            break
        case .right:
            //go to down arrow
            self.calibrationStage = .down
            setDelayedWaitingToTrue(1.0)
            break
        case .down:
            //go to left arrow
            self.calibrationStage = .left
            setDelayedWaitingToTrue(1.0)
            break
            
        case .left:
            //end calibration
            self.calibrationStage = .notCalibrating
            setDelayedWaitingToTrue(1.0)
            break
        }
    }
    
    func processAndSendImage(_ image: UIImage) {
        guard let resizedImage = resizeImage(image, to: CGSize(width: 32, height: 32)),
              let imageData = resizedImage.pngData() else {
            print("Failed to process image")
            return
        }

        client.sendHandwritingData(imageData: imageData) { success in
            DispatchQueue.main.async {
                if success {
                    print("Prediction sent successfully")
                } else {
                    print("Failed to send prediction")
                }
            }
        }
    }

    func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resizedImage
    }
    
    
}

