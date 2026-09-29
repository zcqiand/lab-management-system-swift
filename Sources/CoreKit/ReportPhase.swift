import Foundation
import LabSharedGenerated

// REQ-2026-006 T-1：报告四阶段描述（M03.F05~F08）。
// 四阶段与接样→任务分配→数据录入（各自已有 act 三动作）是同一流程线；
// 队列与 act 全复用既有缝（ReceiptListViewModel + ReceivingFlowViewModel），
// 本件只做「阶段 → 查询钉态 / 操作按钮文案」的映射，App 层 ReportPhaseView
// 按它参数化（镜像家族 ReportPhasePage 单组件四 wrapper）。

/// 报告四阶段。发放的报告编号由后端 act submit 语义生成（家族 ReportPhasePage
/// 注释实证「后端 act 语义已含，此处只显示」）——本枚举不发明客户端状态机。
public enum ReportPhase: String, CaseIterable {
    case review
    case approval
    case issuance
    case archived

    /// 队列查询钉死的流程态（每阶段一态，不串档）。
    public var flowStatus: FlowStatus {
        switch self {
        case .review: return .review
        case .approval: return .approval
        case .issuance: return .issuance
        case .archived: return .archived
        }
    }

    /// 阶段页标题（导航栏）。
    public var phaseTitle: String {
        switch self {
        case .review: return "报告审核"
        case .approval: return "报告批准"
        case .issuance: return "报告发放"
        case .archived: return "报告归档"
        }
    }

    /// 操作按钮文案（submit 语义；家族 submitLabel 同款）。
    public var submitLabel: String {
        switch self {
        case .review: return "审核通过"
        case .approval: return "批准"
        case .issuance: return "发放"
        case .archived: return "归档完成"
        }
    }
}
