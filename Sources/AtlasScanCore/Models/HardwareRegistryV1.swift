/// HardwareRegistryV1 — Central database of boiler / heat-pump dimensions used
/// to drive the AR "Ghost Box" clearance volumes.
///
/// All measurements are in metric metres.

import Foundation

// MARK: - Clearance envelope (manufacturer-specified)

public struct ClearanceEnvelopeV1: Codable, Sendable {
    public let topM: Double
    public let bottomM: Double
    public let frontM: Double
    public let backM: Double
    public let leftM: Double
    public let rightM: Double

    public init(
        topM: Double,
        bottomM: Double,
        frontM: Double,
        backM: Double,
        leftM: Double,
        rightM: Double
    ) {
        self.topM = topM
        self.bottomM = bottomM
        self.frontM = frontM
        self.backM = backM
        self.leftM = leftM
        self.rightM = rightM
    }

    /// Minimum regulatory clearance (used when no manufacturer data exists).
    public static let regulatoryMinimum = ClearanceEnvelopeV1(
        topM: 0.025,
        bottomM: 0.025,
        frontM: 0.600,
        backM: 0.025,
        leftM: 0.025,
        rightM: 0.025
    )
}

// MARK: - Hardware type

public enum HardwareType: String, Codable, CaseIterable, Sendable {
    case boiler
    case heatPump
    case hotWaterCylinder
    case pressureVessel
}

// MARK: - Boiler / heat-pump specification

public struct HardwareSpecV1: Codable, Identifiable, Sendable {
    public let id: UUID
    public let type: HardwareType
    public let manufacturer: String
    public let modelName: String
    public let modelCode: String?

    // Physical dimensions (metres)
    public let widthM: Double
    public let heightM: Double
    public let depthM: Double

    // Manufacturer-specified clearances
    public let clearances: ClearanceEnvelopeV1

    // Ghost-box total volume (footprint + all clearances)
    public var ghostBoxWidthM:  Double { widthM  + clearances.leftM  + clearances.rightM  }
    public var ghostBoxHeightM: Double { heightM + clearances.topM   + clearances.bottomM }
    public var ghostBoxDepthM:  Double { depthM  + clearances.frontM + clearances.backM   }

    public init(
        id: UUID = UUID(),
        type: HardwareType,
        manufacturer: String,
        modelName: String,
        modelCode: String? = nil,
        widthM: Double,
        heightM: Double,
        depthM: Double,
        clearances: ClearanceEnvelopeV1
    ) {
        self.id = id
        self.type = type
        self.manufacturer = manufacturer
        self.modelName = modelName
        self.modelCode = modelCode
        self.widthM = widthM
        self.heightM = heightM
        self.depthM = depthM
        self.clearances = clearances
    }
}

// MARK: - Registry

public final class HardwareRegistryV1: @unchecked Sendable {

    // Shared singleton backed by the bundled catalogue.
    public static let shared = HardwareRegistryV1(catalogue: .bundled)

    private var entries: [HardwareSpecV1]

    public init(catalogue: Catalogue) {
        self.entries = catalogue.entries
    }

    // MARK: Lookup

    public func spec(for modelCode: String) -> HardwareSpecV1? {
        entries.first { $0.modelCode?.lowercased() == modelCode.lowercased() }
    }

    public func specs(manufacturer: String) -> [HardwareSpecV1] {
        entries.filter { $0.manufacturer.lowercased() == manufacturer.lowercased() }
    }

    public func allSpecs(ofType type: HardwareType) -> [HardwareSpecV1] {
        entries.filter { $0.type == type }
    }

    public func register(_ spec: HardwareSpecV1) {
        entries.removeAll { $0.id == spec.id }
        entries.append(spec)
    }
}

// MARK: - Bundled catalogue

public extension HardwareRegistryV1 {

    struct Catalogue: Sendable {
        public let entries: [HardwareSpecV1]

        /// Factory-default catalogue with a representative set of common models.
        public static let bundled = Catalogue(entries: [

            // ── Worcester Bosch ──────────────────────────────────────────────
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Worcester Bosch",
                modelName: "Greenstar 8000 Life 30kW",
                modelCode: "GS8L-30",
                widthM: 0.390, heightM: 0.720, depthM: 0.370,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.025, bottomM: 0.025,
                    frontM: 0.600, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Worcester Bosch",
                modelName: "Greenstar 4000 25kW",
                modelCode: "GS4-25",
                widthM: 0.380, heightM: 0.700, depthM: 0.360,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.025, bottomM: 0.025,
                    frontM: 0.600, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),

            // ── Vaillant ─────────────────────────────────────────────────────
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Vaillant",
                modelName: "ecoTEC plus 30kW",
                modelCode: "VU-306/5-5",
                widthM: 0.440, heightM: 0.720, depthM: 0.338,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.050, bottomM: 0.050,
                    frontM: 0.600, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),

            // ── Ideal Boilers ────────────────────────────────────────────────
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Ideal",
                modelName: "Logic Max Combi 30",
                modelCode: "ILM-C30",
                widthM: 0.380, heightM: 0.690, depthM: 0.350,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.025, bottomM: 0.025,
                    frontM: 0.600, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),

            // ── Viessmann ────────────────────────────────────────────────────
            HardwareSpecV1(
                type: .boiler,
                manufacturer: "Viessmann",
                modelName: "Vitodens 100-W 26kW",
                modelCode: "B1HF-26",
                widthM: 0.400, heightM: 0.700, depthM: 0.350,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.025, bottomM: 0.025,
                    frontM: 0.700, backM: 0.025,
                    leftM: 0.025, rightM: 0.025
                )
            ),

            // ── Heat pumps ───────────────────────────────────────────────────
            HardwareSpecV1(
                type: .heatPump,
                manufacturer: "Vaillant",
                modelName: "aroTHERM plus 7kW",
                modelCode: "VWL-7-5AS",
                widthM: 1.100, heightM: 1.255, depthM: 0.470,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.500, bottomM: 0.100,
                    frontM: 1.000, backM: 0.200,
                    leftM: 0.200, rightM: 0.200
                )
            ),
            HardwareSpecV1(
                type: .heatPump,
                manufacturer: "Mitsubishi Electric",
                modelName: "Ecodan 8.5kW ASHP",
                modelCode: "PUHZ-SW85VHA",
                widthM: 0.940, heightM: 1.390, depthM: 0.380,
                clearances: ClearanceEnvelopeV1(
                    topM: 0.300, bottomM: 0.100,
                    frontM: 0.600, backM: 0.050,
                    leftM: 0.100, rightM: 0.100
                )
            )
        ])
    }
}
