import XCTest
@testable import AtlasScanCore

final class HardwareRegistryV1Tests: XCTestCase {

    // MARK: - Bundled catalogue

    func test_bundledCatalogue_isNotEmpty() {
        let registry = HardwareRegistryV1.shared
        let boilers = registry.allSpecs(ofType: .boiler)
        XCTAssertFalse(boilers.isEmpty)
    }

    func test_bundledCatalogue_containsHeatPumps() {
        let registry = HardwareRegistryV1.shared
        let pumps = registry.allSpecs(ofType: .heatPump)
        XCTAssertFalse(pumps.isEmpty)
    }

    // MARK: - Lookup by model code

    func test_lookup_byModelCode_succeeds() {
        let spec = HardwareRegistryV1.shared.spec(for: "GS8L-30")
        XCTAssertNotNil(spec)
        XCTAssertEqual(spec?.manufacturer, "Worcester Bosch")
    }

    func test_lookup_byModelCode_caseInsensitive() {
        let lower = HardwareRegistryV1.shared.spec(for: "gs8l-30")
        let upper = HardwareRegistryV1.shared.spec(for: "GS8L-30")
        XCTAssertEqual(lower?.id, upper?.id)
    }

    func test_lookup_unknownCode_returnsNil() {
        let spec = HardwareRegistryV1.shared.spec(for: "UNKNOWN-9999")
        XCTAssertNil(spec)
    }

    // MARK: - Manufacturer filter

    func test_specs_byManufacturer_worcester() {
        let specs = HardwareRegistryV1.shared.specs(manufacturer: "Worcester Bosch")
        XCTAssertFalse(specs.isEmpty)
        XCTAssertTrue(specs.allSatisfy { $0.manufacturer == "Worcester Bosch" })
    }

    // MARK: - Ghost box dimensions

    func test_ghostBox_isLargerThanPhysicalUnit() {
        guard let spec = HardwareRegistryV1.shared.spec(for: "GS8L-30") else {
            return XCTFail("GS8L-30 not found in registry")
        }
        XCTAssertGreaterThan(spec.ghostBoxWidthM,  spec.widthM)
        XCTAssertGreaterThan(spec.ghostBoxHeightM, spec.heightM)
        XCTAssertGreaterThan(spec.ghostBoxDepthM,  spec.depthM)
    }

    func test_ghostBox_frontClearanceIsLargest() {
        guard let spec = HardwareRegistryV1.shared.spec(for: "GS8L-30") else {
            return XCTFail("GS8L-30 not found in registry")
        }
        // GS8L-30 front clearance is 600 mm — access requirement
        XCTAssertEqual(spec.clearances.frontM, 0.6, accuracy: 0.001)
    }

    // MARK: - Custom registration

    func test_register_addsSpec() {
        let registry = HardwareRegistryV1(catalogue: .bundled)
        let custom = HardwareSpecV1(
            type: .boiler,
            manufacturer: "TestCo",
            modelName: "TestBoiler X1",
            modelCode: "TB-X1",
            widthM: 0.4, heightM: 0.7, depthM: 0.35,
            clearances: .regulatoryMinimum
        )
        registry.register(custom)
        let found = registry.spec(for: "TB-X1")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.manufacturer, "TestCo")
    }

    func test_register_replacesDuplicate() {
        let registry = HardwareRegistryV1(catalogue: .bundled)
        let spec1 = HardwareSpecV1(
            id: UUID(),
            type: .boiler, manufacturer: "A", modelName: "M1", modelCode: "DUP",
            widthM: 0.3, heightM: 0.6, depthM: 0.3,
            clearances: .regulatoryMinimum
        )
        let spec2 = HardwareSpecV1(
            id: spec1.id,    // same id → should replace
            type: .boiler, manufacturer: "B", modelName: "M2", modelCode: "DUP",
            widthM: 0.4, heightM: 0.7, depthM: 0.35,
            clearances: .regulatoryMinimum
        )
        registry.register(spec1)
        registry.register(spec2)
        // Should only have one entry for this id
        let all = registry.allSpecs(ofType: .boiler)
        let matches = all.filter { $0.id == spec1.id }
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].manufacturer, "B")
    }

    // MARK: - Regulatory minimum clearances

    func test_regulatoryMinimum_frontIsPoint6() {
        XCTAssertEqual(ClearanceEnvelopeV1.regulatoryMinimum.frontM, 0.6, accuracy: 0.001)
    }
}
