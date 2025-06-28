//
//  AsyncWhileTests.swift
//  RoccTests
//
//  Created by Simon Mitchell on 19/11/2019.
//  Copyright © 2019 Simon Mitchell. All rights reserved.
//

import XCTest
@testable import Rocc

class AsyncWhileTests: XCTestCase {
  
  func testTimeoutCalledBeforeBreakingTwice() async {
    var continueCalls: Int = 0
    
    await DispatchQueue.global().asyncWhile(timeout: 1, defaultValue: ()) {
      await withCheckedContinuation { seal in
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.2, execute: {
          continueCalls += 1
          
          seal.resume(returning: ((), true))
        })
      }
    }
    
    XCTAssertEqual(continueCalls, 1)
  }
    
  func testWhileClosureCalledAppropriateNumberOfTimes() async {
    var continueCalls: Int = 0
    
    await DispatchQueue.global().asyncWhile(timeout: 2.1, defaultValue: ()) {
      await withCheckedContinuation { seal in
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2, execute: {
          continueCalls += 1
          
          seal.resume(returning: ((), true))
        })
      }
    }
    
    XCTAssertEqual(continueCalls, 11)
  }
}
