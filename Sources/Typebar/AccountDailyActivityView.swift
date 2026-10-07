import Charts
import SwiftUI

struct AccountDailyActivityView: View {
  let activity: AccountDailyActivity
  @Binding var selectedDate: Date?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("每日练习 · 当前本地时区").font(.headline)
      HStack(spacing: 16) {
        Label("练习分钟（左轴）", systemImage: "chart.bar.fill").foregroundStyle(Color.accentColor)
        Label("平均速度（右轴）", systemImage: "point.topleft.down.to.point.bottomright.curvepath").foregroundStyle(.orange)
        Text("虚线：分钟趋势").foregroundStyle(.secondary)
      }.font(.caption)
      chart
      Text("按真实日期间距拟合，分钟轴始终从零开始。未知时长 \(activity.unknownMinuteDays) 天不绘制柱或参与趋势，已知速度仍显示；空日期不补零。点按或拖动查看当天统计。")
        .font(.caption).foregroundStyle(.secondary)
      if let selectedDate, let day = activity.nearest(to: selectedDate) {
        let stats = day.statistics
        VStack(alignment: .leading, spacing: 4) {
          Text(day.day.formatted(date: .abbreviated, time: .omitted)).fontWeight(.medium)
          Text("完成 \(stats.completed) · 练习 \(text(stats.timeTyping, decimals: false)) 秒 · 每条重启 \(text(stats.restartsPerCompleted))")
          Text("最高 \(speed(stats.maximumWpm)) · 平均 \(speed(stats.averageWpm)) \(activity.scale.unit.displayName) · 准确率 \(text(stats.averageAccuracy))% · 一致性 \(text(stats.averageConsistency))%")
          Button("清除日期选择") { self.selectedDate = nil }
        }.font(.caption).monospacedDigit().accessibilityElement(children: .contain)
      }
    }
    .onChange(of: activity.days.map(\.day)) { selectedDate = nil }
  }

  private var chart: some View {
    Chart {
      ForEach(activity.days) { day in
        if let seconds = day.statistics.timeTyping {
          BarMark(x: .value("日期", day.day), y: .value("练习分钟", seconds / 60))
            .foregroundStyle(Color.accentColor.opacity(0.65))
            .accessibilityLabel(day.day.formatted(date: .abbreviated, time: .omitted))
            .accessibilityValue("练习 \(text(seconds / 60)) 分钟")
        }
      }
      ForEach(activity.speeds) { point in
        LineMark(x: .value("日期", point.day), y: .value("平均速度位置", activity.scale.ordinate(wpm: point.wpm)),
          series: .value("曲线", "speed-\(point.segment)")).foregroundStyle(.orange)
        PointMark(x: .value("日期", point.day), y: .value("平均速度位置", activity.scale.ordinate(wpm: point.wpm)))
          .foregroundStyle(.orange)
          .accessibilityLabel(point.day.formatted(date: .abbreviated, time: .omitted))
          .accessibilityValue("平均 \(speed(point.wpm)) \(activity.scale.unit.displayName)")
      }
      ForEach(activity.trend) { point in
        LineMark(x: .value("日期", point.day), y: .value("分钟趋势", point.minutes), series: .value("曲线", "minutes"))
          .foregroundStyle(.secondary).lineStyle(.init(lineWidth: 2, dash: [2, 3]))
          .accessibilityLabel("练习分钟趋势").accessibilityValue("\(text(point.minutes)) 分钟")
      }
      if let selectedDate, let day = activity.nearest(to: selectedDate) {
        RuleMark(x: .value("所选日期", day.day)).foregroundStyle(.secondary.opacity(0.6))
      }
    }
    .chartXScale(domain: activity.dateDomain)
    .chartXScale(range: .plotDimension(startPadding: 12, endPadding: 12))
    .chartYScale(domain: 0...activity.scale.minutesUpper)
    .chartYAxis {
      AxisMarks(position: .leading, values: activity.scale.ticks) { value in
        AxisGridLine(); AxisTick(); AxisValueLabel()
      }
      AxisMarks(position: .trailing, values: activity.scale.ticks) { value in
        AxisTick()
        AxisValueLabel {
          if let y = value.as(Double.self) { Text(text(activity.scale.speed(at: y))) }
        }
      }
    }
    .chartYAxisLabel("左：练习分钟 · 右：平均 \(activity.scale.unit.displayName)")
    .chartXSelection(value: $selectedDate)
    .chartPlotStyle { $0.clipped() }
    .chartLegend(.hidden)
    .frame(height: 220)
    .accessibilityLabel("每日练习分钟、平均速度与分钟趋势；拖动选择日期")
  }

  private func text(_ value: Double?, decimals: Bool = true) -> String {
    AccountHistoryNumberPresentation.text(value, decimals: decimals)
  }
  private func speed(_ value: Double?) -> String {
    AccountHistoryNumberPresentation.text(value, unit: activity.scale.unit, decimals: true)
  }
}
