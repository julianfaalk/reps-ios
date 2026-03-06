import Foundation

struct WorkoutPlanExerciseSnapshot: Hashable {
    var exercise: Exercise
    var sortOrder: Int
    var isAnchor: Bool
}

struct WorkoutPlanExerciseDraft: Hashable {
    var exercise: Exercise
    var sortOrder: Int
    var targetSets: Int?
    var targetReps: Int?
    var targetDuration: Int?
    var targetWeight: Double?
    var isAnchor: Bool
}

struct WorkoutPlanBuildResult: Hashable {
    var exercises: [WorkoutPlanExerciseDraft]
    var unavailableReason: String?
}

enum WorkoutPlanGenerationError: LocalizedError {
    case noAlternative(String)

    var errorDescription: String? {
        switch self {
        case .noAlternative(let message):
            return message
        }
    }
}

struct WorkoutPlanGenerator {
    func buildPlan(
        template: WorkoutTemplate,
        baseExercises: [TemplateExerciseDetail],
        allExercises: [Exercise],
        previousPlan: [WorkoutPlanExerciseSnapshot]?,
        shuffleSeed: Int
    ) throws -> WorkoutPlanBuildResult {
        let category = templateCategory(for: template)

        if let builtInCategory = category {
            return try buildBuiltInPlan(
                category: builtInCategory,
                allExercises: allExercises,
                previousPlan: previousPlan,
                shuffleSeed: shuffleSeed
            )
        }

        return try buildCustomPlan(
            baseExercises: baseExercises,
            allExercises: allExercises,
            previousPlan: previousPlan,
            shuffleSeed: shuffleSeed
        )
    }

    func signature(for exercises: [WorkoutPlanExerciseDraft]) -> String {
        exercises.map { $0.exercise.id.uuidString }.joined(separator: "|")
    }

    func signature(for snapshots: [WorkoutPlanExerciseSnapshot]) -> String {
        snapshots.sorted { $0.sortOrder < $1.sortOrder }
            .map { $0.exercise.id.uuidString }
            .joined(separator: "|")
    }

    private func buildBuiltInPlan(
        category: BuiltInTemplateCategory,
        allExercises: [Exercise],
        previousPlan: [WorkoutPlanExerciseSnapshot]?,
        shuffleSeed: Int
    ) throws -> WorkoutPlanBuildResult {
        let slots = category.slotSpecs
        let previousByIndex = Dictionary(uniqueKeysWithValues: (previousPlan ?? []).map { ($0.sortOrder, $0) })
        let previousSignature = previousPlan.map(signature(for:))

        for attempt in 0..<24 {
            var chosen: [WorkoutPlanExerciseDraft] = []
            var usedExerciseIDs = Set<UUID>()
            var usedVariationGroups = Set<String>()
            var failed = false

            for (index, slot) in slots.enumerated() {
                let candidates = candidatePool(
                    for: slot,
                    allExercises: allExercises,
                    usedExerciseIDs: usedExerciseIDs,
                    usedVariationGroups: usedVariationGroups,
                    previousSlot: previousByIndex[index]
                )

                guard let exercise = chooseExercise(
                    candidates: candidates,
                    seed: shuffleSeed,
                    attempt: attempt,
                    slotIndex: index,
                    preferredNameFragments: slot.preferredNameFragments
                ) else {
                    failed = true
                    break
                }

                chosen.append(
                    WorkoutPlanExerciseDraft(
                        exercise: exercise,
                        sortOrder: index,
                        targetSets: slot.targetSets,
                        targetReps: slot.targetReps,
                        targetDuration: slot.targetDuration,
                        targetWeight: slot.targetWeight,
                        isAnchor: slot.isAnchor
                    )
                )

                usedExerciseIDs.insert(exercise.id)
                if let variationGroup = normalizedVariationGroup(exercise) {
                    usedVariationGroups.insert(variationGroup)
                }
            }

            guard !failed else { continue }

            if let previousPlan {
                let allNonAnchorChanged = chosen.allSatisfy { draft in
                    guard !draft.isAnchor else { return true }
                    guard let previous = previousByIndex[draft.sortOrder] else { return true }
                    return normalizedVariationGroup(draft.exercise) != normalizedVariationGroup(previous.exercise)
                }

                guard allNonAnchorChanged else { continue }
                if let previousSignature, signature(for: chosen) == previousSignature {
                    continue
                }
            }

            return WorkoutPlanBuildResult(exercises: chosen, unavailableReason: nil)
        }

        throw WorkoutPlanGenerationError.noAlternative("No fresh shuffle is possible with the available gym-safe exercises for this template yet.")
    }

    private func buildCustomPlan(
        baseExercises: [TemplateExerciseDetail],
        allExercises: [Exercise],
        previousPlan: [WorkoutPlanExerciseSnapshot]?,
        shuffleSeed: Int
    ) throws -> WorkoutPlanBuildResult {
        guard !baseExercises.isEmpty else {
            return WorkoutPlanBuildResult(exercises: [], unavailableReason: "No exercises are configured for this template.")
        }

        let anchorIDs = customAnchorExerciseIDs(baseExercises: baseExercises)
        let previousByIndex = Dictionary(uniqueKeysWithValues: (previousPlan ?? []).map { ($0.sortOrder, $0) })
        let previousSignature = previousPlan.map(signature(for:))

        for attempt in 0..<24 {
            var chosen: [WorkoutPlanExerciseDraft] = []
            var usedExerciseIDs = Set<UUID>()
            var usedVariationGroups = Set<String>()
            var failed = false

            for (index, detail) in baseExercises.sorted(by: { $0.templateExercise.sortOrder < $1.templateExercise.sortOrder }).enumerated() {
                let isAnchor = anchorIDs.contains(detail.exercise.id)

                if isAnchor {
                    chosen.append(
                        WorkoutPlanExerciseDraft(
                            exercise: detail.exercise,
                            sortOrder: index,
                            targetSets: detail.templateExercise.targetSets,
                            targetReps: detail.templateExercise.targetReps,
                            targetDuration: detail.templateExercise.targetDuration,
                            targetWeight: detail.templateExercise.targetWeight,
                            isAnchor: true
                        )
                    )
                    usedExerciseIDs.insert(detail.exercise.id)
                    if let variationGroup = normalizedVariationGroup(detail.exercise) {
                        usedVariationGroups.insert(variationGroup)
                    }
                    continue
                }

                let candidates = allExercises
                    .filter { candidate in
                        guard candidate.exerciseType == detail.exercise.exerciseType else { return false }
                        guard !usedExerciseIDs.contains(candidate.id) else { return false }
                        guard sharesSplitIntent(base: detail.exercise, candidate: candidate) else { return false }

                        if let previous = previousByIndex[index] {
                            guard normalizedVariationGroup(previous.exercise) != normalizedVariationGroup(candidate) else {
                                return false
                            }
                        }

                        if let variationGroup = normalizedVariationGroup(candidate),
                           usedVariationGroups.contains(variationGroup) {
                            return false
                        }

                        return true
                    }
                    .sorted(by: candidateSort)

                let preferred = candidates.filter { normalizedMovementPattern($0) == normalizedMovementPattern(detail.exercise) }
                let selectionPool = preferred.isEmpty ? candidates : preferred

                guard let exercise = chooseExercise(
                    candidates: selectionPool,
                    seed: shuffleSeed,
                    attempt: attempt,
                    slotIndex: index,
                    preferredNameFragments: []
                ) else {
                    failed = true
                    break
                }

                chosen.append(
                    WorkoutPlanExerciseDraft(
                        exercise: exercise,
                        sortOrder: index,
                        targetSets: detail.templateExercise.targetSets,
                        targetReps: detail.templateExercise.targetReps,
                        targetDuration: detail.templateExercise.targetDuration,
                        targetWeight: detail.templateExercise.targetWeight,
                        isAnchor: false
                    )
                )
                usedExerciseIDs.insert(exercise.id)
                if let variationGroup = normalizedVariationGroup(exercise) {
                    usedVariationGroups.insert(variationGroup)
                }
            }

            guard !failed else { continue }

            if let previousPlan {
                let allNonAnchorChanged = chosen.allSatisfy { draft in
                    guard !draft.isAnchor else { return true }
                    guard let previous = previousByIndex[draft.sortOrder] else { return true }
                    return normalizedVariationGroup(draft.exercise) != normalizedVariationGroup(previous.exercise)
                }

                guard allNonAnchorChanged else { continue }
                if let previousSignature, signature(for: chosen) == previousSignature {
                    continue
                }
            }

            return WorkoutPlanBuildResult(exercises: chosen, unavailableReason: nil)
        }

        throw WorkoutPlanGenerationError.noAlternative("This template needs a few more compatible gym exercises before it can be shuffled without repeats.")
    }

    private func candidatePool(
        for slot: BuiltInSlotSpec,
        allExercises: [Exercise],
        usedExerciseIDs: Set<UUID>,
        usedVariationGroups: Set<String>,
        previousSlot: WorkoutPlanExerciseSnapshot?
    ) -> [Exercise] {
        let basePool = allExercises
            .filter { exercise in
                guard exercise.exerciseType == slot.exerciseType else { return false }
                guard !usedExerciseIDs.contains(exercise.id) else { return false }
                guard matches(slot: slot, exercise: exercise) else { return false }

                if let previousSlot, !slot.isAnchor {
                    guard normalizedVariationGroup(previousSlot.exercise) != normalizedVariationGroup(exercise) else {
                        return false
                    }
                }

                if let variationGroup = normalizedVariationGroup(exercise),
                   usedVariationGroups.contains(variationGroup) {
                    return false
                }

                return true
            }
            .sorted(by: candidateSort)

        if slot.isAnchor {
            let preferredPool = basePool.filter { exercise in
                guard let variationGroup = normalizedVariationGroup(exercise) else { return false }
                return slot.preferredVariationGroups.contains(variationGroup)
            }
            return preferredPool.isEmpty ? basePool : preferredPool
        }

        return basePool
    }

    private func chooseExercise(
        candidates: [Exercise],
        seed: Int,
        attempt: Int,
        slotIndex: Int,
        preferredNameFragments: [String]
    ) -> Exercise? {
        guard !candidates.isEmpty else { return nil }

        let prioritized = preferredNameFragments.isEmpty
            ? candidates
            : candidates.sorted {
                let leftScore = preferredScore(for: $0, fragments: preferredNameFragments)
                let rightScore = preferredScore(for: $1, fragments: preferredNameFragments)
                if leftScore != rightScore {
                    return leftScore < rightScore
                }
                return candidateSort($0, $1)
            }

        let index = abs(seed + attempt + slotIndex) % prioritized.count
        return prioritized[index]
    }

    private func matches(slot: BuiltInSlotSpec, exercise: Exercise) -> Bool {
        if !slot.splitTag.isEmpty {
            guard exercise.splitTags.map({ $0.lowercased() }).contains(slot.splitTag) else { return false }
        }

        if !slot.movementPatterns.isEmpty {
            guard let pattern = normalizedMovementPattern(exercise),
                  slot.movementPatterns.contains(pattern) else {
                return false
            }
        }

        if slot.isAnchor {
            return exercise.isAnchorCandidate
        }

        return true
    }

    private func sharesSplitIntent(base: Exercise, candidate: Exercise) -> Bool {
        let baseTags = Set(base.splitTags.map { $0.lowercased() })
        let candidateTags = Set(candidate.splitTags.map { $0.lowercased() })
        if !baseTags.isEmpty && !candidateTags.isEmpty && !baseTags.isDisjoint(with: candidateTags) {
            return true
        }

        let baseMuscles = Set(base.muscleGroups.map(normalizeMuscle))
        let candidateMuscles = Set(candidate.muscleGroups.map(normalizeMuscle))
        return !baseMuscles.isEmpty && !candidateMuscles.isEmpty && !baseMuscles.isDisjoint(with: candidateMuscles)
    }

    private func customAnchorExerciseIDs(baseExercises: [TemplateExerciseDetail]) -> Set<UUID> {
        let ordered = baseExercises.sorted { $0.templateExercise.sortOrder < $1.templateExercise.sortOrder }
        let anchors = ordered
            .filter { $0.exercise.isCompound || $0.exercise.isAnchorCandidate }
            .prefix(2)
        let resolved = anchors.isEmpty ? ordered.prefix(2) : anchors
        return Set(resolved.map(\.exercise.id))
    }

    private func candidateSort(_ lhs: Exercise, _ rhs: Exercise) -> Bool {
        if lhs.isCompound != rhs.isCompound {
            return lhs.isCompound && !rhs.isCompound
        }
        return lhs.name < rhs.name
    }

    private func normalizedVariationGroup(_ exercise: Exercise) -> String? {
        exercise.variationGroup?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedMovementPattern(_ exercise: Exercise) -> String? {
        exercise.movementPattern?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func preferredScore(for exercise: Exercise, fragments: [String]) -> Int {
        fragments.firstIndex(where: { !$0.isEmpty && $0.matches(in: exercise) }) ?? Int.max
    }

    private func normalizeMuscle(_ muscle: String) -> String {
        muscle.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func templateCategory(for template: WorkoutTemplate) -> BuiltInTemplateCategory? {
        let name = template.name.lowercased()

        if name.contains("push") || name.contains("brust") {
            return .push
        }
        if name.contains("pull") || name.contains("rücken") {
            return .pull
        }
        if name.contains("legs") || name.contains("bein") {
            return .legs
        }
        if name.contains("shoulder") || name.contains("schulter") {
            return .shouldersCore
        }

        return nil
    }
}

private struct BuiltInSlotSpec {
    var splitTag: String
    var movementPatterns: [String]
    var preferredVariationGroups: [String]
    var preferredNameFragments: [String]
    var exerciseType: ExerciseType = .reps
    var targetSets: Int?
    var targetReps: Int?
    var targetDuration: Int?
    var targetWeight: Double?
    var isAnchor: Bool
}

private enum BuiltInTemplateCategory {
    case push
    case pull
    case legs
    case shouldersCore

    var slotSpecs: [BuiltInSlotSpec] {
        switch self {
        case .push:
            return [
                BuiltInSlotSpec(splitTag: "push", movementPatterns: ["horizontal-press"], preferredVariationGroups: ["bench-press"], preferredNameFragments: ["bench"], targetSets: 4, targetReps: 6, isAnchor: true),
                BuiltInSlotSpec(splitTag: "push", movementPatterns: ["push-up"], preferredVariationGroups: ["push-up"], preferredNameFragments: ["push"], targetSets: 3, targetReps: 15, isAnchor: true),
                BuiltInSlotSpec(splitTag: "push", movementPatterns: ["incline-press"], preferredVariationGroups: [], preferredNameFragments: [], targetSets: 4, targetReps: 8, isAnchor: false),
                BuiltInSlotSpec(splitTag: "push", movementPatterns: ["chest-isolation", "chest-secondary"], preferredVariationGroups: [], preferredNameFragments: [], targetSets: 3, targetReps: 12, isAnchor: false),
                BuiltInSlotSpec(splitTag: "push", movementPatterns: ["triceps-extension"], preferredVariationGroups: [], preferredNameFragments: [], targetSets: 3, targetReps: 12, isAnchor: false),
                BuiltInSlotSpec(splitTag: "push", movementPatterns: ["lateral-delt"], preferredVariationGroups: [], preferredNameFragments: [], targetSets: 3, targetReps: 15, isAnchor: false)
            ]
        case .pull:
            return [
                BuiltInSlotSpec(splitTag: "pull", movementPatterns: ["hip-hinge"], preferredVariationGroups: ["deadlift"], preferredNameFragments: ["dead"], targetSets: 4, targetReps: 5, isAnchor: true),
                BuiltInSlotSpec(splitTag: "pull", movementPatterns: ["vertical-pull"], preferredVariationGroups: ["pull-up"], preferredNameFragments: ["pull"], targetSets: 4, targetReps: 8, isAnchor: true),
                BuiltInSlotSpec(splitTag: "pull", movementPatterns: ["horizontal-row"], preferredVariationGroups: [], preferredNameFragments: [], targetSets: 4, targetReps: 10, isAnchor: false),
                BuiltInSlotSpec(splitTag: "pull", movementPatterns: ["upper-back", "rear-delt"], preferredVariationGroups: [], preferredNameFragments: [], targetSets: 3, targetReps: 15, isAnchor: false),
                BuiltInSlotSpec(splitTag: "pull", movementPatterns: ["biceps-curl"], preferredVariationGroups: [], preferredNameFragments: [], targetSets: 3, targetReps: 10, isAnchor: false),
                BuiltInSlotSpec(splitTag: "pull", movementPatterns: ["lat-isolation", "forearm-grip"], preferredVariationGroups: [], preferredNameFragments: [], targetSets: 3, targetReps: 12, isAnchor: false)
            ]
        case .legs:
            return [
                BuiltInSlotSpec(splitTag: "legs", movementPatterns: ["squat"], preferredVariationGroups: ["squat"], preferredNameFragments: ["squat"], targetSets: 4, targetReps: 6, isAnchor: true),
                BuiltInSlotSpec(splitTag: "legs", movementPatterns: ["hinge-posterior"], preferredVariationGroups: [], preferredNameFragments: [], targetSets: 4, targetReps: 8, isAnchor: false),
                BuiltInSlotSpec(splitTag: "legs", movementPatterns: ["quad-compound"], preferredVariationGroups: [], preferredNameFragments: [], targetSets: 3, targetReps: 10, isAnchor: false),
                BuiltInSlotSpec(splitTag: "legs", movementPatterns: ["unilateral-leg"], preferredVariationGroups: [], preferredNameFragments: [], targetSets: 3, targetReps: 12, isAnchor: false),
                BuiltInSlotSpec(splitTag: "legs", movementPatterns: ["hamstring-isolation"], preferredVariationGroups: [], preferredNameFragments: [], targetSets: 3, targetReps: 12, isAnchor: false),
                BuiltInSlotSpec(splitTag: "legs", movementPatterns: ["calves"], preferredVariationGroups: [], preferredNameFragments: [], targetSets: 4, targetReps: 15, isAnchor: false)
            ]
        case .shouldersCore:
            return [
                BuiltInSlotSpec(splitTag: "shoulders", movementPatterns: ["vertical-press"], preferredVariationGroups: ["overhead-press"], preferredNameFragments: ["press"], targetSets: 4, targetReps: 8, isAnchor: true),
                BuiltInSlotSpec(splitTag: "shoulders", movementPatterns: ["lateral-delt"], preferredVariationGroups: [], preferredNameFragments: [], targetSets: 4, targetReps: 15, isAnchor: false),
                BuiltInSlotSpec(splitTag: "shoulders", movementPatterns: ["rear-delt"], preferredVariationGroups: [], preferredNameFragments: [], targetSets: 3, targetReps: 15, isAnchor: false),
                BuiltInSlotSpec(splitTag: "arms", movementPatterns: ["biceps-curl"], preferredVariationGroups: [], preferredNameFragments: [], targetSets: 3, targetReps: 10, isAnchor: false),
                BuiltInSlotSpec(splitTag: "arms", movementPatterns: ["triceps-extension"], preferredVariationGroups: [], preferredNameFragments: [], targetSets: 3, targetReps: 12, isAnchor: false),
                BuiltInSlotSpec(splitTag: "arms", movementPatterns: ["forearm-grip", "arm-secondary"], preferredVariationGroups: [], preferredNameFragments: [], targetSets: 3, targetReps: 12, isAnchor: false),
                BuiltInSlotSpec(splitTag: "core", movementPatterns: ["core-flexion"], preferredVariationGroups: ["hanging-leg-raise"], preferredNameFragments: ["raise"], targetSets: 3, targetReps: 15, isAnchor: true),
                BuiltInSlotSpec(splitTag: "core", movementPatterns: ["core-flexion", "core-stability"], preferredVariationGroups: [], preferredNameFragments: [], targetSets: 3, targetReps: 20, isAnchor: false)
            ]
        }
    }
}

private extension String {
    func matches(in exercise: Exercise) -> Bool {
        let name = exercise.name.lowercased()
        return name.contains(lowercased())
    }
}
