import Foundation

// MARK: - 智能内容类型

enum SmartContentType: Equatable {
    /// 颜色值（RGBA 分量 0~1）
    case color(red: Double, green: Double, blue: Double, alpha: Double)
    /// 电话号码
    case phoneNumber
    /// 邮箱地址
    case email
    /// 普通内容，无特殊类型
    case none
}

// MARK: - 智能内容检测器

enum SmartContentDetector {

    /// 检测文本中的智能内容类型。仅当整段文本匹配时才返回对应类型。
    static func detect(_ text: String) -> SmartContentType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }

        // 优先检测颜色（最直观的视觉识别）
        if let color = detectColor(trimmed) {
            return color
        }

        // 邮箱检测（优先于电话，因为邮箱格式更严格）
        if detectEmail(trimmed) {
            return .email
        }

        // 电话号码检测
        if detectPhoneNumber(trimmed) {
            return .phoneNumber
        }

        return .none
    }

    // MARK: - 颜色检测

    private static func detectColor(_ text: String) -> SmartContentType? {
        // Hex: #RGB, #RRGGBB, #RRGGBBAA
        if let color = parseHexColor(text) {
            return color
        }

        // rgb() / rgba()
        if let color = parseRGBColor(text) {
            return color
        }

        // hsl() / hsla()
        if let color = parseHSLColor(text) {
            return color
        }

        return nil
    }

    private static func parseHexColor(_ text: String) -> SmartContentType? {
        let pattern = #"^#([0-9A-Fa-f]{3,8})$"#
        guard let match = text.range(of: pattern, options: .regularExpression) else { return nil }
        let hex = String(text[match]).dropFirst() // 去掉 #

        var r: Double = 0, g: Double = 0, b: Double = 0, a: Double = 1

        switch hex.count {
        case 3: // #RGB
            r = hexVal(hex, offset: 0, length: 1) / 15.0
            g = hexVal(hex, offset: 1, length: 1) / 15.0
            b = hexVal(hex, offset: 2, length: 1) / 15.0
        case 4: // #RGBA
            r = hexVal(hex, offset: 0, length: 1) / 15.0
            g = hexVal(hex, offset: 1, length: 1) / 15.0
            b = hexVal(hex, offset: 2, length: 1) / 15.0
            a = hexVal(hex, offset: 3, length: 1) / 15.0
        case 6: // #RRGGBB
            r = hexVal(hex, offset: 0, length: 2) / 255.0
            g = hexVal(hex, offset: 2, length: 2) / 255.0
            b = hexVal(hex, offset: 4, length: 2) / 255.0
        case 8: // #RRGGBBAA
            r = hexVal(hex, offset: 0, length: 2) / 255.0
            g = hexVal(hex, offset: 2, length: 2) / 255.0
            b = hexVal(hex, offset: 4, length: 2) / 255.0
            a = hexVal(hex, offset: 6, length: 2) / 255.0
        default:
            return nil
        }

        return .color(red: r, green: g, blue: b, alpha: a)
    }

    private static func hexVal(_ hex: Substring, offset: Int, length: Int) -> Double {
        let start = hex.index(hex.startIndex, offsetBy: offset)
        let end = hex.index(start, offsetBy: length)
        let slice = String(hex[start..<end])
        return Double(UInt64(slice, radix: 16) ?? 0)
    }

    private static func parseRGBColor(_ text: String) -> SmartContentType? {
        // rgb(255, 87, 51) 或 rgba(255, 87, 51, 0.8)
        let pattern = #"^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*(?:,\s*([\d.]+)\s*)?\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 4
        else { return nil }

        func intGroup(_ i: Int) -> Int? {
            guard let range = Range(match.range(at: i), in: text) else { return nil }
            return Int(text[range])
        }

        guard let rv = intGroup(1), let gv = intGroup(2), let bv = intGroup(3),
              (0...255).contains(rv), (0...255).contains(gv), (0...255).contains(bv)
        else { return nil }

        var a = 1.0
        if match.numberOfRanges >= 5, let range = Range(match.range(at: 4), in: text),
           let av = Double(text[range])
        {
            a = min(max(av, 0), 1)
        }

        return .color(red: Double(rv) / 255.0, green: Double(gv) / 255.0, blue: Double(bv) / 255.0, alpha: a)
    }

    private static func parseHSLColor(_ text: String) -> SmartContentType? {
        // hsl(120, 100%, 50%) 或 hsla(120, 100%, 50%, 0.5)
        let pattern = #"^hsla?\(\s*(\d{1,3})\s*,\s*(\d{1,3})%\s*,\s*(\d{1,3})%\s*(?:,\s*([\d.]+)\s*)?\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 4
        else { return nil }

        func intGroup(_ i: Int) -> Int? {
            guard let range = Range(match.range(at: i), in: text) else { return nil }
            return Int(text[range])
        }

        guard let h = intGroup(1), let s = intGroup(2), let l = intGroup(3),
              (0...360).contains(h), (0...100).contains(s), (0...100).contains(l)
        else { return nil }

        var a = 1.0
        if match.numberOfRanges >= 5, let range = Range(match.range(at: 4), in: text),
           let av = Double(text[range])
        {
            a = min(max(av, 0), 1)
        }

        // HSL → RGB 转换
        let (r, g, b) = hslToRGB(h: Double(h), s: Double(s) / 100.0, l: Double(l) / 100.0)
        return .color(red: r, green: g, blue: b, alpha: a)
    }

    /// HSL → RGB（h: 0~360, s/l: 0~1）
    private static func hslToRGB(h: Double, s: Double, l: Double) -> (Double, Double, Double) {
        if s == 0 {
            return (l, l, l)
        }

        let c = (1 - abs(2 * l - 1)) * s
        let hPrime = h / 60.0
        let x = c * (1 - abs(hPrime.truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2

        let (r1, g1, b1): (Double, Double, Double)
        switch hPrime {
        case 0..<1: (r1, g1, b1) = (c, x, 0)
        case 1..<2: (r1, g1, b1) = (x, c, 0)
        case 2..<3: (r1, g1, b1) = (0, c, x)
        case 3..<4: (r1, g1, b1) = (0, x, c)
        case 4..<5: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }

        return (r1 + m, g1 + m, b1 + m)
    }

    // MARK: - 电话号码检测

    private static func detectPhoneNumber(_ text: String) -> Bool {
        // 限制长度，避免长文误匹配
        guard text.count <= 30 else { return false }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, range: range)

        // 整段文本必须被识别为电话号码
        guard matches.count == 1, let match = matches.first else { return false }
        return match.range.location == 0 && match.range.length == range.length
    }

    // MARK: - 邮箱检测

    private static func detectEmail(_ text: String) -> Bool {
        guard text.count <= 320 else { return false } // RFC 规定邮箱最长 320 字符

        let pattern = #"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}
