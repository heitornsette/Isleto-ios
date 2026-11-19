import Foundation

/// Muscle group of an exercise. Stored as the raw value (`exercises.muscle`).
public enum Muscle: String, CaseIterable, Codable, Sendable {
    case chest, back, legs, glutes, calves, shoulders, biceps, triceps, abs, other

    public init(storage: String) {
        self = Muscle(rawValue: storage) ?? .other
    }

    public var label: String {
        switch self {
        case .chest: "Peito"
        case .back: "Costas"
        case .legs: "Pernas"
        case .glutes: "Glúteos"
        case .calves: "Panturrilha"
        case .shoulders: "Ombros"
        case .biceps: "Bíceps"
        case .triceps: "Tríceps"
        case .abs: "Abdômen"
        case .other: "Outros"
        }
    }
}

/// An exercise of the library (`exercises`).
public struct Exercise: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let uuid: String
    public var name: String
    public var muscle: Muscle
    public var notes: String
    public var archived: Bool

    public init(id: Int64, uuid: String, name: String, muscle: Muscle, notes: String = "", archived: Bool = false) {
        self.id = id
        self.uuid = uuid
        self.name = name
        self.muscle = muscle
        self.notes = notes
        self.archived = archived
    }
}

/// An exercise the app offers before it is in the library. Its uuid is fixed, so two
/// devices that add the same one write the same row and the sync joins them.
public struct CatalogExercise: Identifiable, Equatable, Sendable {
    public let uuid: String
    public let name: String
    public let muscle: Muscle

    public var id: String { uuid }

    init(_ uuid: String, _ name: String, _ muscle: Muscle) {
        self.uuid = uuid
        self.name = name
        self.muscle = muscle
    }
}

public enum ExerciseCatalog {
    /// UUIDs are version 5 of the name (generated once; never change one that shipped).
    public static let all: [CatalogExercise] = [
        .init("18ec393b-079e-5e2c-84c1-c4c6a05a4d2c", "Supino reto", .chest),
        .init("b8f08cea-f34d-5bfa-b7fb-ef937214dabe", "Supino inclinado", .chest),
        .init("2405e696-abc4-5f8a-9a1a-90889999fbff", "Supino declinado", .chest),
        .init("d8fdafb7-38ab-5a89-8303-ab62377bffae", "Supino com halteres", .chest),
        .init("b614f095-f929-5122-a31e-1c07472b26bd", "Crucifixo", .chest),
        .init("5e2b99d3-1226-5e79-8559-c6067a04ddcb", "Crossover", .chest),
        .init("0c855d27-e23a-5fd7-8b11-2eb90f030923", "Voador (peck deck)", .chest),
        .init("55f0585a-6afa-5de8-b3a3-14eebc227a9b", "Flexão de braço", .chest),
        .init("8287844f-6c65-5ee7-a5fa-3d1ae2a4c800", "Puxada frontal", .back),
        .init("b870ac0f-0cbc-541d-8309-20c39233ba58", "Barra fixa", .back),
        .init("2fdb01f0-5f4c-5988-8c07-e8fb4300e39c", "Remada curvada", .back),
        .init("e58dbdc2-55f3-5f19-8054-7b89bad0804b", "Remada baixa", .back),
        .init("755428f9-cbfe-5d9b-a080-1797d3118e07", "Remada unilateral", .back),
        .init("4851967f-5fbe-5e74-ab79-e0b230de814c", "Pulldown", .back),
        .init("8258a001-a2da-59d6-9034-4d44cb21a708", "Levantamento terra", .back),
        .init("cd157da4-2726-5c22-9e16-8027d644d1d1", "Agachamento livre", .legs),
        .init("d35ab642-a75a-57c7-9f8f-938130613aab", "Agachamento no Smith", .legs),
        .init("c55ed538-1a38-5028-bb8e-250e9dfa3789", "Leg press", .legs),
        .init("bad3d38e-daf9-5603-b58d-2fb58818bff2", "Hack", .legs),
        .init("3042ad65-33e3-51c3-be87-f7d98833fa35", "Cadeira extensora", .legs),
        .init("09930205-bbc3-581b-8e9a-047a110856b9", "Mesa flexora", .legs),
        .init("4e203caa-57c9-58fe-af31-9626f98141a1", "Cadeira flexora", .legs),
        .init("f9249805-9d7b-525d-8f93-ddf2caabf1e8", "Stiff", .legs),
        .init("6a44fe57-39fb-5749-b228-57e7e5efa3c1", "Afundo", .legs),
        .init("e2de5b47-323a-5257-8836-7325c4e3532c", "Agachamento búlgaro", .legs),
        .init("226ebf6a-db6f-524b-99cc-e50459cf7de7", "Cadeira abdutora", .legs),
        .init("c14b20c4-c872-5bb1-9d61-37a0171cfacf", "Cadeira adutora", .legs),
        .init("81d792e4-314b-5855-a8ea-defc0672fe24", "Elevação pélvica", .glutes),
        .init("ffc9048f-b2dc-5cbd-9bf7-0b35e5fa0fb2", "Glúteo na polia", .glutes),
        .init("4db20dd0-2ce6-5bff-9afe-fa7bdc7f5dd3", "Panturrilha em pé", .calves),
        .init("226ec833-91d8-591d-b776-26c7b833a0ba", "Panturrilha sentado", .calves),
        .init("75bcaa41-259a-5499-81d4-c0d2b528fe3a", "Desenvolvimento", .shoulders),
        .init("7dfcd916-1460-5442-acce-6ae2ede919f5", "Desenvolvimento com halteres", .shoulders),
        .init("be28b318-cab8-5c23-a42c-42410cdb5f63", "Elevação lateral", .shoulders),
        .init("e115cb03-908a-5896-a9ce-da36d2acc800", "Elevação frontal", .shoulders),
        .init("0a620166-b8db-5611-9114-8c8a27945759", "Crucifixo invertido", .shoulders),
        .init("298f01ac-1d05-5fde-b3a1-e65c0ca31854", "Encolhimento", .shoulders),
        .init("71828e24-5dca-554f-9ee1-565cc1e45f74", "Rosca direta", .biceps),
        .init("05c8af9e-a4dc-5e5d-a152-3af7db8b4595", "Rosca alternada", .biceps),
        .init("4afb46a8-4212-5c42-a724-6b4913f22f65", "Rosca martelo", .biceps),
        .init("9964e9c2-8056-56da-8fbe-543bffe6e442", "Rosca Scott", .biceps),
        .init("071300ac-c048-5ea9-88df-fa172f9469d8", "Rosca na polia", .biceps),
        .init("b5fc8cc1-b053-57f9-a30a-93b4dd9f2791", "Tríceps na polia", .triceps),
        .init("68c5442f-e277-51d3-bee6-7c08cf66b355", "Tríceps corda", .triceps),
        .init("0150c7be-17a8-5acd-ab64-ac5b451e65da", "Tríceps testa", .triceps),
        .init("c0f04382-fde8-5fd3-802a-cf9c99a4fc78", "Tríceps francês", .triceps),
        .init("5b434ce4-af05-5c67-a108-e142fb7fd692", "Mergulho", .triceps),
        .init("aa61372e-8b6b-578e-a01b-c40776794b10", "Abdominal", .abs),
        .init("43f5d1ca-9ba1-58bc-9df2-88f2c95139a9", "Prancha", .abs),
        .init("c9de3714-9acf-5220-9235-403dd6f6bee0", "Elevação de pernas", .abs),
        .init("492453e9-f36f-530d-8173-9e073b86749f", "Abdominal na polia", .abs),
    ]
}

/// An exercise of a workout plan ("ficha").
public struct PlanExercise: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let exerciseID: Int64
    public var name: String
    public var muscle: Muscle
    public var position: Int
    public var sets: Int
    /// Text, like "10" or "8-12".
    public var reps: String
    public var restSeconds: Int
}

/// A workout plan ("ficha"): the exercises of a kind of workout, in order.
public struct WorkoutPlan: Identifiable, Equatable, Sendable {
    public let id: Int64
    public var name: String
    public var notes: String
    public var sortOrder: Int
    public var exercises: [PlanExercise]
}

/// One set of a workout.
public struct WorkoutSet: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let exerciseID: Int64
    public var setNumber: Int
    public var reps: Int
    /// Kilograms.
    public var weight: Double
    public var done: Bool

    public var volume: Double { Double(reps) * weight }
}

/// What a set was the last time: shown next to the set to beat.
public struct PreviousSet: Equatable, Sendable {
    public let reps: Int
    public let weight: Double

    public init(reps: Int, weight: Double) {
        self.reps = reps
        self.weight = weight
    }
}

/// The sets of one exercise in a workout.
public struct WorkoutBlock: Identifiable, Equatable, Sendable {
    public let exerciseID: Int64
    public var name: String
    public var muscle: Muscle
    public var position: Int
    /// Rest after each set: from the plan, else the default.
    public var restSeconds: Int
    public var sets: [WorkoutSet]
    /// Done sets of the last finished workout with this exercise.
    public var previous: [PreviousSet]
    /// Heaviest done set of the other finished workouts. Nil the first time.
    public var record: Double?

    public var id: Int64 { exerciseID }
}

/// A workout session. `finishedAt` is nil while it runs.
public struct Workout: Identifiable, Equatable, Sendable {
    public let id: Int64
    public var planID: Int64?
    public var name: String
    public var startedAt: Date
    public var finishedAt: Date?
    public var notes: String
    public var blocks: [WorkoutBlock]

    public var isActive: Bool { finishedAt == nil }
    public var doneSets: Int { blocks.reduce(0) { $0 + $1.sets.filter(\.done).count } }
    public var totalSets: Int { blocks.reduce(0) { $0 + $1.sets.count } }
    /// Sum of reps x kg of the done sets.
    public var volume: Double {
        blocks.reduce(0) { total, block in total + block.sets.filter(\.done).reduce(0) { $0 + $1.volume } }
    }
}

/// A finished workout, for the history list.
public struct WorkoutSummary: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let name: String
    public let startedAt: Date
    public let finishedAt: Date
    public let exercises: Int
    public let sets: Int
    public let volume: Double

    public var duration: TimeInterval { max(0, finishedAt.timeIntervalSince(startedAt)) }
}

/// The history of one exercise, newest first.
public struct ExerciseHistory: Equatable, Sendable {
    public struct Entry: Identifiable, Equatable, Sendable {
        public let workoutID: Int64
        public let date: Date
        public let sets: [PreviousSet]

        public var id: Int64 { workoutID }
        public var bestWeight: Double { sets.map(\.weight).max() ?? 0 }
    }

    public let entries: [Entry]

    /// Heaviest done set ever.
    public var record: Double? { entries.map(\.bestWeight).max() }
}

public enum WorkoutRules {
    /// First number of a reps text ("8-12" -> 8). 10 when there is none.
    public static func targetReps(_ text: String) -> Int {
        let digits = text.drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int(digits).map { max(0, $0) } ?? 10
    }
}
