public enum CLICommand: Equatable, Sendable {
    case fans
    case keys(prefix: String?)
    case sensors(raw: Bool)
    case auto
    case set(fan: Int, rpm: Double, hold: Int)
    case help

    public static let maxHold = 120

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case unknownCommand(String)
        case usage(String)
        public var description: String {
            switch self {
            case .unknownCommand(let c): return "bilinmeyen komut: \(c)"
            case .usage(let u): return u
            }
        }
    }

    public static let setUsage = "kullanım: boreasctl set <fan> <rpm> --hold <saniye> (1...\(maxHold), zorunlu)"

    public static func parse(_ args: [String]) throws -> CLICommand {
        guard let cmd = args.first else { return .help }
        let rest = Array(args.dropFirst())
        switch cmd {
        case "fans": return .fans
        case "auto": return .auto
        case "sensors":
            guard rest.isEmpty || rest == ["--raw"] else { throw ParseError.usage("kullanım: boreasctl sensors [--raw]") }
            return .sensors(raw: !rest.isEmpty)
        case "help", "-h", "--help": return .help
        case "keys": return .keys(prefix: rest.first)
        case "set":
            guard rest.count == 4, rest[2] == "--hold",
                  let fan = Int(rest[0]), fan >= 0,
                  let rpm = Double(rest[1]), rpm.isFinite, rpm >= 0,
                  let hold = Int(rest[3]), (1...maxHold).contains(hold)
            else { throw ParseError.usage(setUsage) }
            return .set(fan: fan, rpm: rpm, hold: hold)
        default: throw ParseError.unknownCommand(cmd)
        }
    }
}
