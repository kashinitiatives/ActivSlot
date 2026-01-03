import Foundation
import HealthKit

enum HealthKitError: Error {
    case notAvailable
    case authorizationFailed
    case dataNotAvailable
}

class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()

    @Published var isAuthorized = false
    @Published var todaySteps: Int = 0
    @Published var todayActiveEnergy: Double = 0
    @Published var recentWorkouts: [HKWorkout] = []

    private init() {
        checkAuthorizationStatus()
    }

    var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Authorization

    func requestAuthorization() async throws -> Bool {
        guard isHealthKitAvailable else {
            throw HealthKitError.notAvailable
        }

        var typesToRead: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            typesToRead.insert(stepType)
        }
        if let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            typesToRead.insert(energyType)
        }

        return try await withCheckedThrowingContinuation { continuation in
            healthStore.requestAuthorization(toShare: nil, read: typesToRead) { success, error in
                DispatchQueue.main.async {
                    self.isAuthorized = success
                }
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    func checkAuthorizationStatus() {
        guard isHealthKitAvailable else {
            isAuthorized = false
            return
        }

        // Note: iOS doesn't reveal read authorization status for privacy.
        // We check if authorization was requested (not .notDetermined) and assume
        // we can try to read. If user denied, queries will return empty data.
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            isAuthorized = false
            return
        }
        let status = healthStore.authorizationStatus(for: stepType)

        // If status is not .notDetermined, authorization was requested
        // We set isAuthorized = true to enable UI, actual data access may still be limited
        isAuthorized = status != .notDetermined
    }

    // MARK: - Step Count

    func fetchTodaySteps() async throws -> Int {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw HealthKitError.dataNotAvailable
        }
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let steps = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                DispatchQueue.main.async {
                    self.todaySteps = Int(steps)
                }
                continuation.resume(returning: Int(steps))
            }
            healthStore.execute(query)
        }
    }

    func fetchSteps(for date: Date) async throws -> Int {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw HealthKitError.dataNotAvailable
        }
        let startOfDay = Calendar.current.startOfDay(for: date)
        guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else {
            throw HealthKitError.dataNotAvailable
        }
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let steps = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: Int(steps))
            }
            healthStore.execute(query)
        }
    }

    func observeStepChanges(completion: @escaping (Int) -> Void) {
        guard isHealthKitAvailable else { return }
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }

        let query = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, _, error in
            if error == nil {
                Task {
                    if let steps = try? await self?.fetchTodaySteps() {
                        DispatchQueue.main.async {
                            completion(steps)
                        }
                    }
                }
            }
        }

        healthStore.execute(query)
    }

    // MARK: - Active Energy

    func fetchTodayActiveEnergy() async throws -> Double {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            throw HealthKitError.dataNotAvailable
        }
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: energyType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let energy = result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                DispatchQueue.main.async {
                    self.todayActiveEnergy = energy
                }
                continuation.resume(returning: energy)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Workouts

    func fetchRecentWorkouts(days: Int = 7) async throws -> [HKWorkout] {
        let workoutType = HKObjectType.workoutType()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
            throw HealthKitError.dataNotAvailable
        }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: 50, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let workouts = (samples as? [HKWorkout]) ?? []
                DispatchQueue.main.async {
                    self.recentWorkouts = workouts
                }
                continuation.resume(returning: workouts)
            }
            healthStore.execute(query)
        }
    }

    func fetchTodayWorkouts() async throws -> [HKWorkout] {
        let workoutType = HKObjectType.workoutType()
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: 10, sortDescriptors: nil) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let workouts = (samples as? [HKWorkout]) ?? []
                continuation.resume(returning: workouts)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Historical Data

    func fetchWeeklyStepAverage() async throws -> Int {
        var totalSteps = 0
        let calendar = Calendar.current

        for dayOffset in 1...7 {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) {
                let steps = try await fetchSteps(for: date)
                totalSteps += steps
            }
        }

        return totalSteps / 7
    }

    func getLastWorkoutType() async throws -> WorkoutType? {
        let workouts = try await fetchRecentWorkouts(days: 14)

        // Simple heuristic based on workout activity type
        if let lastWorkout = workouts.first {
            switch lastWorkout.workoutActivityType {
            case .traditionalStrengthTraining, .functionalStrengthTraining:
                // Try to determine push/pull/legs from duration or just rotate
                return .push
            default:
                return nil
            }
        }
        return nil
    }
}
