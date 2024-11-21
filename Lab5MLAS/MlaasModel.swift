//
//  MlaasModel.swift
//
//  Alex Geer, Hamna Tameez, Zareenah Murad
//

import UIKit
import Foundation

protocol ClientDelegate: AnyObject {
    func receivedPrediction(_ prediction: [String: Any])
    func updateDsid(_ newDsid: Int)
}


class MlaasModel: NSObject, URLSessionDelegate {

    // MARK: - Properties
    private let operationQueue = OperationQueue()
    var server_ip = "127.0.0.1" // Replace with server IP or hostname
    var delegate: ClientDelegate?
    private var dsid: Int = 1 // Default dsid for handwriting
    
    lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 15.0
        return URLSession(configuration: config, delegate: self, delegateQueue: operationQueue)
    }()

    // MARK: - Initializers
    override init() {
        super.init()
    }
    
    // MARK: - Getters and Setters
    func updateDsid(_ newDsid: Int) {
        dsid = newDsid
    }

    func getDsid() -> Int {
        return dsid
    }

    func setServerIp(ip: String) -> Bool {
        // Validate and set IP
        let pattern = "((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\\.|$)){4}"
        if NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: ip) {
            server_ip = ip
            return true
        }
        return false
    }

    // MARK: - Utility Functions
    func testConnection(completion: @escaping (Bool) -> Void) {
        let baseURL = "http://\(server_ip):8000/max_dsid/"
        guard let url = URL(string: baseURL) else {
            print("Invalid URL")
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        session.dataTask(with: request) { (data, response, error) in
            if let error = error {
                print("Connection error: \(error.localizedDescription)")
                completion(false)
            } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("Connected to server")
                completion(true)
            } else {
                print("Failed to connect, status code: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                completion(false)
            }
        }.resume()
    }

    // MARK: - API Actions
    func getNewDsid() {
        let baseURL = "http://\(server_ip):8000/max_dsid/"
        guard let url = URL(string: baseURL) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        session.dataTask(with: request) { data, response, error in
            guard error == nil, let data = data else {
                print("Error getting DSID: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let newDsid = json["dsid"] as? Int {
                self.dsid = newDsid + 1
                self.delegate?.updateDsid(self.dsid)
            }
        }.resume()
    }

    func trainModel() {
        let baseURL = "http://\(server_ip):8000/train_model_sklearn/\(dsid)"
        guard let url = URL(string: baseURL) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        session.dataTask(with: request) { data, response, error in
            guard error == nil, let data = data else {
                print("Error training model: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                print("Training response: \(json)")
            }
        }.resume()
    }

    func trainHandwritingModel(completion: @escaping (Bool) -> Void) {
        let url = URL(string: "http://\(server_ip):8000/train_model_sklearn/\(dsid)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        session.dataTask(with: request) { data, response, error in
            guard error == nil, let data = data else {
                print("Error training model: \(error?.localizedDescription ?? "Unknown error")")
                completion(false)
                return
            }

            let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            if let message = json?["message"] as? String {
                print("Training Response: \(message)")
                completion(true)
            } else {
                print("Invalid response")
                completion(false)
            }
        }.resume()
    }

    func sendHandwritingData(imageData: Data, completion: @escaping (Bool) -> Void) {
        let url = URL(string: "http://\(server_ip):8000/predict_sklearn/")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "feature": imageData.base64EncodedString(),
            "dsid": dsid
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])

        session.dataTask(with: request) { data, response, error in
            guard error == nil, let data = data else {
                print("Error sending handwriting data: \(error?.localizedDescription ?? "Unknown error")")
                completion(false)
                return
            }

            let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            if let prediction = json?["prediction"] as? String {
                print("Prediction: \(prediction)")
                self.delegate?.receivedPrediction(json!)
                completion(true)
            } else {
                print("Invalid response")
                completion(false)
            }
        }.resume()
    }

    func sendData(_ array: [Double]) {
        let baseURL = "http://\(server_ip):8000/predict_sklearn/"
        guard let url = URL(string: baseURL) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "feature": array,
            "dsid": dsid
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [])
        
        session.dataTask(with: request) { data, response, error in
            guard error == nil, let data = data else {
                print("Error sending data: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                self.delegate?.receivedPrediction(json)
            }
        }.resume()
    }
}


