//
//  ViewController.swift
//  AWSS3DownloadFileDemo
//
//  Created by Eugene Zozulya on 10/5/18.
//  Copyright © 2018 Sezorus. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    
    // MARK: - IBOutlets
    
    @IBOutlet private weak var imageView:           UIImageView!
    @IBOutlet private weak var activityIndicator:   UIActivityIndicatorView!
    @IBOutlet private weak var downloadButton:      UIButton!
    
    // MARK: - Properties
    
    fileprivate var imageData:   Data?
    private var currentTask:     URLSessionTask?
    lazy private var urlSession: URLSession = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: URLSessionConfiguration.default, delegate: self, delegateQueue: queue)
    }()
    
    // MARK: - IBActions
    
    @IBAction func downloadButtonPushed(_ sender: Any) {
        self.downloadImage()
    }
    
    // MARK: - Private Methods
    
    private func showLoading(inProgress: Bool) {
        inProgress ? self.activityIndicator.startAnimating() : self.activityIndicator.stopAnimating()
        UIView.animate(withDuration: 0.25) {
            self.activityIndicator.alpha = inProgress ? 1.0 : 0.0
        }
    }
    
    private func actions(block: Bool) {
        self.downloadButton.isEnabled = !block
    }
    
    private func show(image: UIImage) {
        self.imageView.image = image
    }
    
    fileprivate func finishCurrentDownloading() {
        self.showLoading(inProgress: false)
        self.actions(block: false)
        self.currentTask = nil
    }
    
    private func downloadImage() {
        if self.currentTask != nil { return }
        
        self.showLoading(inProgress: true)
        self.actions(block: true)
        
        #warning("Set image URL")
        guard let imageURL = URL(string: "https://s3.amazonaws.com/myBucket/myImage.png") else {
            fatalError("Invalid URL.")
        }
        
        var request = URLRequest(url: imageURL)
        
        #warning("Set your AWS S3 and IAM user info")
        let s3Info = AWSS3Info(region: "",
                               accessKey: "",
                               secret: "")
        let s3RequestHelper = AWSS3RequestHelper(withS3info: s3Info)
        s3RequestHelper.sign(request: &request)
        
        self.currentTask = self.urlSession.dataTask(with: request)
        self.currentTask?.resume()
    }
    
}

// MARK: - URLSessionDataDelegate

extension ViewController: URLSessionDataDelegate {
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let httpResponse = response as? HTTPURLResponse {
            let statusCode = httpResponse.statusCode
            print("Status code \(statusCode)")
            if statusCode != 200 {
                completionHandler(URLSession.ResponseDisposition.cancel)
                return
            }
        }
        
        self.imageData = Data()
        completionHandler(URLSession.ResponseDisposition.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        self.imageData?.append(data)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("Failed to download image with error: \(error)")
        } else if let data = self.imageData, let image = UIImage(data: data) {
            DispatchQueue.main.async {
                self.show(image: image)
            }
        }
        
        DispatchQueue.main.async {
            self.finishCurrentDownloading()
        }
    }
    
}


