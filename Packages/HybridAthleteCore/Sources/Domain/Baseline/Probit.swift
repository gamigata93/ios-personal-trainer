import Foundation

/// The inverse of the standard normal CDF, using Acklam's rational approximation
/// (relative error below 1.15e-9). Used to place a percentile on a bell curve.
public enum Probit {
    private static let a = [
        -3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
        1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00,
    ]
    private static let b = [
        -5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
        6.680131188771972e+01, -1.328068155288572e+01,
    ]
    private static let c = [
        -7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
        -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00,
    ]
    private static let d = [
        7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00, 3.754408661907416e+00,
    ]
    private static let lowRegion = 0.02425

    /// The z-score below which a fraction `p` of a normal population falls.
    /// Returns `nil` unless 0 < p < 1.
    public static func z(_ p: Double) -> Double? {
        guard p > 0, p < 1 else { return nil }
        if p < lowRegion {
            return tail(sqrt(-2 * log(p)))
        }
        if p > 1 - lowRegion {
            return -tail(sqrt(-2 * log(1 - p)))
        }
        let q = p - 0.5
        let r = q * q
        let numerator = (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q
        let denominator = ((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1
        return numerator / denominator
    }

    private static func tail(_ q: Double) -> Double {
        let numerator = ((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]
        let denominator = (((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1
        return numerator / denominator
    }
}
