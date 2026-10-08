import SwiftUI

enum PublicProfileLeaderboardPolicy {
  struct Card: Identifiable {
    let seconds: Int
    let position: RemotePublicProfileAllTimeLeaderboards.Position
    var id: Int { seconds }
    var rankLabel: String { position.rank.map { "第 \($0) 名" } ?? "—" }
    var standingLabel: String {
      guard let rank = position.rank else { return "—" }
      if rank == 1 { return "GOAT" }
      guard position.count > 0 else { return "—" }
      var percentage = AccountHistoryNumberPresentation.text(
        Double(rank) / Double(position.count) * 100, decimals: true)
      while percentage.last == "0" { percentage.removeLast() }
      if percentage.last == "." { percentage.removeLast() }
      return "前 \(percentage)%"
    }
  }
  static func cards(_ profile: RemotePublicProfile) -> [Card] {
    guard !profile.accountSuspended, profile.leaderboardOptedOut != true else { return [] }
    return [15, 60].compactMap { seconds in
      profile.allTimeLbs?.time[String(seconds)]?["english"].map { .init(seconds: seconds, position: $0) }
    }
  }
}

struct PublicProfileLeaderboardsView: View {
  let profile: RemotePublicProfile
  var body: some View {
    if !profile.accountSuspended {
      if profile.leaderboardOptedOut == true {
        Text("该账户已退出排行榜；其成绩不代表已通过排行榜验证。")
          .font(.caption).foregroundStyle(.secondary)
      } else {
        let cards = PublicProfileLeaderboardPolicy.cards(profile)
        if !cards.isEmpty {
          VStack(alignment: .leading, spacing: 10) {
            Text("英语全部时间排行榜").font(.headline)
            HStack(alignment: .top, spacing: 10) {
              ForEach(cards) { card in
                VStack(alignment: .leading, spacing: 5) {
                  Text("\(card.seconds) 秒").font(.caption).foregroundStyle(.secondary)
                  Text(card.rankLabel).font(.title2.monospacedDigit())
                  Text(card.standingLabel).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .combine)
              }
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
  }
}
