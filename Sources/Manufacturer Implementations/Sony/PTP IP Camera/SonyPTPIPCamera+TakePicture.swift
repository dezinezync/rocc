//
//  SonyPTPIPCamera+TakePicture.swift
//  Rocc
//
//  Created by Simon Mitchell on 22/01/2020.
//  Copyright © 2020 Simon Mitchell. All rights reserved.
//

import Foundation
import os.log

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension SonyPTPIPDevice {
    
    typealias CaptureCompletion = @Sendable (Result<URL?, Error>) -> Void
    
    func takePicture(completion: @escaping CaptureCompletion) {
        
        Logger.log(message: "Taking picture...", category: "SonyPTPIPCamera", level: .debug)
        os_log("Taking picture...", log: log, type: .debug)
        
        self.isAwaitingObject = true
        
        startCapturing { [weak self] (error) in
            
            guard let self = self else { return }
            if let error = error {
                self.isAwaitingObject = false
                completion(Result.failure(error))
                return
            }
            
            self.awaitFocusIfNeeded(completion: { [weak self] (objectId) in
                self?.cancelShutterPress(objectID: objectId, completion: completion)
            })
        }
    }
    
    func awaitFocusIfNeeded(completion: @Sendable @escaping (_ objectId: DWord?) -> Void) {
        
        guard let focusMode = self.lastEvent?.focusMode?.current else {
            
            self.performFunction(Focus.Mode.get, payload: nil) { [weak self] (_, focusMode) in
            
                guard let self = self else {
                    return
                }
                
                guard focusMode?.isAutoFocus == true else {
                    completion(nil)
                    return
                }
                
                self.awaitFocus(completion: completion)
            }
            
            return
        }
        
        guard focusMode.isAutoFocus else {
            completion(nil)
            return
        }
        
        self.awaitFocus(completion: completion)
    }
 
    func startCapturing(completion: @escaping (Error?) -> Void) {
        
        Logger.log(message: "Starting capture...", category: "SonyPTPIPCamera", level: .debug)
        os_log("Starting capture...", log: self.log, type: .debug)
        
        ptpIPClient?.sendSetControlDeviceBValue(
            PTP.DeviceProperty.Value(
                code: .autoFocus,
                type: .uint16,
                value: Word(2)
            ),
            callback: { [weak self] (_) in
                
                guard let self = self else { return }
                
                self.ptpIPClient?.sendSetControlDeviceBValue(
                    PTP.DeviceProperty.Value(
                        code: .capture,
                        type: .uint16,
                        value: Word(2)
                    ),
                    callback: { (shutterResponse) in
                        guard !shutterResponse.code.isError else {
                            completion(PTPError.commandRequestFailed(shutterResponse.code))
                            return
                        }
                        completion(nil)
                    }
                )
            }
        )
    }
    
    func finishCapturing(awaitObjectId: Bool = true, completion: @escaping CaptureCompletion) {
        
        cancelShutterPress(objectID: nil, awaitObjectId: awaitObjectId, completion: completion)
    }
    
    func awaitFocus(completion: @Sendable @escaping (_ objectId: DWord?) -> Void) {
        
      Logger.log(message: "Focus mode is AF variant awaiting focus...", category: "SonyPTPIPCamera", level: .debug)
      os_log("Focus mode is AF variant awaiting focus...", log: self.log, type: .debug)
      
      Task {
        let newObject: (DWord, Bool)? = await DispatchQueue.global().asyncWhile(timeout: 1, defaultValue: awaitingObjectId ?? 0, operation: { [weak  self] in
          // If code is property changed, and first variable == "Focus Found"
          if let lastEvent = self?.lastEventPacket,
              lastEvent.code == .propertyChanged,
              lastEvent.variables?.first == 0xD213 {
            Logger.log(message: "Got property changed event and was \"Focus Found\", continuing with capture process", category: "SonyPTPIPCamera", level: .debug)
            if let log = self?.log {
              os_log("Got property changed event and was \"Focus Found\", continuing with capture process", log: log, type: .debug)
            }
            return (self?.awaitingObjectId ?? 0, true)
          }
          else if let lastEvent = self?.lastEventPacket,
                    lastEvent.code == .objectAdded,
                    let objectId = lastEvent.variables?.first {
            self?.isAwaitingObject = false
            self?.awaitingObjectId = nil
            Logger.log(message: "Got property changed event and was \"Object Added\", continuing with capture process", category: "SonyPTPIPCamera", level: .debug)
            if let log = self?.log {
              os_log("Got property changed event and was \"Object Added\", continuing with capture process", log: log, type: .debug)
            }
            return (objectId, true)
          }
          else if let awaitingObjectId = self?.awaitingObjectId {
            Logger.log(message: "Got object ID from elsewhere whilst awaiting focus", category: "SonyPTPIPCamera", level: .debug)
            
            if let log = self?.log {
              os_log("Got object ID from elsewhere whilst awaiting focus", log: log, type: .debug)
            }
            
            self?.isAwaitingObject = false
            self?.awaitingObjectId = nil
            
            return (awaitingObjectId, true)
          }
          else {
            return (0, false)
          }
        })
        
        guard let newObject else {
          return
        }
        
        let newValue = newObject.0
        
        Logger.log(message: "Focus awaited \(newValue != 0 ? "\(newValue)" : "null")", category: "SonyPTPIPCamera", level: .debug)
        os_log("Focus awaited %@", log: self.log, type: .debug, newValue != 0 ? "\(newValue)" : "null")
        
        let awaitingObjectId = self.awaitingObjectId
        self.awaitingObjectId = nil
        completion(newValue != 0 ? newValue : awaitingObjectId)
      }
    }
    
    private func cancelShutterPress(objectID: DWord?, awaitObjectId: Bool = true, completion: @escaping CaptureCompletion) {
        
        Logger.log(message: "Cancelling shutter press \(objectID != nil ? "\(objectID!)" : "null")", category: "SonyPTPIPCamera", level: .debug)
        os_log("Cancelling shutter press %@", log: self.log, type: .debug, objectID != nil ? "\(objectID!)" : "null")
                
        ptpIPClient?.sendSetControlDeviceBValue(
            PTP.DeviceProperty.Value(
                code: .capture,
                type: .uint16,
                value: Word(1)
            ),
            callback: { [weak self] response in
                
                guard let self = self else { return }
                
                Logger.log(message: "Shutter press set to 1", category: "SonyPTPIPCamera", level: .debug)
                os_log("Shutter press set to 1", log: self.log, type: .debug, objectID != nil ? "\(objectID!)" : "null")
                
                self.ptpIPClient?.sendSetControlDeviceBValue(
                    PTP.DeviceProperty.Value(
                        code: .autoFocus,
                        type: .uint16,
                        value: Word(1)
                    ),
                    callback: { [weak self] (_) in
                        guard let self = self else { return }
                        
                        Logger.log(message: "Autofocus set to 1 \(objectID ?? 0)", category: "SonyPTPIPCamera", level: .debug)
                        os_log("Autofocus set to 1", log: self.log, type: .debug, objectID != nil ? "\(objectID!)"
                            : "null")
                        guard objectID != nil || !awaitObjectId else {
                            self.awaitObjectId(completion: completion)
                            return
                        }
                        completion(Result.success(nil))
                    }
                )
            }
        )
    }
    
    private func awaitObjectId(completion: @escaping CaptureCompletion) {
        Logger.log(message: "Awaiting Object ID", category: "SonyPTPIPCamera", level: .debug)
        os_log("Awaiting Object ID", log: self.log, type: .debug)
        
        // If we already have an awaitingObjectId! For some reason this isn't caught if we jump into asyncWhile...
        guard awaitingObjectId == nil else {
            
            awaitingObjectId = nil
            isAwaitingObject = false
            // If we've got an object ID successfully then we captured an image, and we can callback, it's not necessary to transfer image to carry on.
            // We will transfer the image when the event is received...
            completion(Result.success(nil))
            
            return
        }
      
      Task {
        let newObject: (DWord, Bool)? = await DispatchQueue.global().asyncWhile(timeout: 35, defaultValue: awaitingObjectId ?? 0) { [weak self] in
          if let lastEvent = self?.lastEventPacket,
              lastEvent.code == .objectAdded {
              
              Logger.log(message: "Got property changed event and was \"Object Added\", continuing with capture process", category: "SonyPTPIPCamera", level: .debug)
            if let log = self?.log {
              os_log("Got property changed event and was \"Object Added\", continuing with capture process", log: log, type: .debug)
            }
              self?.isAwaitingObject = false
              let newObject = lastEvent.variables?.first ?? self?.awaitingObjectId
              self?.awaitingObjectId = nil
            
            return (newObject ?? 0, true)
              
          }
          else if let awaitingObjectId = self?.awaitingObjectId {
              
              Logger.log(message: "\"Object Added\" event was intercepted elsewhere, continuing with capture process", category: "SonyPTPIPCamera", level: .debug)
            if let log = self?.log {
              os_log("\"Object Added\" event was intercepted elsewhere, continuing with capture process", log: log, type: .debug)
            }
              
              self?.isAwaitingObject = false
              let newObject = awaitingObjectId
              self?.awaitingObjectId = nil
              
            return (newObject, true)
          }
          
          Logger.log(message: "Getting device prop description for 'objectInMemory'", category: "SonyPTPIPCamera", level: .debug)
          
          if let log = self?.log {
            os_log("Getting device prop description for 'objectInMemory'", log: log, type: .debug)
          }
          
          let retval: (DWord?, Bool) = await withCheckedContinuation { continuation in
            self?.getDevicePropDescriptionFor(propCode: .objectInMemory, callback: { (result) in
              Logger.log(message: "Got device prop description for 'objectInMemory'", category: "SonyPTPIPCamera", level: .debug)
              if let log = self?.log {
                os_log("Got device prop description for 'objectInMemory'", log: log, type: .debug)
              }
              
              switch result {
              case .failure(_):
                continuation.resume(returning: (nil, false))
              case .success(let property):
                // if prop 0xd215 > 0x8000, the object in RAM is available at location 0xffffc001
                // This variable also turns to 1 , but downloading then will crash the firmware
                // we seem to need to wait for 0x8000 (See https://github.com/gphoto/libgphoto2/blob/de98b151bce6b0aa70157d6c0ebb7f59b4da3792/camlibs/ptp2/library.c#L4330)
                guard let value = property.currentValue.toInt, value >= 0x8000 else {
                  continuation.resume(returning: (nil, false))
                  return
                }
                
                Logger.log(message: "objectInMemory >= 0x8000, object in memory at 0xffffc001", category: "SonyPTPIPCamera", level: .debug)
                if let log = self?.log {
                  os_log("objectInMemory >= 0x8000, object in memory at 0xffffc001", log: log, type: .debug)
                }
                
                self?.isAwaitingObject = false
                self?.awaitingObjectId = nil
                let newObject: DWord = 0xffffc001
                continuation.resume(returning: (newObject, true))
              }
            })
          }
          
          return (retval.0 ?? 0, retval.1)
        }
        
        self.awaitingObjectId = nil
        self.isAwaitingObject = false
        
        guard let newObject else {
          completion(Result.failure(PTPError.objectNotFound))
          return
        }

        // If we've got an object ID successfully then we captured an image, and we can callback, it's not necessary to transfer image to carry on.
        // We will transfer the image when the event is received...
        completion(Result.success(nil))
      }
    }
    
    func handleObjectId(objectID: DWord, shootingMode: ShootingMode, completion: @escaping CaptureCompletion) {
        
        Logger.log(message: "Got object with id: \(objectID)", category: "SonyPTPIPCamera", level: .debug)
        os_log("Got object ID", log: log, type: .debug)
        
        ptpIPClient?.getObjectInfoFor(objectId: objectID, callback: { [weak self] (result) in
            
            guard let self = self else { return }
            
            switch result {
            case .success(let info):
                // Call completion as technically now ready to take an image!
                completion(Result.success(nil))
                self.getObjectWith(info: info, objectID: objectID, shootingMode: shootingMode, completion: completion)
            case .failure(_):
                // Doesn't really matter if this part fails, as image already taken
                completion(Result.success(nil))
            }
        })
    }
    
    private func getObjectWith(info: PTP.ObjectInfo, objectID: DWord, shootingMode: ShootingMode, completion: @escaping CaptureCompletion) {
        
        Logger.log(message: "Getting object of size: \(info.compressedSize) with id: \(objectID)", category: "SonyPTPIPCamera", level: .debug)
        os_log("Getting object", log: log, type: .debug)
        
        let packet = Packet.commandRequestPacket(code: .getPartialObject, arguments: [objectID, 0, info.compressedSize], transactionId: ptpIPClient?.getNextTransactionId() ?? 2)
        ptpIPClient?.awaitDataFor(transactionId: packet.transactionId, callback: { [weak self] (result) in
            guard let self = self else { return }
            switch result {
            case .success(let data):
                self.handleObjectData(data.data, shootingMode: shootingMode, fileName: info.fileName ?? "\(ProcessInfo().globallyUniqueString).jpg")
            case .failure(let error):
                Logger.log(message: "Failed to get object: \(error.localizedDescription)", category: "SonyPTPIPCamera", level: .error)
                os_log("Failed to get object", log: self.log, type: .error)
                break
            }
        })
        ptpIPClient?.sendCommandRequestPacket(packet, callback: nil)
    }
    
    private func handleObjectData(_ data: ByteBuffer, shootingMode: ShootingMode, fileName: String) {
        
        Logger.log(message: "Got object data!: \(data.length). Attempting to save as image", category: "SonyPTPIPCamera", level: .debug)
        os_log("Got object data! Attempting to save as image", log: self.log, type: .debug)
        
        // Check for a new object, in-case we missed the event for it!
        getDevicePropDescriptionFor(propCode: .objectInMemory, callback: { [weak self] (result) in
            
            guard let self = self else { return }
            
            switch result {
            case .failure(_):
                break
            case .success(let property):
                // if prop 0xd215 > 0x8000, the object in RAM is available at location 0xffffc001
                // This variable also turns to 1 , but downloading then will crash the firmware
                // we seem to need to wait for 0x8000 (See https://github.com/gphoto/libgphoto2/blob/de98b151bce6b0aa70157d6c0ebb7f59b4da3792/camlibs/ptp2/library.c#L4330)
                guard let value = property.currentValue.toInt, value >= 0x8000 else {
                    return
                }
                self.handleObjectId(objectID: 0xffffc001, shootingMode: shootingMode) { (_) in
                    
                }
            }
        })
        
        let imageData = Data(data)
        guard Image(data: imageData) != nil else {
            Logger.log(message: "Image data not valid", category: "SonyPTPIPCamera", level: .error)
            os_log("Image data not valud", log: self.log, type: .error)
            return
        }
        
        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let imageURL = temporaryDirectoryURL.appendingPathComponent(fileName)
        do {
            try imageData.write(to: imageURL)
            imageURLs[shootingMode, default: []].append(imageURL)
            // Trigger dummy event
            onEventAvailable?()
        } catch let error {
            Logger.log(message: "Failed to save image to disk: \(error.localizedDescription)", category: "SonyPTPIPCamera", level: .error)
            os_log("Failed to save image to disk", log: self.log, type: .error)
        }
    }
}
