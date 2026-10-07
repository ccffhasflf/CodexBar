// Chinese strings copied from upstream zh-Hans.lproj/Localizable.strings (MIT).
import Foundation

func L(_ key: String, _ arguments: CVarArg...) -> String {
    let translations: [String: String] = [
        "%@ %@": "%@ %@",
        "%@ · %@": "%@ · %@",
        "%d%% in deficit": "超额 %d%%",
        "%d%% in reserve": "余量 %d%%",
        "(%d%% risk)": "(%d%% 耗尽风险)",
        "1.5× headroom": "1.5 倍余量",
        "Lasts until reset": "持续到重置",
        "Monthly": "每月",
        "On pace": "节奏正常",
        "Pace: %@": "节奏：%@",
        "Pace: %@ · %@": "节奏：%@ · %@",
        "Projected empty in %@": "预计 %@ 后耗尽",
        "Projected empty now": "即将耗尽",
        "Refresh": "刷新",
        "Resets in %@": "%@后重置",
        "Resets now": "立即重置",
        "Runs out in %@": "预计 %@ 后耗尽",
        "Runs out now": "即将耗尽",
        "Session": "会话",
        "Unknown": "未知",
        "Updated %@h ago": "%@ 小时前更新",
        "Updated %@m ago": "%@ 分钟前更新",
        "Updated absolute %@": "更新于 %@",
        "Updated just now": "刚刚更新",
        "Updated relative %@": "%@已更新",
        "Usage remaining": "剩余用量",
        "Usage used": "已使用用量",
        "Weekly": "每周",
        "quota_warnings_title": "配额预警",
        "usage_percent_suffix_left": "剩余",
        "usage_percent_suffix_used": "已使用",
        "weekly_progress_work_days_title": "工作日刻度线",
        "workday_tick_appearance_hidden": "隐藏",
        "workday_tick_appearance_high_contrast": "高对比度",
        "workday_tick_appearance_subtle": "柔和",
    ]
    return String(format: translations[key] ?? key, locale: Locale(identifier: "zh-Hans"), arguments: arguments)
}
