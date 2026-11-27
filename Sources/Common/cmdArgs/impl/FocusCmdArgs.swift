public struct FocusCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    fileprivate init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .focus,
        help: focus_help_generated,
        flags: [
            "--ignore-floating": falseBoolFlag(\.floatingAsTiling),
            "--window-id": windowIdSubArgParser(),
            "--dfs-index": singleValueSubArgParser(\.dfsIndex, "<dfs-index>", parseUInt32),

            "--boundaries": ArgParser(\.rawBoundaries, upcastArgParserFun(parseBoundaries)),
            "--boundaries-action": ArgParser(\.rawBoundariesAction, upcastArgParserFun(parseBoundariesAction)),
            "--fail-if-fullscreen": trueBoolFlag(\.failIfFullscreen),
            "--fail-if-macos-native-fullscreen": trueBoolFlag(\.failIfMacosNativeFullscreen),
            "--wrap-around": trueBoolFlag(\.wrapAroundAlias),
            "--keep-fullscreen": trueBoolFlag(\.keepFullscreen),
            "--cycle": singleValueSubArgParser(\.cycle, "(next|prev)", parseCycle),
        ],
        posArgs: [ArgParser(\.cardinalOrDfsDirection, upcastArgParserFun(parseCardinalOrDfsDirection))],
        conflictingOptions: [
            ["--wrap-around", "--boundaries-action"],
            ["--wrap-around", "--boundaries"],
        ],
    )

    public var rawBoundaries: Boundaries? = nil // todo cover boundaries wrapping with tests
    public var rawBoundariesAction: WhenBoundariesCrossed? = nil
    public var failIfFullscreen: Bool = false
    public var failIfMacosNativeFullscreen: Bool = false
    fileprivate var wrapAroundAlias: Bool = false
    public var dfsIndex: UInt32? = nil
    public var cardinalOrDfsDirection: CardinalOrDfsDirection? = nil
    public var floatingAsTiling: Bool = true
    // hbak fork: with --window-id, hand the focused window's fullscreen to the target in the same
    // layout pass, so flipping between fullscreen windows doesn't flash the split layout.
    public var keepFullscreen: Bool = false
    // hbak fork: --cycle next|prev rotates focus through every window on the workspace, floating
    // included, in window-id order, wrapping. Carries fullscreen over like --keep-fullscreen.
    public var cycle: String? = nil

    public init(rawArgs: StrArrSlice, cardinalOrDfsDirection: CardinalOrDfsDirection) {
        self.commonState = .init(rawArgs)
        self.cardinalOrDfsDirection = cardinalOrDfsDirection
    }

    public init(rawArgs: StrArrSlice, windowId: UInt32) {
        self.commonState = .init(rawArgs)
        self.windowId = windowId
    }

    public init(rawArgs: StrArrSlice, dfsIndex: UInt32) {
        self.commonState = .init(rawArgs)
        self.dfsIndex = dfsIndex
    }

    public enum Boundaries: String, CaseIterable, Equatable, Sendable {
        case workspace
        case allMonitorsOuterFrame = "all-monitors-outer-frame"
    }
    public enum WhenBoundariesCrossed: String, CaseIterable, Equatable, Sendable {
        case stop = "stop"
        case fail = "fail"
        case wrapAroundTheWorkspace = "wrap-around-the-workspace"
        case wrapAroundAllMonitors = "wrap-around-all-monitors"
    }
}

public enum FocusCmdTarget {
    case direction(CardinalDirection)
    case windowId(UInt32)
    case dfsIndex(UInt32)
    case dfsRelative(DfsNextPrev)
    case cycle(next: Bool)

    var isDfsRelative: Bool {
        switch self {
            case .dfsRelative: true
            default: false
        }
    }
}

extension FocusCmdArgs {
    public var target: FocusCmdTarget {
        if let cardinalOrDfsDirection {
            return switch cardinalOrDfsDirection {
                case .direction(let dir): .direction(dir)
                case .dfsRelative(let nextPrev): .dfsRelative(nextPrev)
            }
        }
        if let windowId {
            return .windowId(windowId)
        }
        if let dfsIndex {
            return .dfsIndex(dfsIndex)
        }
        if let cycle {
            return .cycle(next: cycle == "next")
        }
        die("Parser invariants are broken")
    }

    public var boundaries: Boundaries { rawBoundaries ?? .workspace }
    public var boundariesAction: WhenBoundariesCrossed {
        wrapAroundAlias ? .wrapAroundTheWorkspace : (rawBoundariesAction ?? .stop)
    }
}

func parseFocusCmdArgs(_ args: StrArrSlice) -> ParsedCmd<FocusCmdArgs> {
    return parseSpecificCmdArgs(FocusCmdArgs(rawArgs: args), args)
        .flatMap { (raw: FocusCmdArgs) -> ParsedCmd<FocusCmdArgs> in
            raw.boundaries == .workspace && raw.boundariesAction == .wrapAroundAllMonitors
                ? .failure("\(raw.boundaries.rawValue) and \(raw.boundariesAction.rawValue) is an invalid combination of values")
                : .cmd(raw)
        }
        .filter("Mandatory argument is missing. \(CardinalOrDfsDirection.unionLiteral), --window-id or --dfs-index is required") {
            $0.cardinalOrDfsDirection != nil || $0.windowId != nil || $0.dfsIndex != nil || $0.cycle != nil
        }
        .filter("--cycle is incompatible with other options") {
            $0.cycle == nil || ($0.cardinalOrDfsDirection == nil && $0.windowId == nil && $0.dfsIndex == nil)
        }
        .filter("--window-id is incompatible with other options except --keep-fullscreen") {
            var plain = $0
            plain.keepFullscreen = false
            return $0.windowId == nil || plain == FocusCmdArgs(rawArgs: args, windowId: $0.windowId.orDie())
        }
        .filter("--keep-fullscreen requires --window-id") {
            $0.keepFullscreen.implies($0.windowId != nil)
        }
        .filter("--dfs-index is incompatible with other options") {
            $0.dfsIndex == nil || $0 == FocusCmdArgs(rawArgs: args, dfsIndex: $0.dfsIndex.orDie())
        }
        .filter("--fail-if-fullscreen/--fail-if-macos-native-fullscreen require using (left|down|up|right) argument") {
            if !$0.failIfFullscreen && !$0.failIfMacosNativeFullscreen {
                return true
            }
            return switch $0.target {
                case .direction: true
                case .dfsIndex, .dfsRelative, .windowId, .cycle: false
            }
        }
        .filter("(dfs-next|dfs-prev) only supports --boundaries workspace") {
            $0.target.isDfsRelative.implies($0.boundaries == .workspace)
        }
}

private func parseBoundariesAction(i: SubArgParserInput) -> ParsedCliArgs<FocusCmdArgs.WhenBoundariesCrossed> {
    if let arg = i.nonFlagArgOrNil() {
        return .init(parseEnum(arg, FocusCmdArgs.WhenBoundariesCrossed.self), advanceBy: 1)
    } else {
        return .fail("<action> is mandatory", advanceBy: 0)
    }
}

private func parseBoundaries(i: SubArgParserInput) -> ParsedCliArgs<FocusCmdArgs.Boundaries> {
    if let arg = i.nonFlagArgOrNil() {
        return .init(parseEnum(arg, FocusCmdArgs.Boundaries.self), advanceBy: 1)
    } else {
        return .fail("<boundary> is mandatory", advanceBy: 0)
    }
}

private func parseCycle(_ str: String) -> ResOrStr<String> {
    str == "next" || str == "prev" ? .success(str) : .failure("--cycle takes next or prev, got '\(str)'")
}
