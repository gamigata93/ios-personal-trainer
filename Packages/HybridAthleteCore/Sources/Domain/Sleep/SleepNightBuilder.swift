import Foundation

/// Turns raw sleep segments into one night per wake date.
public enum SleepNightBuilder {
    /// What was left out, for the DEBUG export.
    public struct Ignored: Sendable, Equatable, Codable {
        public var naps = 0
        public var tooShort = 0
        public var inBedSegments = 0

        public init(naps: Int = 0, tooShort: Int = 0, inBedSegments: Int = 0) {
            self.naps = naps
            self.tooShort = tooShort
            self.inBedSegments = inBedSegments
        }
    }

    public struct Result: Sendable, Equatable {
        /// Oldest first, one per wake date.
        public let nights: [SleepNight]
        public let ignored: Ignored
        /// The segments behind each chosen night, for the DEBUG export. Never cached.
        public let segmentsByNight: [LocalDate: [SleepSegment]]
    }

    /// 1. In-bed segments are dropped; each source's segments are split into
    ///    sessions at gaps over `SleepRules.sessionGapMinutes`.
    /// 2. Minutes are unions of intervals. A session without sleep is dropped.
    /// 3. The wake date is the local date of the last asleep moment.
    /// 4. Naps and too-short sessions are dropped.
    /// 5. Per wake date the session with the most sleep wins; ties prefer
    ///    `SleepRules.preferredSource`, then the alphabetically first source.
    public static func build(_ segments: [SleepSegment], calendar: Calendar) -> Result {
        var ignored = Ignored(inBedSegments: segments.filter { $0.stage == .inBed }.count)
        let bySource = Dictionary(grouping: segments.filter { $0.stage != .inBed }, by: \.source)

        var candidates: [(night: SleepNight, segments: [SleepSegment])] = []
        for (source, sourceSegments) in bySource {
            for session in sessions(sourceSegments) {
                guard let night = night(from: session, source: source, calendar: calendar) else { continue }
                if isNap(night, calendar: calendar) {
                    ignored.naps += 1
                } else if night.asleepMinutes < SleepRules.minNightAsleepMinutes {
                    ignored.tooShort += 1
                } else {
                    candidates.append((night, session))
                }
            }
        }

        var chosen: [LocalDate: (night: SleepNight, segments: [SleepSegment])] = [:]
        for candidate in candidates.sorted(by: { $0.night.wakeTime < $1.night.wakeTime }) {
            if let current = chosen[candidate.night.wakeDate], !beats(candidate.night, current.night) { continue }
            chosen[candidate.night.wakeDate] = candidate
        }
        return Result(
            nights: chosen.values.map(\.night).sorted { $0.wakeDate < $1.wakeDate },
            ignored: ignored,
            segmentsByNight: chosen.mapValues(\.segments)
        )
    }

    // MARK: Steps

    /// One source's segments split at gaps longer than the session gap.
    static func sessions(_ segments: [SleepSegment]) -> [[SleepSegment]] {
        let gap = TimeInterval(SleepRules.sessionGapMinutes * 60)
        var sessions: [[SleepSegment]] = []
        var latestEnd: Date?
        for segment in segments.sorted(by: { ($0.start, $0.end) < ($1.start, $1.end) }) {
            if let end = latestEnd, segment.start.timeIntervalSince(end) <= gap {
                sessions[sessions.count - 1].append(segment)
                latestEnd = max(end, segment.end)
            } else {
                sessions.append([segment])
                latestEnd = segment.end
            }
        }
        return sessions
    }

    private static func night(from session: [SleepSegment], source: String, calendar: Calendar) -> SleepNight? {
        let asleep = session.filter(\.stage.isAsleep)
        guard
            let sleepStart = asleep.map(\.start).min(),
            let wakeTime = asleep.map(\.end).max(),
            let first = session.map(\.start).min(),
            let last = session.map(\.end).max()
        else { return nil }

        func minutes(_ stages: Set<SleepStage>) -> Int {
            unionMinutes(session.filter { stages.contains($0.stage) })
        }
        let deep = minutes([.deep])
        let core = minutes([.core])
        let rem = minutes([.rem])
        return SleepNight(
            wakeDate: LocalDate(date: wakeTime, calendar: calendar),
            sleepStart: sleepStart,
            wakeTime: wakeTime,
            asleepMinutes: unionMinutes(asleep),
            deepMinutes: deep,
            coreMinutes: core,
            remMinutes: rem,
            unspecifiedMinutes: minutes([.asleepUnspecified]),
            awakeMinutes: minutes([.awake]),
            timeInBedMinutes: Int((last.timeIntervalSince(first) / 60).rounded()),
            hasStages: deep + core + rem > 0,
            sourceLabel: source
        )
    }

    /// Less sleep than a night and a wake time from 09:00 up to 20:00 local.
    private static func isNap(_ night: SleepNight, calendar: Calendar) -> Bool {
        guard night.asleepMinutes < SleepRules.napMaxAsleepMinutes else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: night.wakeTime)
        let minuteOfDay = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return minuteOfDay >= SleepRules.napWindowStartHour * 60 && minuteOfDay < SleepRules.napWindowEndHour * 60
    }

    /// More sleep wins; a tie goes to the preferred source, then the first label.
    private static func beats(_ challenger: SleepNight, _ current: SleepNight) -> Bool {
        if challenger.asleepMinutes != current.asleepMinutes {
            return challenger.asleepMinutes > current.asleepMinutes
        }
        let preferred = SleepRules.preferredSource
        if (challenger.sourceLabel == preferred) != (current.sourceLabel == preferred) {
            return challenger.sourceLabel == preferred
        }
        return challenger.sourceLabel < current.sourceLabel
    }

    /// Total minutes covered by the segments, counting overlaps once.
    static func unionMinutes(_ segments: [SleepSegment]) -> Int {
        var total: TimeInterval = 0
        var current: (start: Date, end: Date)?
        for segment in segments.sorted(by: { $0.start < $1.start }) where segment.end > segment.start {
            if let open = current, segment.start <= open.end {
                current = (open.start, max(open.end, segment.end))
            } else {
                if let open = current { total += open.end.timeIntervalSince(open.start) }
                current = (segment.start, segment.end)
            }
        }
        if let open = current { total += open.end.timeIntervalSince(open.start) }
        return Int((total / 60).rounded())
    }
}
