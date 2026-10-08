import Foundation
import SwiftUI

enum PublicProfilePersonalBestPolicy {
  struct Card: Identifiable {
    let id: String
    let mode: String
    let parameter: Int
    let best: RemotePublicProfileBest?
    var title: String { "\(parameter) \(mode == "time" ? "秒" : "词")" }
  }
  struct Record: Identifiable {
    let id: Int
    let best: RemotePublicProfileBest
  }

  /// Fixed summary slots select one whole snapshot, not independent maxima.
  static func cards(_ profile: RemotePublicProfile) -> [Card] {
    [("time", [15, 30, 60, 120]), ("words", [10, 25, 50, 100])].flatMap { mode, parameters in
      parameters.map { parameter in
        let best = profile.displayPersonalBests.reduce(nil as RemotePublicProfileBest?) { selected, candidate in
          let explicit = mode == "time" ? candidate.durationSeconds : candidate.wordLimit
          guard candidate.mode == mode,
            (candidate.mode2 ?? explicit.map(String.init)) == String(parameter) else { return selected }
          return candidate.effectiveWpm > (selected?.effectiveWpm ?? 0) ? candidate : selected
        }
        return Card(id: "\(mode)/\(parameter)", mode: mode, parameter: parameter, best: best)
      }
    }
  }

  /// Full disclosure retains every saved record, including legacy duplicate IDs.
  static func records(_ profile: RemotePublicProfile) -> [Record] {
    profile.displayPersonalBests.enumerated().map { index, best in
      .init(id: index, best: best)
    }
  }
}

enum PublicProfilePersonalBestPresentation {
  static func speed(_ value: Double?, unit: TypingSpeedUnit, decimals: Bool) -> String {
    guard let value, value.isFinite else { return "—" }
    return AccountHistoryNumberPresentation.text(value, unit: unit, decimals: decimals)
  }
  static func percentage(_ value: Double?, decimals: Bool, accuracy: Bool = false) -> String {
    guard let value, value.isFinite else { return "—" }
    return AccountHistoryNumberPresentation.text(accuracy && !decimals ? floor(value) : value,
      decimals: decimals) + "%"
  }
}

struct PublicProfilePersonalBestsView: View {
  let profile: RemotePublicProfile
  let settings: AppSettings

  var body: some View {
    let cards = PublicProfilePersonalBestPolicy.cards(profile)
    VStack(alignment: .leading, spacing: 12) {
      Text("公开个人最佳").font(.headline)
      Text(AccountPersonalBestTablePolicy.coverageNotice(profile))
        .font(.caption).foregroundStyle(.secondary)
      ForEach([TestMode.time, .words], id: \.self) { mode in
        Text(mode.displayName).font(.subheadline.weight(.medium))
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
          ForEach(cards.filter { $0.mode == mode.rawValue }) { card in
            VStack(alignment: .leading, spacing: 6) {
              Text(card.title).font(.caption).foregroundStyle(.secondary)
              Text("\(PublicProfilePersonalBestPresentation.speed(card.best?.effectiveWpm, unit: settings.typingSpeedUnit, decimals: false)) \(settings.typingSpeedUnit.displayName)")
                .font(.title2.monospacedDigit())
              Text(PublicProfilePersonalBestPresentation.percentage(
                card.best.map { $0.preciseAccuracy ?? Double($0.accuracy) }, decimals: false, accuracy: true))
                .font(.subheadline.monospacedDigit())
                .accessibilityLabel("准确率 " + PublicProfilePersonalBestPresentation.percentage(
                  card.best.map { $0.preciseAccuracy ?? Double($0.accuracy) }, decimals: false, accuracy: true))
              if let best = card.best {
                DisclosureGroup("纪录详情") { PublicProfilePersonalBestDetails(best: best, settings: settings) }
                  .font(.caption)
              } else {
                Text("此档暂无正速度纪录").font(.caption2).foregroundStyle(.secondary)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
          }
        }
      }
      if !profile.displayPersonalBests.isEmpty {
        DisclosureGroup("全部公开纪录 · \(profile.displayPersonalBests.count) 条") {
          LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(PublicProfilePersonalBestPolicy.records(profile)) { record in
              VStack(alignment: .leading, spacing: 4) {
                Text(record.best.configurationLabel).font(.subheadline.weight(.medium))
                PublicProfilePersonalBestDetails(best: record.best, settings: settings)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.vertical, 4)
            }
          }
          .padding(.top, 8)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct PublicProfilePersonalBestDetails: View {
  let best: RemotePublicProfileBest
  let settings: AppSettings
  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text("速度 \(speed(best.effectiveWpm)) \(settings.typingSpeedUnit.displayName) · Raw \(speed(best.preciseRawWpm ?? best.rawWpm.map(Double.init)))")
        .monospacedDigit()
      Text("准确率 \(PublicProfilePersonalBestPresentation.percentage(best.preciseAccuracy ?? Double(best.accuracy), decimals: settings.alwaysShowDecimalPlaces, accuracy: true)) · 稳定度 \(PublicProfilePersonalBestPresentation.percentage(best.consistency, decimals: settings.alwaysShowDecimalPlaces))")
        .monospacedDigit()
      Text(best.languageLabel)
      Text(best.groupingLabel)
      Text(best.recordedAt, format: .dateTime.year().month().day().hour().minute())
      if best.personalBestOrigin == "legacyHistory" { Text("旧历史基线") }
    }
    .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
  }
  private func speed(_ value: Double?) -> String {
    PublicProfilePersonalBestPresentation.speed(value, unit: settings.typingSpeedUnit,
      decimals: settings.alwaysShowDecimalPlaces)
  }
}
