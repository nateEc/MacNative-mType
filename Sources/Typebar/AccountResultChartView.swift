import Charts
import SwiftUI

struct AccountResultChartSelection: Identifiable {
  let id: UUID
  let scope: ResultPublicationScope
}

struct AccountResultChartDetail: View {
  let selection: AccountResultChartSelection
  let account: AccountSession
  let settings: AppSettings
  @Environment(\.dismiss) private var dismiss
  @State private var loader = AccountResultChartLoader()
  @State private var retry = UUID()
  @State private var elapsed: Double?
  private var isCurrent: Bool {
    account.resultPublicationScope == selection.scope
      && account.accountHistoryLoadedResults.contains { $0.id == selection.id }
  }
  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 14) {
        Text("账户成绩 · \(selection.id.uuidString.prefix(8))").font(.caption).foregroundStyle(.secondary)
        if !isCurrent {
          ContentUnavailableView("成绩已不在当前账户缓存", systemImage:"person.crop.circle.badge.xmark")
        } else {
          switch loader.state {
          case .loading: ProgressView("正在读取这条成绩的速度图…")
          case .unavailable:
            ContentUnavailableView("没有保存的速度图",systemImage:"chart.xyaxis.line",
              description:Text("旧成绩、缺少回放或超过 122 秒的练习不补造轨迹。"))
          case .failed(let message):
            Text(message).foregroundStyle(.secondary)
            Button("重新读取") { retry = UUID() }
          case .ready(let data):
            chart(data)
            Text("仅保存的匿名数值，不含提示或输入内容；速度与 Burst 使用左轴，错误使用右轴。")
              .font(.caption).foregroundStyle(.secondary)
          }
        }
      }.padding(24).frame(minWidth:640,idealWidth:760,minHeight:340)
      .navigationTitle("账户成绩速度图")
      .toolbar { ToolbarItem(placement:.cancellationAction) { Button("完成") { dismiss() } } }
    }
    .task(id:retry) {
      elapsed = nil
      await loader.load { try await account.fetchAccountResultChart(id:selection.id,scope:selection.scope) }
    }
    .onChange(of:account.resultPublicationScope) { dismiss() }
    .onChange(of:account.accountHistoryLoadedResults.map(\.id)) { if !isCurrent { dismiss() } }
  }
  private func chart(_ data: AccountResultChartData) -> some View {
    let scale = AccountResultChartScale(data:data,unit:settings.typingSpeedUnit,startsAtZero:settings.startGraphsAtZero)
    return VStack(alignment:.leading,spacing:10) {
      HStack(spacing:18) {
        Label(settings.typingSpeedUnit.displayName,systemImage:"waveform.path").foregroundStyle(Color.accentColor)
        Label("Burst",systemImage:"bolt.fill").foregroundStyle(.secondary)
        Label("错误",systemImage:"xmark").foregroundStyle(.red)
      }.font(.caption)
      Chart {
        ForEach(data.samples) { sample in
          LineMark(x:.value("秒",sample.elapsed),y:.value("速度位置",scale.speedPosition(sample.wpm)),series:.value("曲线","speed"))
            .foregroundStyle(Color.accentColor).symbol(.circle).symbolSize(8)
            .accessibilityLabel("\(number(sample.elapsed)) 秒速度")
            .accessibilityValue("\(speed(sample.wpm)) \(settings.typingSpeedUnit.displayName)")
          LineMark(x:.value("秒",sample.elapsed),y:.value("速度位置",scale.speedPosition(sample.burst)),series:.value("曲线","burst"))
            .foregroundStyle(.secondary).lineStyle(.init(lineWidth:2,dash:[4,3])).symbol(.circle).symbolSize(8)
            .accessibilityLabel("\(number(sample.elapsed)) 秒 Burst")
            .accessibilityValue("\(speed(sample.burst)) \(settings.typingSpeedUnit.displayName)")
          if sample.errors > 0 {
            PointMark(x:.value("秒",sample.elapsed),y:.value("错误位置",scale.errorPosition(sample.errors)))
              .symbol { Image(systemName:"xmark").font(.system(size:8,weight:.bold)) }.foregroundStyle(.red)
              .accessibilityLabel("\(number(sample.elapsed)) 秒错误").accessibilityValue("\(sample.errors)")
          }
        }
        if let elapsed, let sample = data.nearest(to:elapsed) {
          RuleMark(x:.value("所选秒",sample.elapsed)).foregroundStyle(.secondary.opacity(0.4))
        }
      }
      .chartXScale(domain:0...max(1,data.samples.last?.elapsed ?? 1),range:.plotDimension(startPadding:8,endPadding:8))
      .chartYScale(domain:0...1)
      .chartYAxis {
        AxisMarks(position:.leading,values:[0.0,0.25,0.5,0.75,1]) { value in
          AxisGridLine(); AxisTick(); AxisValueLabel {
            if let y = value.as(Double.self) { Text(number(scale.speed(at:y))) }
          }
        }
        AxisMarks(position:.trailing,values:scale.errorTickPositions) { value in
          AxisTick(); AxisValueLabel {
            if let y = value.as(Double.self) { Text("\(Int(scale.errors(at:y).rounded()))") }
          }
        }
      }
      .chartXAxisLabel("秒").chartYAxisLabel("左：\(settings.typingSpeedUnit.displayName) · 右：错误")
      .chartLegend(.hidden).chartPlotStyle { $0.clipped() }
      .chartXSelection(value:$elapsed).frame(height:220)
      if let elapsed, let sample = data.nearest(to:elapsed) {
        Text("\(number(sample.elapsed)) 秒 · \(speed(sample.wpm)) \(settings.typingSpeedUnit.displayName) · Burst \(speed(sample.burst)) · 错误 \(sample.errors)")
          .font(.caption).monospacedDigit()
        Button("清除时间选择") { self.elapsed = nil }
      } else { Text("点按或拖动查看同一时间的三条指标。") .font(.caption).foregroundStyle(.secondary) }
    }
  }
  private func number(_ value: Double) -> String { AccountHistoryNumberPresentation.text(value,decimals:true) }
  private func speed(_ value: Double) -> String { AccountHistoryNumberPresentation.text(value,unit:settings.typingSpeedUnit,decimals:true) }
}
