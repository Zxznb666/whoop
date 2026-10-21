import Foundation

/// 显示用的四舍五入。绝对值不超过半个显示单位的数返回正零，避免界面出现 “-0.0 °C” 这样的负零（F6）。
public enum DisplayRounding {
    public static func value(_ value: Double, digits: Int) -> Double {
        let scale = pow(10, Double(digits))
        if abs(value) <= 0.5 / scale {
            return 0
        }
        let rounded = (value * scale).rounded() / scale
        return rounded == 0 ? 0 : rounded
    }
}
