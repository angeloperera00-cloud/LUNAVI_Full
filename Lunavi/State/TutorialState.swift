import Foundation
import Observation

/// Diagram drawn for a tutorial step. Diagrams are conceptual sketches (labelled "not to scale")
/// and never carry scientific numbers.
enum TutorialDiagram: String, Sendable {
    case none
    case siteMap
    case azimuthElevation
    case terrainBlocking
    case earthLineOfSight
    case timeline
    case delay
    case rescue
}

/// A real part of the interface a step refers to, so the explanation can point at it by name.
struct TutorialUIReference: Hashable, Sendable {
    var name: String
    var location: String
}

struct TutorialStep: Identifiable, Hashable, Sendable {
    var id: Int
    var title: String
    var body: String
    var terms: [(term: String, definition: String)]
    var references: [TutorialUIReference]
    var diagram: TutorialDiagram
    var symbol: String

    static func == (lhs: TutorialStep, rhs: TutorialStep) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// The twelve-step beginner walkthrough. Text only explains concepts and names real controls;
/// it never states results, so it cannot disagree with the data loaded in the app.
enum TutorialContent {
    static let steps: [TutorialStep] = [
        TutorialStep(
            id: 0,
            title: "Welcome to LUNAVI",
            body: "LUNAVI helps you plan a short mission near the Moon's south pole. For a chosen place and UTC time it checks two things: is the Sun visible (for light and power), and is Earth in line of sight (for a direct view home). It uses NASA elevation data and NAIF SPICE geometry. Results are model results for learning and planning practice — not an official NASA product and not a landing-safety assessment.",
            terms: [("UTC", "Coordinated Universal Time. Every time in LUNAVI is UTC, so it does not change with your device's time zone.")],
            references: [TutorialUIReference(name: "Data mode badge", location: "top toolbar (COMPUTED or SIMULATED DEMO)")],
            diagram: .none,
            symbol: "moon.stars"
        ),
        TutorialStep(
            id: 1,
            title: "Select a landing site",
            body: "Sites are shown as pins on the south-pole terrain map. Tap a pin to inspect it, or open the site list from the Site button in the toolbar. Only sites with computed data can be analysed; others are shown as No data, never as suitable.",
            terms: [("Landing site", "A point on the lunar surface given by latitude and longitude. LUNAVI's computed sites come from NASA region files (PGDA product 78).")],
            references: [TutorialUIReference(name: "Site button", location: "top toolbar"),
                         TutorialUIReference(name: "Map pins", location: "terrain map")],
            diagram: .siteMap,
            symbol: "mappin.and.ellipse"
        ),
        TutorialStep(
            id: 2,
            title: "Choose the mission date and time",
            body: "In the Mission Inspector, tap Landing time to pick a UTC date and time. The picker only offers times inside the computed data, because outside it LUNAVI has nothing to calculate from.",
            terms: [("Data coverage", "The period for which the science pipeline actually computed results. Outside it every result is Unknown.")],
            references: [TutorialUIReference(name: "Landing time", location: "Mission Inspector › Parameters")],
            diagram: .none,
            symbol: "calendar.badge.clock"
        ),
        TutorialStep(
            id: 3,
            title: "Select the operating duration",
            body: "Choose how many hours the mission must operate without interruption. A requirement is met only if it holds for the whole duration — a single minute of obstruction means it is not met.",
            terms: [("Operating window", "The UTC period from the landing time to the end of the required duration.")],
            references: [TutorialUIReference(name: "Duration buttons", location: "Mission Inspector › Parameters")],
            diagram: .none,
            symbol: "hourglass"
        ),
        TutorialStep(
            id: 4,
            title: "Sun azimuth and elevation",
            body: "The Sun's position in the sky is described by two angles. Azimuth is the compass direction, measured clockwise from north. Elevation is the angle above the flat local horizon. Near the pole the Sun stays very low and circles around the horizon over a month.",
            terms: [("Azimuth", "Compass direction of a target: 0° north, 90° east, 180° south, 270° west."),
                    ("Elevation", "Angle of a target above the local horizontal. Negative means below it.")],
            references: [TutorialUIReference(name: "Shadow Analysis", location: "top toolbar")],
            diagram: .azimuthElevation,
            symbol: "sun.max"
        ),
        TutorialStep(
            id: 5,
            title: "How terrain blocks sunlight",
            body: "Mountains and crater rims raise the real horizon above the flat one. For each direction LUNAVI computes the terrain horizon from NASA elevation data. If the Sun is lower than the terrain in its direction, the site is in shadow even though the Sun is above the flat horizon.",
            terms: [("Terrain horizon", "The highest angle of the surrounding terrain seen from the site, in one direction."),
                    ("Clearance", "Target elevation minus terrain horizon. Positive: above the terrain. Negative: hidden behind it.")],
            references: [TutorialUIReference(name: "Horizon profile", location: "Shadow Analysis")],
            diagram: .terrainBlocking,
            symbol: "mountain.2"
        ),
        TutorialStep(
            id: 6,
            title: "Earth line of sight",
            body: "Earth line of sight means some part of Earth's disc is above the terrain horizon. From the south pole Earth sits low in the sky and moves slowly, so terrain often hides it for days. This is geometry only: it does not model radios, antennas or ground stations.",
            terms: [("Line of sight", "A straight, unobstructed path between the site and the target.")],
            references: [TutorialUIReference(name: "Earth Line of Sight card", location: "Mission Inspector")],
            diagram: .earthLineOfSight,
            symbol: "globe.europe.africa"
        ),
        TutorialStep(
            id: 7,
            title: "Read the visibility timeline",
            body: "Below the map, the timeline shows Sun and Earth tracks over UTC time. Coloured stretches are visible, coral stretches are obstructed and grey means no data. Drag on the timeline to move the cursor; the cursor never changes your plan.",
            terms: [("Cursor", "The selected instant. Shadow Analysis and Earth Windows use it.")],
            references: [TutorialUIReference(name: "Visibility Timeline", location: "below the map")],
            diagram: .timeline,
            symbol: "chart.bar.xaxis"
        ),
        TutorialStep(
            id: 8,
            title: "Use Shadow Analysis",
            body: "Shadow Analysis explains the state at the cursor: the Sun's and Earth's azimuth and elevation, the terrain horizon in their directions and the clearance between them, with a 360° horizon profile. Angles come from exported samples; if they are missing it says Data unavailable instead of guessing.",
            terms: [],
            references: [TutorialUIReference(name: "Shadow Analysis", location: "top toolbar and map")],
            diagram: .none,
            symbol: "sun.horizon"
        ),
        TutorialStep(
            id: 9,
            title: "Compare landing sites",
            body: "Compare Sites evaluates every site over exactly the same UTC window with the same rules. You can preview a site without changing anything, and commit it with Use for Plan while the plan is editable. The screen shows results; it does not rank sites or judge landing safety.",
            terms: [],
            references: [TutorialUIReference(name: "Compare Sites for This Window", location: "Mission Inspector")],
            diagram: .none,
            symbol: "square.split.3x1"
        ),
        TutorialStep(
            id: 10,
            title: "Simulate a mission delay",
            body: "Real missions slip. Simulate Delay keeps your original plan and creates a separate delayed copy starting later. LUNAVI shows whether the delayed window still meets both requirements and, if not, which one fails first and when.",
            terms: [("Delay", "The same site and duration, starting later.")],
            references: [TutorialUIReference(name: "Simulate Delay", location: "Mission Inspector footer")],
            diagram: .delay,
            symbol: "clock.arrow.circlepath"
        ),
        TutorialStep(
            id: 11,
            title: "Use Mission Rescue",
            body: "Find Recovery Options searches the computed data for two alternatives: A, the same site at the earliest later time that meets both requirements, and B, the nearest other site at the delayed time. Select one to preview it, then Apply to commit it. Reset restores the original plan.",
            terms: [("Recovery option", "An alternative plan that meets both requirements for the whole window in the computed data.")],
            references: [TutorialUIReference(name: "Find Recovery Options", location: "Mission Inspector footer"),
                         TutorialUIReference(name: "Reset", location: "top toolbar")],
            diagram: .rescue,
            symbol: "lifepreserver"
        ),
    ]
}

/// Persists tutorial completion locally (UserDefaults).
struct TutorialProgress {
    static let completedKey = "lunavi.tutorial.completed.v1"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isCompleted: Bool { defaults.bool(forKey: Self.completedKey) }

    func markCompleted() {
        defaults.set(true, forKey: Self.completedKey)
    }

    func reset() {
        defaults.removeObject(forKey: Self.completedKey)
    }
}

/// Navigation through the tutorial. Independent of `MissionStore`: opening, stepping through or
/// closing the tutorial never touches the active mission.
@MainActor
@Observable
final class TutorialState {
    let steps: [TutorialStep]
    private(set) var index = 0
    private let progress: TutorialProgress

    init(steps: [TutorialStep] = TutorialContent.steps, progress: TutorialProgress = TutorialProgress()) {
        self.steps = steps
        self.progress = progress
    }

    var current: TutorialStep { steps[index] }
    var isFirst: Bool { index == 0 }
    var isLast: Bool { index == steps.count - 1 }
    /// 0…1, for the progress bar.
    var fraction: Double { steps.count > 1 ? Double(index + 1) / Double(steps.count) : 1 }
    var positionLabel: String { "Step \(index + 1) of \(steps.count)" }

    func next() {
        if index < steps.count - 1 { index += 1 }
    }

    func back() {
        if index > 0 { index -= 1 }
    }

    func go(to newIndex: Int) {
        index = min(max(newIndex, 0), steps.count - 1)
    }

    /// Finishing or skipping both record completion, so the tutorial does not reopen by itself.
    func finish() {
        progress.markCompleted()
    }

    func skip() {
        progress.markCompleted()
    }
}
