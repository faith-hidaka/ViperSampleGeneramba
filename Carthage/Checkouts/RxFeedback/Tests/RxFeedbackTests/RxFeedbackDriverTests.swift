    //
//  RxFeedbackDriverTests.swift
//  RxFeedbackTests
//
//  Created by Krunoslav Zaher on 8/13/17.
//  Copyright © 2017 Krunoslav Zaher. All rights reserved.
//

import Foundation
import XCTest
import RxFeedback
import RxSwift
import RxCocoa

class RxFeedbackDriverTests: RxTest {
}

extension RxFeedbackDriverTests {
    func testInitial() {
        let system = Driver.system(
            initialState: "initial",
            reduce: { _, newState in
                return newState
            },
            feedback: [] as [Driver<Any>.Feedback<String, String>])

        var state = ""
        _ = system.drive(onNext: { nextState in
            state = nextState
        })

        XCTAssertEqual(state, "initial")
    }

    func testImmediateFeedbackLoop() {
        let system = Driver.system(
            initialState: "initial",
            reduce: { oldState, append in
                return  oldState + append
            },
            feedback: { state in
                return state.flatMapLatest { state -> Signal<String> in
                    if state == "initial" {
                        return Signal.just("_a").delay(0.01)
                    }
                    else if state == "initial_a" {
                        return Signal.just("_b")
                    }
                    else if state == "initial_a_b" {
                        return Signal.just("_c")
                    }
                    else {
                        return Signal.never()
                    }
                }
        })

        let result = (try?
            system
                .asObservable()
                .take(4)
                .timeout(0.5, other: Observable.empty(), scheduler: MainScheduler.instance)
                .toBlocking(timeout: 3.0)
                .toArray()
            ) ?? []

        XCTAssertEqual(result, [
            "initial",
            "initial_a",
            "initial_a_b",
            "initial_a_b_c"
        ])
    }

    func testImmediateFeedbackLoopParallel() {
        let feedbackLoop: (Driver<String>) -> Signal<String> = { state in
            return state.flatMapLatest { state -> Signal<String> in
                if state == "initial" {
                    return Signal.just("_a")
                }
                else if state == "initial_a" {
                    return Signal.just("_b")
                }
                else if state == "initial_a_b" {
                    return Signal.just("_c")
                }
                else {
                    return Signal.never()
                }
            }
        }

        let system = Driver.system(
            initialState: "initial",
            reduce: { oldState, append in
                return  oldState + append
            },
            feedback: feedbackLoop, feedbackLoop, feedbackLoop)

        let result = (try?
            system
                .asObservable()
                .timeout(0.5, other: Observable.empty(), scheduler: MainScheduler.instance)
                .toBlocking(timeout: 3.0)
                .toArray()
            ) ?? []

        XCTAssertEqual(result, [
            "initial",
            "initial_a",
            "initial_a_a",
            "initial_a_a_a",
            "initial_a_a_a_b",
            "initial_a_a_a_b_b",
            "initial_a_a_a_b_b_b",
            ])
    }
}

// Feedback loops
extension RxFeedbackDriverTests {
    func testImmediateFeedbackLoopParallel_react_non_equatable() {
        let feedbackLoop: (Driver<String>) -> Signal<String> = react(query: { $0.needsToAppendDot }) { (_: ()) -> Signal<String> in
            return Signal.just("_.")
        }

        let system = Driver.system(
            initialState: "initial",
            reduce: { oldState, append in
                return  oldState + append
            },
            feedback: feedbackLoop, feedbackLoop, feedbackLoop)

        let result = (try?
            system
                .asObservable()
                .timeout(0.5, other: Observable.empty(), scheduler: MainScheduler.instance)
                .toBlocking(timeout: 3.0)
                .toArray()
            ) ?? []

        XCTAssertEqual(result, [
            "initial",
            "initial_.",
            "initial_._.",
            "initial_._._.",
            ])
    }

    func testImmediateFeedbackLoopParallel_react_equatable() {
        let feedbackLoop: (Driver<String>) -> Signal<String> = react(query: { $0.needsToAppend }) { (value) in
            return Signal.just(value)
        }

        let system = Driver.system(
            initialState: "initial",
            reduce: { oldState, append in
                return  oldState + append
            },
            feedback: feedbackLoop, feedbackLoop, feedbackLoop)

        let result = (try?
            system
                .asObservable()
                .timeout(0.5, other: Observable.empty(), scheduler: MainScheduler.instance)
                .toBlocking(timeout: 3.0)
                .toArray()
            ) ?? []

        XCTAssertEqual(result, [
            "initial",
            "initial_a",
            "initial_a_b",
            "initial_a_b_c",
            ])
    }

    func testImmediateFeedbackLoopParallel_react_set() {
        let feedbackLoop: (Driver<String>) -> Signal<String> = react(query: { $0.needsToAppendParallel }) { value in
            return Signal.just(value)
        }

        let system = Driver.system(
            initialState: "initial",
            reduce: { oldState, append in
                return  oldState + append
            },
            feedback: feedbackLoop, feedbackLoop, feedbackLoop)

        let result = (try?
            system
                .asObservable()
                .timeout(0.5, other: Observable.empty(), scheduler: MainScheduler.instance)
                .toBlocking(timeout: 3.0)
                .toArray()
            ) ?? []

        XCTAssertTrue(result[1].contains("_a") || result[1].contains("_b"))
        XCTAssertTrue(result[2].contains("_a") || result[2].contains("_b"))
        XCTAssertTrue(result[1].contains("_a") || result[2].contains("_a"))
        XCTAssertTrue(result[1].contains("_b") || result[2].contains("_b"))

        var ignoringAB = result

        for i in 0 ..< result.count {
            ignoringAB[i] = ignoringAB[i].replacingOccurrences(of: "_a", with: "_x")
            ignoringAB[i] = ignoringAB[i].replacingOccurrences(of: "_b", with: "_x")
        }
        
        XCTAssertEqual(ignoringAB, [
            "initial",
            "initial_x",
            "initial_x_x",
            "initial_x_x_c",
            "initial_x_x_c_c",
            "initial_x_x_c_c_c",
            ])
    }
}

extension RxFeedbackDriverTests {
    func testUIBindFeedbackLoopReentrancy() {
        let system = Driver.system(
            initialState: "initial",
            reduce: { oldState, append in
                return  oldState + append
            },
            feedback: RxFeedback.bind { (stateAndScheduler) in
                let results = stateAndScheduler.flatMap { state -> Signal<String> in
                    if state == "initial" {
                        return Signal.just("_a").delay(0.01)
                    }
                    else if state == "initial_a" {
                        return Signal.just("_b")
                    }
                    else if state == "initial_a_b" {
                        return Signal.just("_c")
                    }
                    else {
                        return Signal.never()
                    }
                }
                return Bindings(subscriptions: [], events: [results])
        })

        let result = (try?
            system
                .asObservable()
                .take(4)
                .timeout(0.5, other: Observable.empty(), scheduler: MainScheduler.instance)
                .toBlocking(timeout: 3.0)
                .toArray()
            ) ?? []

        XCTAssertEqual(result, [
            "initial",
            "initial_a",
            "initial_a_b",
            "initial_a_b_c"
            ])
    }

    func testUIBindFeedbackWithOwnerLoopReentrancy() {
        let owner = NSObject()

        let system = Driver.system(
            initialState: "initial",
            reduce: { oldState, append in
                return  oldState + append
            },
            feedback: RxFeedback.bind(owner) { (_, stateAndScheduler) in
                let results = stateAndScheduler.flatMap { state -> Signal<String> in
                    if state == "initial" {
                        return Signal.just("_a").delay(0.01)
                    }
                    else if state == "initial_a" {
                        return Signal.just("_b")
                    }
                    else if state == "initial_a_b" {
                        return Signal.just("_c")
                    }
                    else {
                        return Signal.never()
                    }
                }
                return Bindings(subscriptions: [], events: [results])
            })

        let result = (try?
            system
                .asObservable()
                .take(4)
                .timeout(0.5, other: Observable.empty(), scheduler: MainScheduler.instance)
                .toBlocking(timeout: 3.0)
                .toArray()
            ) ?? []

        XCTAssertEqual(result, [
            "initial",
            "initial_a",
            "initial_a_b",
            "initial_a_b_c"
            ])
    }
}
