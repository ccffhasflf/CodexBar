import Foundation

enum WorkdayTickAppearance: String, CaseIterable, Identifiable {
    case hidden
    case subtle
    case highContrast

    var id: String {
        self.rawValue
    }

    var label: String {
        switch self {
        case .hidden: L("workday_tick_appearance_hidden")
        case .subtle: L("workday_tick_appearance_subtle")
        case .highContrast: L("workday_tick_appearance_high_contrast")
        }
    }
}
