//
//  AWSS3RequestHelper.swift
//  AWSS3DownloadFileDemo
//
//  Created by Eugene Zozulya on 10/5/18.
//  Copyright © 2018 Sezorus. All rights reserved.
//
// AWS Documentation https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html

import Foundation
import CommonCrypto

struct AWSS3Info {
    let region:     String
    let accessKey:  String
    let secret:     String
}

class AWSS3RequestHelper {
    
    static private let SignatureV4Marker        = "AWS4"
    static private let SignatureV4Algorithm     = "AWS4-HMAC-SHA256"
    static private let SignatureV4Terminator    = "aws4_request"
    static private let ServiceName              = "s3"
    
    // MARK: - Properties
    
    private let s3Info: AWSS3Info
    private var requestDate: Date!
    
    lazy private var shortDateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(abbreviation: "GMT")!
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyyMMdd"
        
        return dateFormatter
    }()
    lazy private var longISO8601DateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(abbreviation: "GMT")!
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        
        return dateFormatter
    }()
    
    // MARK: - Life Cycle Methods
    
    init(withS3info info: AWSS3Info) {
        self.s3Info = info
    }
    
    // MARK: - Public Methods
    
    func sign(request: inout URLRequest) {
        // save Date which we will use for the request
        self.requestDate = Date()
        
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        // calculate SHA256 for request body and set SHA256 content HTTP header
        let requestBody = request.httpBody ?? Data()
        let bodyHashHexString = self.calculateSHA256String(forBody: requestBody)
        request.addValue(bodyHashHexString, forHTTPHeaderField: "x-amz-content-sha256")
        
        // set content type HTTP header for image
        request.setValue("image/png", forHTTPHeaderField: "Content-Type")
        
        // set Host HTTP header for AWS S3
        let host = "s3.amazonaws.com"
        request.setValue(host, forHTTPHeaderField: "Host")
        
        // set request Date HTTP header in ISO8601 format
        let dateString = self.longISO8601DateFormatter.string(from: self.requestDate)
        request.setValue(dateString, forHTTPHeaderField: "X-Amz-Date")
        
        // calculate and set AWS auth string HTTP header
        let authString = self.calculateAuthorizationHeaderForRequest(forRequest: request, bodyHexString: bodyHashHexString)
        request.setValue(authString, forHTTPHeaderField: "Authorization")
    }
    
    // MARK: - Private Methods
    
    private func calculateAuthorizationHeaderForRequest(forRequest request: URLRequest, bodyHexString bodyString: String) -> String {
        let dateString      = self.shortDateFormatter.string(from: self.requestDate)
        let region          = self.s3Info.region
        let accessKey       = self.s3Info.accessKey
        let signedHeaders   = self.self.signedHeadersString(forRequest: request)
        
        let requestScope = "\(dateString)/\(region)/\(AWSS3RequestHelper.ServiceName)/\(AWSS3RequestHelper.SignatureV4Terminator)"
        let requestCredentials = "\(accessKey)/\(requestScope)"
        
        let signature = self.calculateAuthorizationSignature(forRequest: request,
                                                             bodyHexString: bodyString,
                                                             requestScope: requestScope)
        
        let authString = "\(AWSS3RequestHelper.SignatureV4Algorithm) Credential=\(requestCredentials), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        
        return authString
    }
    
    private func calculateAuthorizationSignature(forRequest request: URLRequest,
                                                 bodyHexString bodyString: String,
                                                 requestScope: String) -> String {
        // create canonical request
        let canonicalRequestString = self.createCanonicalRequestString(forRequest: request,
                                                                       bodyHexString: bodyString)
        
        // create StringToSign
        let stringToSign = self.createStringToSign(withCanonicalRequestString: canonicalRequestString, requestScope: requestScope)
        
        // create signature
        let signature = self.createSignature(withStringToSign: stringToSign)
        
        return signature
    }
    
    private func createCanonicalRequestString(forRequest request: URLRequest, bodyHexString bodyString: String) -> String {
        guard let httpMethod = request.httpMethod, let path = request.url?.path else {
            fatalError("Wrong request!")
        }
        let encodedPath = self.urlEncodedPath(fromPath: path)
        
        var canonicalRequest = ""
        canonicalRequest += httpMethod
        canonicalRequest += "\n"
        canonicalRequest += encodedPath
        canonicalRequest += "\n"
        
        // here can be a canonical query string
        canonicalRequest += "\n"
        
        // add canonical headers string
        canonicalRequest += self.canonicalHeadersString(forRequest: request)
        canonicalRequest += "\n"
        
        // add signed headers string
        canonicalRequest += self.signedHeadersString(forRequest: request)
        canonicalRequest += "\n"
        
        canonicalRequest += bodyString
        
        return canonicalRequest
    }
    
    private func createStringToSign(withCanonicalRequestString canonicalRequestString: String, requestScope: String) -> String {
        var stringToSign = AWSS3RequestHelper.SignatureV4Algorithm
        stringToSign += "\n"
        stringToSign += self.longISO8601DateFormatter.string(from: self.requestDate)
        stringToSign += "\n"
        stringToSign += requestScope
        stringToSign += "\n"
        
        let canonicalRequestHashString = self.hashString(fromString: canonicalRequestString)
        let canonicalRequestHashStringHexEncoded = self.hexEncodedString(fromString: canonicalRequestHashString)
        stringToSign += canonicalRequestHashStringHexEncoded
        
        return stringToSign
    }
    
    private func createSignature(withStringToSign stringToSign: String) -> String {
        let dateString  = self.shortDateFormatter.string(from: self.requestDate)
        let secret      = self.s3Info.secret
        let region      = self.s3Info.region
        
        let kSecret     = AWSS3RequestHelper.SignatureV4Marker + secret
        let kDate       = self.hmacSHA256(withData: dateString.data(using: .utf8)!, keyData: kSecret.data(using: .utf8)!)
        let kRegion     = self.hmacSHA256(withData: region.data(using: .ascii)!, keyData: kDate)
        let kService    = self.hmacSHA256(withData: AWSS3RequestHelper.ServiceName.data(using: .utf8)!, keyData: kRegion)
        let kSign       = self.hmacSHA256(withData: AWSS3RequestHelper.SignatureV4Terminator.data(using: .utf8)!, keyData: kService)
        
        let signatureData       = self.hmacSHA256(withData: stringToSign.data(using: .utf8)!, keyData: kSign)
        let signatureDataString = String(data: signatureData, encoding: .ascii)!
        let signatureString     = self.hexEncodedString(fromString: signatureDataString)
        
        return signatureString
    }
    
    private func calculateSHA256String(forBody bodyData: Data) -> String {
        let contentHash          = self.sha256Hash(fromData: bodyData)
        let contentHashString    = String(data: contentHash, encoding: .ascii)!
        let contentHashHexString = self.hexEncodedString(fromString: contentHashString)

        return contentHashHexString
    }
    
    private func hmacSHA256(withData: Data, keyData: Data) -> Data {
        let algorithm        = kCCHmacAlgSHA256
        let algorithmLength  = CC_SHA256_DIGEST_LENGTH
        var retData          = Data(count: Int(algorithmLength))
        
        retData.withUnsafeMutableBytes { macBytes in
            withData.withUnsafeBytes { messageBytes in
                keyData.withUnsafeBytes { keyBytes in
                    CCHmac(CCHmacAlgorithm(algorithm),
                           keyBytes.baseAddress,     keyData.count,
                           messageBytes.baseAddress, withData.count,
                           macBytes.baseAddress)
                }
            }
        }
        
        return retData
    }
    
    private func hash(fromData data: Data) -> Data {
        var retHash = [UInt8](repeating: 0,  count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &retHash)
        }
        return Data(retHash)
    }
    
    private func hashString(fromString: String) -> String {
        guard let stringData = fromString.data(using: .utf8) else {
            return ""
        }
        
        return String(data: hash(fromData: stringData), encoding: .ascii) ?? ""
    }
    
    private func sha256Hash(fromData data: Data) -> Data {
        var retHash = [UInt8](repeating: 0,  count: Int(CC_SHA256_DIGEST_LENGTH))
        let transfromData = data
        
        transfromData.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &retHash)
        }
        
        return Data(retHash)
    }
    
    private func hexEncodedString(fromString: String) -> String {
        let length = fromString.count
        var chars = [unichar](repeating: 0,  count: length)
        (fromString as NSString).getCharacters(&chars, range: NSRange(location: 0, length: length))
        
        var retString = ""
        chars.forEach { (char) in
            if (Int(char) < 16) {
                retString += "0"
            }
            retString += String(format: "%x", char)
        }
        
        return retString
    }
    
    private func urlEncodedPath(fromPath: String) -> String {
        guard let newPath = fromPath.removingPercentEncoding else {
            return fromPath
        }
        
        guard let encodedPath = newPath.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "\\!*'();:@&=+$,?%#[] ").inverted) else {
            return fromPath
        }
        
        return encodedPath
    }
    
    private func signedHeadersString(forRequest request: URLRequest) -> String {
        guard let headers = request.allHTTPHeaderFields else {
            return ""
        }
        
        var headersString = ""
        
        let sortedHeaders = headers.keys.sorted { $0.lowercased() < $1.lowercased() }
        sortedHeaders.forEach {
            if headersString.count > 0 {
                headersString += ";"
            }
            headersString += $0.lowercased()
        }
        
        return headersString
    }
    
    private func canonicalHeadersString(forRequest request: URLRequest) -> String {
        guard let headers = request.allHTTPHeaderFields else {
            return ""
        }
        
        var headersString = ""
        
        let sortedHeaders = headers.keys.sorted { $0.lowercased() < $1.lowercased() }
        sortedHeaders.forEach {
            headersString += $0.lowercased()
            headersString += ":"
            headersString += headers[$0]!
            headersString += "\n"
        }
        
        let whitespaaceChars = CharacterSet.whitespaces
        let parts = headersString.components(separatedBy: whitespaaceChars)
        let noWhitespace = parts.filter { $0 != "" }
        headersString = noWhitespace.joined(separator: " ")
        
        return headersString
    }
    
}
