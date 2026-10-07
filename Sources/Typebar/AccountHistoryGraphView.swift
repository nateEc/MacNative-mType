import Charts
import SwiftUI

struct AccountHistoryGraphView: View {
  let graph: AccountHistoryGraphs
  let settings: AppSettings
  let selectedID: UUID?
  let onSelect: (UUID?) -> Void
  @State private var position: Double?
  @State private var histogramLabel: String?

  private var visibility: HistoryChartVisibility { settings.historyChartVisibility }
  private var scale: AccountHistoryGraphScale {
    .init(points: graph.points, unit: settings.typingSpeedUnit,
      startsAtZero: settings.startGraphsAtZero, speedVisible: visibility.speed)
  }
  private var selected: AccountHistoryGraphPoint? {
    visibility.speed || visibility.accuracy ? position.flatMap { graph.nearest(to: $0) } : nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("成绩走势 · 整个匹配集合").font(.headline)
      HStack {
        toggle("速度", \.speed); toggle("准确率", \.accuracy)
        toggle("10 次均线", \.average10); toggle("100 次均线", \.average100)
        Spacer()
        Toggle("从零开始", isOn: Binding(get: { settings.startGraphsAtZero }, set: { settings.startGraphsAtZero = $0 }))
      }.toggleStyle(.checkbox)
      HStack {
        Picker("速度单位", selection: Binding(get: { settings.typingSpeedUnit }, set: { settings.typingSpeedUnit = $0 })) {
          ForEach(TypingSpeedUnit.allCases) { Text($0.displayName).tag($0) }
        }.frame(width: 180)
        Toggle("始终显示两位小数", isOn: Binding(get: { settings.alwaysShowDecimalPlaces }, set: { settings.alwaysShowDecimalPlaces = $0 }))
          .toggleStyle(.checkbox)
      }
      historyChart
      Text("左侧准确率轴反向；右侧为速度。均线包含尾部不足 10/100 次的样本；阶梯线仅表示筛选集合内的历史最高速度，不代表提交时 PB。未知观测不补零。")
        .font(.caption).foregroundStyle(.secondary)
      if let change = graph.speedChangePerTypingHour {
        Text("每练习小时速度变化：\(change > 0 ? "+" : "")\(text(change, speed: true)) \(settings.typingSpeedUnit.displayName)")
          .font(.caption).monospacedDigit()
      } else {
        Text("每练习小时速度变化：未知（至少两条有效速度与完整正练习时长）")
          .font(.caption).foregroundStyle(.secondary)
      }
      if let selected {
        let row = selected.row
        VStack(alignment: .leading, spacing: 4) {
          Text("\(row.finishedAt.formatted(date: .abbreviated, time: .shortened)) · \(row.mode) · \(row.mode2 ?? "未知参数") · \(row.language)")
          Text("速度 \(text(selected.speed, speed: true)) · Raw \(text(row.effectiveRawWpm, speed: true)) \(settings.typingSpeedUnit.displayName) · 准确率 \(text(selected.accuracy))% · 错误率 \(text(selected.accuracy.map { 100 - $0 }))%")
          Text("难度 \(row.personalBestConfiguration?.difficulty ?? "未知") · 标点 \(row.personalBestConfiguration.map { $0.punctuation ? "开" : "关" } ?? "未知") · 历史 PB \(row.historicalPersonalBest.map { $0 ? "是" : "否" } ?? "未知")")
          Button("清除选择") { position = nil }
        }.font(.caption).monospacedDigit().accessibilityElement(children: .contain)
      }
      histogram
    }
    .onChange(of: position) { onSelect(selected?.id) }
    .onChange(of: selectedID) { if selectedID == nil { position = nil } }
    .onChange(of: graph.points.map(\.id)) { position = nil; histogramLabel = nil; onSelect(nil) }
    .onChange(of: visibility) {
      if !visibility.speed && !visibility.accuracy { position = nil; onSelect(nil) }
    }
  }

  private var historyChart: some View {
    Chart {
      ForEach(graph.points) { point in
        if visibility.speed, let speed = point.speed {
          PointMark(x: .value("成绩序号", point.position), y: .value("速度位置", scale.speedPosition(speed)))
            .foregroundStyle(.blue).accessibilityLabel(point.row.finishedAt.formatted())
            .accessibilityValue("\(text(speed, speed: true)) \(settings.typingSpeedUnit.displayName)")
        }
        if visibility.accuracy, let accuracy = point.accuracy {
          PointMark(x: .value("成绩序号", point.position), y: .value("准确率位置", scale.accuracyPosition(accuracy)))
            .symbol(.triangle).foregroundStyle(.orange)
            .accessibilityLabel(point.row.finishedAt.formatted()).accessibilityValue("准确率 \(text(accuracy))%")
        }
      }
      if visibility.speed {
        speedLine(\.envelope, name: "包络", color: .secondary, stepped: true)
        if visibility.average10 { speedLine(\.speed10, name: "速度10", color: .blue.opacity(0.6)) }
        if visibility.average100 { speedLine(\.speed100, name: "速度100", color: .blue) }
      }
      if visibility.accuracy {
        if visibility.average10 { accuracyLine(\.accuracy10, name: "准确率10", color: .orange.opacity(0.6)) }
        if visibility.average100 { accuracyLine(\.accuracy100, name: "准确率100", color: .orange) }
      }
      if let selected, visibility.speed || visibility.accuracy {
        RuleMark(x: .value("选择", selected.position)).foregroundStyle(.secondary.opacity(0.5))
      }
    }
    .chartXScale(domain: -1...max(1, graph.points.count))
    .chartXAxis {
      AxisMarks { value in
        AxisGridLine(); AxisTick()
        AxisValueLabel {
          if let x = value.as(Int.self), graph.points.indices.contains(x) { Text("\(graph.points.count - 1 - x)") }
        }
      }
    }
    .chartYScale(domain: 0...100)
    .chartYAxis {
      AxisMarks(position: .leading, values: [0,25,50,75,100]) { value in
        AxisTick()
        AxisValueLabel { if let y = value.as(Double.self) { Text("\(text(scale.accuracy(at: y)))%") } }
      }
      AxisMarks(position: .trailing, values: [0,25,50,75,100]) { value in
        AxisGridLine(); AxisTick()
        AxisValueLabel { if let y = value.as(Double.self) { Text(AccountHistoryNumberPresentation.text(scale.speed(at: y), decimals: settings.alwaysShowDecimalPlaces)) } }
      }
    }
    .chartYAxisLabel("准确率 % ← · → \(settings.typingSpeedUnit.displayName)")
    .chartXAxisLabel("较早 ← 成绩序号 → 较新 · 0 为最新（与列表排序独立）")
    .chartXSelection(value: $position)
    .chartLegend(.hidden)
    .frame(height: 260)
    .accessibilityLabel("账户成绩走势；点按或拖动选择成绩并定位列表")
  }

  @ChartContentBuilder private func speedLine(_ key: KeyPath<AccountHistoryGraphPoint, Double?>,
    name: String, color: Color, stepped: Bool = false) -> some ChartContent {
    ForEach(graph.line(key)) { point in
      LineMark(x: .value("成绩序号", point.position), y: .value("速度位置", scale.speedPosition(point.value)),
        series: .value("曲线", "\(name)-\(point.segment)"))
        .foregroundStyle(color).interpolationMethod(stepped ? .stepEnd : .linear)
    }
  }
  @ChartContentBuilder private func accuracyLine(_ key: KeyPath<AccountHistoryGraphPoint, Double?>,
    name: String, color: Color) -> some ChartContent {
    ForEach(graph.line(key)) { point in
      LineMark(x: .value("成绩序号", point.position), y: .value("准确率位置", scale.accuracyPosition(point.value)),
        series: .value("曲线", "\(name)-\(point.segment)"))
        .foregroundStyle(color)
    }
  }

  private var histogram: some View {
    let data = AccountHistoryHistogram(points: graph.points, unit: settings.typingSpeedUnit)
    return VStack(alignment: .leading, spacing: 8) {
      Text("速度分布 · \(settings.typingSpeedUnit.displayName)").font(.headline)
      Chart(data.buckets) { bucket in
        BarMark(x: .value("原版分桶标签", bucket.label), y: .value("成绩数量", bucket.count))
          .foregroundStyle(.blue).accessibilityLabel(bucket.label).accessibilityValue("\(bucket.count) 条")
      }.chartYScale(domain: 0...max(1, data.buckets.map(\.count).max() ?? 1))
        .chartYAxisLabel("成绩数量").chartXSelection(value: $histogramLabel).frame(height: 160)
      if let bucket = data.buckets.first(where: { $0.label == histogramLabel }) {
        Text("\(bucket.label) \(settings.typingSpeedUnit.displayName)：\(bucket.count) 条").font(.caption)
      }
      Text("按原版先转换单位、整数舍入再分桶；保留其标签和未舍入最大值决定范围的规则。舍入越界未绘制 \(data.omittedByReferenceRounding) 条，速度未知 \(data.unknownCount) 条。")
        .font(.caption).foregroundStyle(.secondary)
    }
  }

  private func toggle(_ label: String, _ key: WritableKeyPath<HistoryChartVisibility, Bool>) -> some View {
    Toggle(label, isOn: Binding(get: { visibility[keyPath: key] }, set: { value in
      settings.mutateHistoryChartVisibility { $0[keyPath: key] = value }
    }))
  }
  private func text(_ value: Double?, speed: Bool = false) -> String {
    AccountHistoryNumberPresentation.text(value, unit: speed ? settings.typingSpeedUnit : nil,
      decimals: settings.alwaysShowDecimalPlaces, forceDecimals: true)
  }
}
