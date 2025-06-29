//
//  Apeture.swift
//  Rocc
//
//  Created by Simon Mitchell on 26/04/2018.
//  Copyright © 2018 Simon Mitchell. All rights reserved.
//

import Foundation

/// Functions for configuring the camera's white balance
public struct WhiteBalance: CameraFunction, @unchecked Sendable {
    
    /// An enumeration representing the white balance mode
    public enum Mode: CaseIterable {
        case auto
        case daylight
        case shade
        case cloudy
        case incandescent
        case fluorescentWarmWhite
        case fluorescentCoolWhite
        case fluorescentDayWhite
        case fluorescentDaylight
        case flash
        case underwaterAuto
        case colorTemp
        case custom
        case custom1
        case custom2
        case custom3
    }
    
    /// A structural representation of white balance information
    public struct Value: Equatable {
        
        /// The white balance mode (incandescent, sunlight e.t.c.)
        public let mode: Mode
        
        /// The colour temperature of the white balance
        public let temperature: Int?
        
        let rawInternal: String
        
        public static func == (lhs: WhiteBalance.Value, rhs: WhiteBalance.Value) -> Bool {
            switch (lhs.mode, rhs.mode) {
                // Only compare color temp if we're actually in that mode!
            case (.colorTemp, .colorTemp):
                return lhs.temperature == rhs.temperature
            default:
                return lhs.mode == rhs.mode
            }
        }
    }
    
    public var function: _CameraFunction
    
    public typealias SendType = Value
    
    public typealias ReturnType = Value
    
    /// Sets the white balance the camera is using
    public static let set = WhiteBalance(function: .setWhiteBalance)
    
    /// Returns the current white balance the camera is using
    public static let get = WhiteBalance(function: .getWhiteBalance)
    
    /// Functions to setup a custom white balance on the camera
    public struct Custom: CameraFunction, @unchecked Sendable {
        
        /// A structural representation of result of setting up a custom white balance from a capture
        public struct Result: Equatable {
            
            /// Color compensating value in G-M axis. The positive value is G direction and negative is M direction.
            let colorCompensation: Int
            
            /// Light balancing value in A-B axis. The positive value is A direction and negative is B direction.
            let lightBalance: Int
            
            /// The exposure of captured image is in range or not.
            let inRange: Bool
            
            /// Color temperature (unit: K)
            let temperature: Int
        }
        
        public var function: _CameraFunction
        
        public typealias SendType = Wrapper<Void>
        
        public typealias ReturnType = Result
    
        /// Sets the white balance on the camera from an image capture
        public static let takeSetupShot = Custom(function: .setupCustomWhiteBalanceFromShot)
    }
}
