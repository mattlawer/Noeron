//
//  ScreenshotUITests.swift
//  NoeronUITests
//
//  Launches the app in offline demo mode (NOERON_DEMO) and captures screenshots of
//  the key screens. The screenshots are attached to the test result and are also
//  used (captured via simctl in demo mode) for the README.
//

import XCTest

final class ScreenshotUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func launch(screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["NOERON_DEMO"] = "1"
        app.launchEnvironment["NOERON_DEMO_SCREEN"] = screen
        app.launch()
        return app
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        // Allow the force-directed layout / fit-to-content to settle.
        _ = app.wait(for: .runningForeground, timeout: 10)
        Thread.sleep(forTimeInterval: 3)
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testGraphScreenshot() {
        snapshot(launch(screen: "graph"), "01-graph")
    }

    func testOverviewScreenshot() {
        snapshot(launch(screen: "overview"), "02-overview")
    }

    func testTimelineScreenshot() {
        snapshot(launch(screen: "timeline"), "03-timeline")
    }
}
