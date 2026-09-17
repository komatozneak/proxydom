import Flutter
import NetworkExtension
import UIKit
import XCTest

class RunnerTests: XCTestCase {
  func testPathFirstIsBaselineOnly() {
    let next = TunnelPathSnapshot(
      satisfied: true,
      expensive: false,
      usesWifi: true,
      usesCellular: false,
      usesWired: false
    )
    let (decision, stored) = TunnelPathReducer.decide(previous: nil, next: next)
    XCTAssertEqual(decision, .ignore)
    XCTAssertEqual(stored, next)
  }

  func testPathWifiToCellularResets() {
    let prev = TunnelPathSnapshot(
      satisfied: true,
      expensive: false,
      usesWifi: true,
      usesCellular: false,
      usesWired: false
    )
    let next = TunnelPathSnapshot(
      satisfied: true,
      expensive: true,
      usesWifi: false,
      usesCellular: true,
      usesWired: false
    )
    let (decision, _) = TunnelPathReducer.decide(previous: prev, next: next)
    XCTAssertEqual(decision, .reset(reason: "path_iface"))
  }

  func testPathUnsatisfiedToSatisfiedResets() {
    let prev = TunnelPathSnapshot(
      satisfied: false,
      expensive: false,
      usesWifi: false,
      usesCellular: false,
      usesWired: false
    )
    let next = TunnelPathSnapshot(
      satisfied: true,
      expensive: false,
      usesWifi: true,
      usesCellular: false,
      usesWired: false
    )
    let (decision, _) = TunnelPathReducer.decide(previous: prev, next: next)
    XCTAssertEqual(decision, .reset(reason: "path_satisfied"))
  }

  func testRouteMergeDedupesEndpointAndApi() {
    let out = TunnelRouteMerge.ipv4Excludes(
      endpointHost: "85.155.228.235",
      controlPlaneHosts: ["176.114.64.174", "85.155.228.235", "not-an-ip"]
    )
    XCTAssertEqual(out, ["85.155.228.235", "176.114.64.174"])
  }

  func testRouteMergeIncludesIPv6Endpoint() {
    let out = TunnelRouteMerge.ipv6Excludes(
      endpointHost: "2001:db8::1",
      controlPlaneHosts: ["2001:db8::2", "2001:db8::1", "not-an-ip"]
    )
    XCTAssertEqual(out, ["2001:db8::1", "2001:db8::2"])
  }

  func testIntentionalStopsClearSessionActive() {
    XCTAssertTrue(TunnelStopIntent.clearsSessionActive(.userInitiated))
    XCTAssertTrue(TunnelStopIntent.clearsSessionActive(.providerDisabled))
    XCTAssertTrue(TunnelStopIntent.clearsSessionActive(.configurationDisabled))
    XCTAssertTrue(TunnelStopIntent.clearsSessionActive(.configurationRemoved))
    XCTAssertTrue(TunnelStopIntent.clearsSessionActive(.userLogout))
  }

  func testTransientStopsPreserveSessionActive() {
    XCTAssertFalse(TunnelStopIntent.clearsSessionActive(.sleep))
    XCTAssertFalse(TunnelStopIntent.clearsSessionActive(.noNetworkAvailable))
    XCTAssertFalse(TunnelStopIntent.clearsSessionActive(.providerFailed))
  }
}
