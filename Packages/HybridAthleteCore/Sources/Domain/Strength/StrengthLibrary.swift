import Foundation

/// How an exercise is dosed.
public enum StrengthDosing: Sendable, Equatable {
    /// Repetitions that follow the phase (`StrengthRules.repDose`).
    case reps
    /// A timed hold that follows the phase (`StrengthRules.holdDose`).
    case hold
    /// The same dose in every phase (mobility work).
    case fixedReps(sets: Int, reps: Int)
    case fixedHold(sets: Int, seconds: Int)
}

/// One exercise in the library, before a phase sets its dose.
public struct LibraryExercise: Sendable, Equatable {
    public let name: String
    public let dosing: StrengthDosing
    public let perSide: Bool
    public let equipment: StrengthEquipment
    public let howTo: String

    public init(_ name: String, _ dosing: StrengthDosing, perSide: Bool = false, _ equipment: StrengthEquipment = .bodyweight, howTo: String) {
        self.name = name
        self.dosing = dosing
        self.perSide = perSide
        self.equipment = equipment
        self.howTo = howTo
    }
}

/// The fixed exercise lists: two per focus (A and B). Nothing is random: the
/// same focus, variant and phase always give the same exercises and doses.
/// A first draft written for this app, not from a cited source; edit freely.
public enum StrengthLibrary {
    public static func exercises(_ focus: StrengthFocus, _ variant: StrengthVariant) -> [LibraryExercise] {
        switch (focus, variant) {
        case (.lowerBody, .a): [
            LibraryExercise("Goblet squat", .reps, .dumbbell, howTo: "Hold the weight at your chest, sit down between your heels, chest up."),
            LibraryExercise("Romanian deadlift", .reps, .dumbbell, howTo: "Soft knees, push the hips back until you feel the hamstrings, then stand tall."),
            LibraryExercise("Reverse lunge", .reps, perSide: true, .dumbbell, howTo: "Step back, lower the back knee toward the floor, drive up through the front heel."),
            LibraryExercise("Glute bridge", .reps, howTo: "On your back, feet flat, lift the hips until knees, hips and shoulders line up."),
            LibraryExercise("Side plank", .hold, perSide: true, howTo: "On one forearm, body in a straight line, hips high."),
        ]
        case (.lowerBody, .b): [
            LibraryExercise("Split squat", .reps, perSide: true, .dumbbell, howTo: "Long stance, lower straight down, front knee over the middle of the foot."),
            LibraryExercise("Single-leg Romanian deadlift", .reps, perSide: true, .dumbbell, howTo: "Hinge on one leg, back leg reaching long, hips level."),
            LibraryExercise("Step-up", .reps, perSide: true, .dumbbell, howTo: "Step onto a knee-high box, stand fully, lower with control."),
            LibraryExercise("Single-leg glute bridge", .reps, perSide: true, howTo: "One foot down, the other knee to the chest, lift the hips level."),
            LibraryExercise("Wall sit", .hold, howTo: "Back on the wall, thighs parallel to the floor, knees over the ankles."),
        ]
        case (.calvesFeet, .a): [
            LibraryExercise("Straight-knee calf raise", .reps, howTo: "On a step, rise onto the toes, pause, lower slowly below the step."),
            LibraryExercise("Bent-knee calf raise", .reps, howTo: "Knees slightly bent, rise and lower slowly; works the deeper calf muscle."),
            LibraryExercise("Tibialis raise", .reps, howTo: "Back against a wall, heels forward, lift the toes toward the shins."),
            LibraryExercise("Single-leg balance", .hold, perSide: true, howTo: "Stand on one foot, knee soft, toes relaxed; hold steady."),
            LibraryExercise("Towel scrunch", .fixedHold(sets: 2, seconds: 60), howTo: "Seated, pull a towel toward you with your toes."),
        ]
        case (.calvesFeet, .b): [
            LibraryExercise("Single-leg calf raise", .reps, perSide: true, howTo: "On one foot on a step, full range, slow on the way down."),
            LibraryExercise("Weighted calf raise", .reps, .dumbbell, howTo: "A weight in each hand, rise onto the toes, lower slowly."),
            LibraryExercise("Heel walk", .fixedHold(sets: 2, seconds: 30), howTo: "Walk on your heels, toes up, short steps."),
            LibraryExercise("Short foot", .hold, perSide: true, howTo: "Shorten the foot by lifting the arch without curling the toes."),
            LibraryExercise("Pogo hops", .fixedReps(sets: 2, reps: 20), howTo: "Small quick hops on the balls of the feet, knees almost straight."),
        ]
        case (.core, .a): [
            LibraryExercise("Front plank", .hold, howTo: "On the forearms, body in a straight line, squeeze the glutes."),
            LibraryExercise("Dead bug", .reps, perSide: true, howTo: "On your back, lower the opposite arm and leg slowly, lower back stays down."),
            LibraryExercise("Side plank", .hold, perSide: true, howTo: "On one forearm, body in a straight line, hips high."),
            LibraryExercise("Bird dog", .reps, perSide: true, howTo: "On hands and knees, reach the opposite arm and leg long, hips still."),
            LibraryExercise("Glute bridge", .reps, howTo: "On your back, feet flat, lift the hips until knees, hips and shoulders line up."),
        ]
        case (.core, .b): [
            LibraryExercise("Pallof press", .reps, perSide: true, .band, howTo: "Band at chest height to the side, press it straight out without turning."),
            LibraryExercise("Hollow hold", .hold, howTo: "On your back, arms and legs long and off the floor, lower back down."),
            LibraryExercise("Suitcase carry", .hold, perSide: true, .dumbbell, howTo: "A heavy weight in one hand, walk tall without leaning."),
            LibraryExercise("Side plank with leg lift", .reps, perSide: true, howTo: "In a side plank, lift the top leg slowly and lower it."),
            LibraryExercise("Reverse crunch", .reps, howTo: "On your back, knees bent, curl the hips off the floor slowly."),
        ]
        case (.fullBody, .a): [
            LibraryExercise("Goblet squat", .reps, .dumbbell, howTo: "Hold the weight at your chest, sit down between your heels, chest up."),
            LibraryExercise("Push-up", .reps, howTo: "Hands under the shoulders, body straight; on the knees if needed."),
            LibraryExercise("Single-leg Romanian deadlift", .reps, perSide: true, .dumbbell, howTo: "Hinge on one leg, back leg reaching long, hips level."),
            LibraryExercise("Bent-over row", .reps, .dumbbell, howTo: "Hinge forward, flat back, pull the weights to the ribs."),
            LibraryExercise("Front plank", .hold, howTo: "On the forearms, body in a straight line, squeeze the glutes."),
        ]
        case (.fullBody, .b): [
            LibraryExercise("Reverse lunge", .reps, perSide: true, .dumbbell, howTo: "Step back, lower the back knee toward the floor, drive up through the front heel."),
            LibraryExercise("Overhead press", .reps, .dumbbell, howTo: "Standing tall, press the weights overhead without arching the back."),
            LibraryExercise("Romanian deadlift", .reps, .dumbbell, howTo: "Soft knees, push the hips back until you feel the hamstrings, then stand tall."),
            LibraryExercise("Single-arm row", .reps, perSide: true, .dumbbell, howTo: "One hand on a bench, pull the weight to the hip."),
            LibraryExercise("Dead bug", .reps, perSide: true, howTo: "On your back, lower the opposite arm and leg slowly, lower back stays down."),
        ]
        case (.mobility, .a): [
            LibraryExercise("Hip flexor stretch", .fixedHold(sets: 2, seconds: 45), perSide: true, howTo: "Half-kneeling, tuck the pelvis and shift forward gently."),
            LibraryExercise("World's greatest stretch", .fixedReps(sets: 2, reps: 5), perSide: true, howTo: "Long lunge, elbow to the instep, then rotate the arm to the sky."),
            LibraryExercise("Ankle dorsiflexion rock", .fixedReps(sets: 2, reps: 10), perSide: true, howTo: "Half-kneeling, drive the front knee over the toes, heel down."),
            LibraryExercise("Hamstring sweep", .fixedReps(sets: 2, reps: 10), perSide: true, howTo: "Heel forward, hinge and sweep the hands along the floor."),
            LibraryExercise("Cat-cow", .fixedReps(sets: 2, reps: 10), howTo: "On hands and knees, round then arch the back slowly."),
        ]
        case (.mobility, .b): [
            LibraryExercise("90/90 hip switch", .fixedReps(sets: 2, reps: 8), perSide: true, howTo: "Seated with both knees bent at 90 degrees, rotate the knees side to side."),
            LibraryExercise("Calf stretch on a wall", .fixedHold(sets: 2, seconds: 45), perSide: true, howTo: "Back leg straight, heel down, lean into the wall."),
            LibraryExercise("Thoracic rotation", .fixedReps(sets: 2, reps: 8), perSide: true, howTo: "On your side, knees bent, open the top arm across to the other side."),
            LibraryExercise("Glute stretch", .fixedHold(sets: 2, seconds: 45), perSide: true, howTo: "On your back, ankle over the opposite knee, pull the thigh in."),
            LibraryExercise("Leg swings", .fixedReps(sets: 2, reps: 12), perSide: true, howTo: "Hold a wall, swing one leg front to back, relaxed."),
        ]
        }
    }
}
