//
//  CocoaFobKeyGenerator.swift
//  CocoaFob
//
//  Created by Gleb Dolgich on 05/07/2015.
//  Copyright © 2015 PixelEspresso. All rights reserved.
//

import Foundation

/**
Generates CocoaFob registration keys
*/
struct CocoaFobLicGenerator {
  
  var privKey: SecKeyRef
  
  // MARK: - Initialization
  
  /**
  Initializes key generator with a private key in PEM format
  
  - parameter privateKeyPEM: String containing PEM representation of the private key
  */
  init(privateKeyPEM: String) throws {
    var params = SecItemImportExportKeyParameters()
    var keyFormat = SecExternalFormat(kSecFormatPEMSequence)
    var keyType = SecExternalItemType(kSecItemTypePrivateKey)
    if let privateKeyData = privateKeyPEM.dataUsingEncoding(NSUTF8StringEncoding) {
      var importArray: Unmanaged<CFArray>? = nil
      let osStatus = withUnsafeMutablePointer(&importArray, { importArrayPtr in
         SecItemImport(privateKeyData, nil, &keyFormat, &keyType, 0, &params, nil, importArrayPtr)
      })
      if osStatus != errSecSuccess {
        throw CocoaFobError.InvalidPrivateKey(osStatus)
      }
      let items = importArray!.takeRetainedValue() as NSArray
      if items.count < 1 {
        throw CocoaFobError.InvalidPrivateKey(0)
      }
      self.privKey = items[0] as! SecKeyRef
    } else {
      throw CocoaFobError.InvalidPrivateKey(0)
    }
  }
  
  // MARK: - Key generation
  
  /**
  Generates registration key for a user name
  
  - parameter userName: User name for which to generate a registration key
  - returns: Registration key
  */
  func generate(name: String) throws -> String {
    guard name != "" else { throw CocoaFobError.InvalidName }
    let nameData = try getNameData(name)
    let signer = try getSigner(nameData)
    let encoder = try getEncoder()
    let group = try connectTransforms(signer, encoder: encoder)
    let regData = try cfTry(.ErrorGeneratingRegKey) { return SecTransformExecute(group.takeUnretainedValue(), $0) }
    if regData.length > 0 {
      let reg = String(regData, NSUTF8StringEncoding)
      // TODO: tweak Base32-encoded key
      return reg
    } else {
      throw CocoaFobError.ErrorGeneratingRegKey
    }
  }
  
  // MARK: - Utility functions

  private func connectTransforms(signer: Unmanaged<SecTransform>, encoder: Unmanaged<SecTransform>) throws -> Unmanaged<SecGroupTransform> {
    let groupTransform = try getGroupTransform()
    return SecTransformConnectTransforms(signer.takeUnretainedValue(), kSecTransformOutputAttributeName, encoder.takeUnretainedValue(), kSecTransformInputAttributeName, groupTransform.takeUnretainedValue(), nil)
  }

  private func getGroupTransform() throws -> Unmanaged<SecGroupTransform> {
    if let group = SecTransformCreateGroupTransform() {
      return group
    }
    throw CocoaFobError.ErrorCreatingGroupTransform
  }
  
  private func cfTry(err: CocoaFobError, cfBlock: UnsafeMutablePointer<Unmanaged<CFError>?> -> Boolean) throws {
    var cferr: Unmanaged<CFError>? = nil
    if cfBlock(&cferr) == 0 {
      if let nserr = cferr?.takeRetainedValue() {
        throw nserr as NSError
      } else {
        throw err
      }
    }
  }
  
  private func cfTry<T>(err: CocoaFobError, cfBlock: UnsafeMutablePointer<Unmanaged<CFError>?> -> T!) throws -> T {
    var cferr: Unmanaged<CFError>? = nil
    if let result = cfBlock(&cferr) {
      return result
    }
    if let nserr = cferr?.takeRetainedValue() {
      throw nserr as NSError
    } else {
      throw err
    }
  }
  
  private func getNameData(name: String) throws -> NSData {
    if let nameData = name.dataUsingEncoding(NSUTF8StringEncoding) {
      return nameData
    }
    throw CocoaFobError.InvalidName
  }
  
  private func getSigner(nameData: NSData) throws -> Unmanaged<SecTransform> {
    let signer = try cfTry(.ErrorCreatingSignerTransform) { return SecSignTransformCreate(self.privKey, $0) }
    try cfTry(.ErrorConfiguringSignerTransform) { return SecTransformSetAttribute(signer.takeUnretainedValue(), kSecTransformInputAttributeName, nameData, $0) }
    try cfTry(.ErrorConfiguringSignerTransform) { return SecTransformSetAttribute(signer.takeUnretainedValue(), kSecDigestTypeAttribute, kSecDigestSHA1, $0) }
    return signer
  }
  
  private func getEncoder() throws -> Unmanaged<SecTransform> {
    let encoder = try cfTry(.ErrorCreatingEncoderTransform) { return SecEncodeTransformCreate(kSecBase32Encoding, $0) }
    return encoder
  }
  
}