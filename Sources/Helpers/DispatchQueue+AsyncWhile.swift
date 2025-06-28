//
//  DispatchQueue+AsyncWhile.swift
//  Rocc
//
//  Created by Nikhil Nigade on 28/06/2025.
//  Copyright © 2025 Nikhil Nigade. All rights reserved.
//

import Foundation

extension DispatchQueue {
  
  /// Allows for asynchronous behaviour in a while-loop manner using async-await.
  /// - Parameters:
  ///   - timeout: A timeout time interval for the while loop as a fall back to exit it
  ///   - operation: An async closure that returns true to continue the loop, false to break
  /// - Returns: True if the loop completed naturally, false if it timed out
  @discardableResult
  func asyncWhile<T>(
    timeout: TimeInterval,
    defaultValue: T,
    operation: @escaping @Sendable () async -> (T, Bool)
  ) async -> (T, Bool) where T: Sendable {
    let deadline = ContinuousClock.now + Duration.seconds(timeout)
    
    return await withTaskGroup(of: (T, Bool)?.self) { group in
      // Add timeout task
      group.addTask {
        try? await Task.sleep(until: deadline, clock: .continuous)
        return nil // Timeout reached
      }
      
      // Add main loop task
      group.addTask { [weak self] in
        guard let self else { return nil }
        
        while ContinuousClock.now < deadline {
          let result = await withCheckedContinuation { continuation in
            self.async {
              Task {
                let operationResult = await operation()
                continuation.resume(returning: operationResult)
              }
            }
          }
          
          if !result.1 {
            // Operation signaled completion
            return (result.0, true)
          }
        }
        
        return nil
      }
      
      defer { group.cancelAll() }
      
      let result = await group.next()
      
      return (result ?? (defaultValue, false)) ?? (defaultValue, false)
    }
  }
  
  /// Creates an AsyncStream that runs operations on this queue with a timeout
  /// - Parameters:
  ///   - timeout: A timeout time interval for the stream
  ///   - operation: An async closure that returns an optional value. Return nil to end the stream
  /// - Returns: An AsyncStream of the operation results
  func asyncWhileStream<T: Sendable>(
    timeout: TimeInterval,
    operation: @escaping @Sendable () async -> T?
  ) -> AsyncStream<T> {
    
    AsyncStream { continuation in
      let task = Task { [weak self] in
        guard let self = self else {
          continuation.finish()
          return
        }
        
        let deadline = ContinuousClock.now + Duration.seconds(timeout)
        
        while ContinuousClock.now < deadline {
          let result = await withCheckedContinuation { asyncContinuation in
            self.async {
              Task {
                let value = await operation()
                asyncContinuation.resume(returning: value)
              }
            }
          }
          
          if let result = result {
            continuation.yield(result)
          } else {
            break // Operation signaled completion
          }
        }
        
        continuation.finish()
      }
      
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}

// MARK: - Usage Examples

extension DispatchQueue {
  
  /// Example usage for polling with async-await
  func pollUntilCondition<T>(
    timeout: TimeInterval = 30.0,
    defaultValue: T,
    condition: @escaping @Sendable () async -> (T, Bool)
  ) async -> (T, Bool) where T: Sendable {
    await asyncWhile(timeout: timeout, defaultValue: defaultValue) {
      await condition() // Continue while condition is NOT met
    }
  }
  
  /// Example usage for collecting results over time
  func collectResults<T: Sendable>(
    timeout: TimeInterval = 30.0,
    generator: @escaping @Sendable () async -> T?
  ) async -> [T] {
    var results: [T] = []
    
    for await result in asyncWhileStream(timeout: timeout, operation: generator) {
      results.append(result)
    }
    
    return results
  }
}
