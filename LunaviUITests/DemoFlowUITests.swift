import XCTest

/// End-to-end Mission Rescue journey on an iPad Simulator in landscape.
/// Captures the three required screenshots as test attachments (kept on success); export them with
/// `xcrun xcresulttool export attachments --path <result.xcresult> --output-path Screenshots`.
/// Every check names its step and prints what the app actually showed, so a failure is self-explaining.
final class DemoFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCompleteMissionRescueJourney() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        // 0. The app must be running in the foreground before its accessibility tree is queried.
        //    (Querying too early on a cold simulator fails with kAXErrorServerNotFound.)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 60), "Step 0: app did not reach the foreground (state \(app.state.rawValue))")

        // 1–3. Launch, original plan displayed, both conditions available.
        let combinedStatus = element(app, "inspector.combinedStatus")
        XCTAssertTrue(combinedStatus.waitForExistence(timeout: 60), "Step 1: inspector did not appear")
        XCTAssertTrue(combinedStatus.label.contains("Requirements Met"), "Step 1 combined status: \(combinedStatus.label)")
        let sunlight = element(app, "condition.sunlight")
        XCTAssertTrue(sunlight.label.contains("Available"), "Step 2 sunlight card: \(sunlight.label)")
        let earth = element(app, "condition.earthLineOfSight")
        XCTAssertTrue(earth.label.contains("Clear throughout"), "Step 2 Earth card: \(earth.label)")
        let siteName = element(app, "inspector.siteName")
        XCTAssertTrue(siteName.label.contains("Demo Point A"), "Step 3 site name: \(siteName.label)")
        let terrain = element(app, "map.terrainLabel")
        XCTAssertTrue(terrain.label.contains("ILLUSTRATIVE TERRAIN"), "Step 3 terrain label: \(terrain.label)")
        attachScreenshot(named: "01-original-mission-plan")

        // 4–6. Simulate +6h delay; delayed plan and sunlight failure appear.
        let simulate = app.buttons["action.simulateDelay"]
        XCTAssertTrue(simulate.waitForExistence(timeout: 5), "Step 4: Simulate Delay button not found")
        XCTAssertTrue(simulate.label.contains("Simulate +6h Delay"), "Step 4 button label: \(simulate.label)")
        tapWhenReady(simulate, step: "Step 4")
        XCTAssertTrue(element(app, "comparison.delayed").waitForExistence(timeout: 5), "Step 5: delayed scenario card did not appear")
        XCTAssertTrue(element(app, "comparison.original").exists, "Step 5: original scenario card missing")
        let delayedSunlight = element(app, "condition.sunlight")
        XCTAssertTrue(delayedSunlight.label.contains("Partially obstructed"), "Step 5 sunlight card after delay: \(delayedSunlight.label)")
        let alert = element(app, "impact.alert")
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Step 6: impact alert did not appear")
        XCTAssertTrue(alert.label.contains("Sunlight interruption detected"), "Step 6 alert: \(alert.label)")
        XCTAssertTrue(alert.label.contains("21 NOV 2026 08:00 UTC"), "Step 6 alert time: \(alert.label)")
        let delayedStatus = element(app, "inspector.combinedStatus")
        XCTAssertTrue(delayedStatus.label.contains("Not Met"), "Step 6 combined status: \(delayedStatus.label)")
        attachScreenshot(named: "02-delay-impact")

        // 7. Explain This Change.
        let explain = app.buttons["action.explain"]
        XCTAssertTrue(explain.waitForExistence(timeout: 5), "Step 7: Explain This Change button not found")
        tapWhenReady(explain, step: "Step 7")
        XCTAssertTrue(element(app, "explain.whatChanged").waitForExistence(timeout: 5), "Step 7: Explain sheet did not open")
        XCTAssertTrue(element(app, "explain.why").exists, "Step 7: 'Why' section missing")
        let done = app.buttons["explain.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Step 7: Done button not found in the Explain sheet")
        tapWhenReady(done, step: "Step 7 (close Explain)")
        XCTAssertTrue(app.buttons["action.findRecovery"].waitForExistence(timeout: 5), "Step 7: Find Recovery Options not found after closing Explain")

        // 8–10. Find Recovery Options, select the alternative site, preview it.
        tapWhenReady(app.buttons["action.findRecovery"], step: "Step 8")
        let optionB = element(app, "recovery.alternativeSite")
        XCTAssertTrue(optionB.waitForExistence(timeout: 5), "Step 8: option B card did not appear")
        XCTAssertTrue(element(app, "recovery.sameSiteLaterTime").exists, "Step 8: option A card missing")
        tapWhenReady(optionB, step: "Step 9")
        XCTAssertTrue(element(app, "preview.tag").waitForExistence(timeout: 5), "Step 9: PREVIEW tag did not appear after selecting option B")
        let previewSite = element(app, "inspector.siteName")
        XCTAssertTrue(previewSite.label.contains("Demo Point A"), "Step 10: preview must not change the committed site: \(previewSite.label)")
        let apply = app.buttons["action.apply"]
        XCTAssertTrue(apply.isEnabled, "Step 10: Apply button is disabled")
        attachScreenshot(named: "03-mission-rescue")

        // 11–12. Apply to Demo Plan; updated plan confirmed.
        tapWhenReady(apply, step: "Step 11")
        let updated = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Updated Plan")).firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 5), "Step 11: 'Updated Plan' banner did not appear")
        XCTAssertTrue(updated.label.contains("Visibility Requirements Met"), "Step 11 banner: \(updated.label)")
        let appliedSite = element(app, "inspector.siteName")
        XCTAssertTrue(appliedSite.label.contains("Ridge Site B"), "Step 12 site after apply: \(appliedSite.label)")

        // 13–14. Reset Demo restores the original mission completely.
        tapWhenReady(app.buttons["toolbar.resetDemo"], step: "Step 13")
        XCTAssertTrue(app.buttons["action.simulateDelay"].waitForExistence(timeout: 5), "Step 13: Simulate Delay did not return after Reset")
        let resetSite = element(app, "inspector.siteName")
        XCTAssertTrue(resetSite.label.contains("Demo Point A"), "Step 13 site after reset: \(resetSite.label)")
        let resetStatus = element(app, "inspector.combinedStatus")
        XCTAssertTrue(resetStatus.label.contains("Requirements Met"), "Step 13 status after reset: \(resetStatus.label)")
        let landing = element(app, "parameters.landingTime")
        let landingValue = (landing.value as? String) ?? ""
        XCTAssertTrue(landingValue.contains("20 November 2026, 06:00 UTC"), "Step 14 landing time after reset: \(landingValue)")
        XCTAssertTrue(app.buttons["duration.24"].isSelected, "Step 14: 24 h duration is not selected after reset")
        XCTAssertFalse(element(app, "comparison.delayed").exists, "Step 14: delayed card still visible after reset")
    }

    /// Taps an element the way a person would: if it is off-screen or right at the edge of the inspector
    /// footer, scroll the inspector and try again; tap only once it is hittable and clear of the footer.
    /// Every check after a tap is unchanged, so a tap that did not work still fails the test.
    @MainActor
    private func tapWhenReady(_ element: XCUIElement, step: String, timeout: TimeInterval = 10) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(step): \(element.identifier) not found")
        let inspector = XCUIApplication().descendants(matching: .any)["inspector"].firstMatch
        for attempt in 0..<6 {
            let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
            if XCTWaiter().wait(for: [hittable], timeout: attempt == 0 ? 2 : 1) == .completed, isClearOfFooter(element) {
                element.tap()
                return
            }
            // Bring it into view: scroll the inspector (or, if it is not visible, the whole window).
            if inspector.exists {
                inspector.swipeUp(velocity: .slow)
            } else {
                XCUIApplication().swipeUp(velocity: .slow)
            }
        }
        XCTFail("\(step): \(element.identifier) never became tappable (not hittable or under the inspector footer)")
    }

    /// False when the element's centre lies inside the pinned inspector footer (primary action area).
    @MainActor
    private func isClearOfFooter(_ element: XCUIElement) -> Bool {
        let app = XCUIApplication()
        let footerButtons = ["action.simulateDelay", "action.findRecovery", "action.apply", "action.clearPreview",
                             "action.acceptDelayed", "action.compareAgain", "action.resetDemo"]
        // Footer buttons themselves are always on screen; only inspector content can slide under them.
        if footerButtons.contains(element.identifier) { return true }
        let centre = CGPoint(x: element.frame.midX, y: element.frame.midY)
        for id in footerButtons where id != element.identifier {
            let footer = app.buttons[id]
            if footer.exists, footer.frame.insetBy(dx: 0, dy: -24).contains(centre) {
                return false
            }
        }
        return true
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
