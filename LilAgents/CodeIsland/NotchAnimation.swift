import SwiftUI

enum NotchAnimation {
    /// 展开面板：微弹，有少许回弹感
    static let open = Animation.spring(response: 0.42, dampingFraction: 0.82)
    /// 普通收起：临界阻尼，无过冲（防止 NotchPanelShape 底边露出刘海）
    static let close = Animation.spring(response: 0.38, dampingFraction: 1.0)
    /// 删除最后一项后的收刘海：更柔和，更从容，避免“瞬间抽回”
    static let deleteCollapse = Animation.spring(response: 0.52, dampingFraction: 0.96, blendDuration: 0.12)
    /// Compact bar 首次出现时，从基础长度慢慢撑开到完整宽度
    static let compactReveal = Animation.spring(response: 0.58, dampingFraction: 0.9, blendDuration: 0.12)
    /// 通知弹出：快速弹跳，用于 completion/approval 自动展开
    static let pop = Animation.spring(response: 0.3, dampingFraction: 0.65)
    /// 微交互：hover 状态变化、按钮高亮等
    static let micro = Animation.easeOut(duration: 0.12)
}
