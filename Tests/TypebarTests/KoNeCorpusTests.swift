import XCTest
@testable import Typebar

final class KoNeCorpusTests: XCTestCase {
  // Reference facts below are character sets/counts only, never reference words.
  private let koreanLegacy = ["아침", "창문", "종이", "해변", "바람", "연습", "집중", "천천히", "분명히", "호수", "거리", "책상", "빛", "여행", "인내", "잠시", "도시", "비", "고요", "방향", "별빛", "쪽지", "정원", "호흡"]
  private let nepaliLegacy = ["किताब", "कलम", "झ्याल", "बाटो", "उज्यालो", "पुल", "बिहान", "कागज", "बगैँचा", "बादल", "शान्ति", "दियो", "पहाड", "बीउ", "सङ्गीत", "टेबल", "विचार", "टिपोट", "कल्पना", "प्रयास", "दूरी", "कदम", "धैर्य", "सन्तुलन"]
  private let references: [(TypingLanguage, Int, Int, Int, String, Int)] = [
    (.korean, 470, 1, 5, "가각간갑갖같개거건걸것격결경계고곧곳공과관광교구국굴그근글금기길깊께꼭꽃꾸끝끼낌나날남낳내냥너넘넣네녀년노놀높놓누눈느는늘능니님다단답당대더데도돈돌동두뒤든듣들듯등디따땅때떠떤떨떻또뜻라람랑래램러런럼렇려력련렵령로론롭료루르른름리림마만많말맛맞매머먹먼명몇모목몸못무문묻물뭐미민믿및바밖받발밝밤밥방배버번법변보부분불비빠뿐사산살삶상새생서선성세센소속손수술쉽슨슴습시식신실심싶쓰씨아안앉않알앞애야양얘어언얻얼엄업없엇여역연열영옆예오올왜요용우욱운움웃원위유육으을음의이인일읽입있자작잘잡장재저적전점정제조족좀좋주죽줄중즉즘지직집짓쪽차찾채책처체최치친침커컴크큼키타태터통트특퍼편표품퓨프피필하학한할함행향혀현형혼화환활황회획후흐히힘", 0),
    (.korean1k, 975, 1, 5, "가각간갈감값강갖같개거걱건걷걸검겁것게겨격겪견결경곁계고골곱곳공과관괜교구국군권귀규균그극근글금급기길까깝깨꺼껴꼴꾸꿈뀌끌끓끔끗끝끼나난날남낮내냄냐너널넓넘네녀녁년념노논놀놈농높놓누눈눕뉴느늘능늦니님다닥닦단닫달닭담답당닿대더던데도독돌돕동되두둘둠둡드득든들듯등디따딸땀때떠떡떨떼똑뜨뜻라락람랑랗래랜램랫러런럽렇레려력련렵례로록론롭롯료루룹류륭르른름릇리린림마막만많말맑맙맛망맞맡매머멀멈며면명모목못무문물므미민밀밑바박반받발밝방밭배버번벌범법벗벽변별볍병보복본봄부분불붙브비빌빛빠빨빼뽑뿌쁘사산살삼상새색생서석선설섭성세센셈소속손송수순술숨숲쉬스슷시식신싣실싫심십싸쌀쌓써썰쓰씀씨씬씻아악안알앙앞야약양얗얘어억언얼엄업없에여역연열염영예옛오온올옮옳옷완왕왜외요용우운울움웃원월웨위유육으은을음응의이익인일잃임입잇있잊자작잔잘잠잡장재쟁저적전절젊점접정젖제져조족존종죄주죽준줄중쥐즈즐증지직진질집짓징짜짧째쨌쩌쪽찌찍차착찬찮찰참찾책챙처척천철첫청체쳐초촌최추축출춤충취층치칙칠침커코크큼키타탓탕태택터텔톤통투트특틀티팀파판팔펴편평포폭표푸풀품프피픽하학한할함합항해행향허험혀현형호혹혼화확환회효후훈훌훨흐흔흘희히", 0),
    (.korean5k, 4201, 1, 6, "가각간갇갈감갑값갓강갖같갚갛개객걀거걱건걷걸검겁것겉게겨격견결겹경계고곡곤곧골곰곱곳공과관광괜괴굉교구국군굳굵굶굽궁권귀귓규균그극근글긁금급긋긍기긴길김깅깊까깎깐깔깜깝깡깥깨꺼꺾껍껏껑께꼬꼭꼼꼽꽂꽃꽉꽤꾸꾼꿀꿈끄끈끊끌끓끔끗끝끼나낙낚난날낡남납낫낭낮낯낱내냄냇냉냐냥너넉넌널넓넘넣네넥넷녀녁년념녕노녹논놀놈농높놓놔뇌뇨누눈뉘뉴늄느늑늘늙능늦늬니닐님다닥단닫달닭닮담답닷당대댁댐댓더덕덜덟덤덥덧덩덮데델도독돈돌돗동돼되된두둑둘둥뒤뒷드득든듣들듬듭듯등디딩딪따딱딴딸땅때땜떠떡떨떼또똑뚜뚫뚱뛰뜨뜩뜯뜰뜻띄라락란람랍랑랗래랜램랫략량러럭런럴럼럽럿렁렇레렉렌려력련렬렵령례로록론롬롭롯료루룩룻뤄류륙률르른름릇릎리릭린림립릿링마막만많말맘맛망맞맡맣매맥맨맵맺머먹먼멀멋멍멎메멘멩며면멸명몇모목몬몰몸몹못몽묘무묵묶문묻물뭄뭇뭘뭣미민믿밀밉밌밑바박밖반받발밝밟밤밥방밭배백뱀뱃뱉버번벌범법벗베벤벨벼벽변별병볕보복볶본볼봇봉뵈뵙부북분불붉붐붓붕붙뷰브븐블비빌빔빗빚빛빠빡빨빵빼뺏뺨뻐뻔뻗뼈뼉뽑뿌쁘쁨사삭산살삶삼삿상새색샌생샤서석섞선설섬섭섯성세섹센셋셔션소속손솔솜솟송솥쇄쇠쇼수숙순숟술숨숫숭쉬쉰쉽슈스슬슴습승시식신실싫심십싯싱싶싸싹싼쌍썩썰썹쎄쏘쏟쑤쓰쓴쓸씌씨씩씹씻아악안앉않알앓암압앗앞애액앨야약얀얄얇양얕얘어억언얹얻얼엄업없엇엉엊엌엎에엔엘여역연열엷염엽엿영옆예옛오옥온올옷옹와완왕왠외왼요욕용우욱운울움웃웅워원월웨웬위윗유육율으윽은을음응의이익인일읽잃임입잇있잊잎자작잔잖잘잠잡잣장잦재쟁저적전절젊점접젓정젖제젠젯져조족존졸좁종좋좌죄주죽준줄줌줍중쥐즈즉즌즐증지직진질짐집짓징짙짚짜짝짧째쩌쩍쩐쩔쩜쪽쫓쭈쭉찌찍찢차착찬찮찰참찻창찾채책챔처척천철첩첫청체쳐초촉촌촛총촬최추축춘출춤춥춧충취츠측츰층치칙친칠침칫칭카칸칼캄캐캠커컨컬컴컵컷케켓켜코콘콜콤콩쾌쿠퀴크큰클키킬타탁탄탈탑탕태택탤터턱턴털텅테텍텔템토톤톨톱통퇴투툴툼퉁튀튜트특튼튿틀틈티틱팅파팎판팔팝패팩팬퍼퍽페펜펴편펼평폐포폭폰표푸푹풀품풍프플픔피픽필핏핑하학한할함합항해핵핸햄햇행향허헌험헤헬혀현혈협형혜호혹혼홀홈홉홍화확환활황회획횟횡효후훈훔휘휴흉흐흑흔흘흙흡흥흩희흰히힘", 0),
    (.nepali, 200, 1, 10, "ँंअआइईउएओकखगघचछजझटठडढणतथदधनपफबभमयरलवशषसहािीुूृेैोौ्", 182),
    (.nepali1k, 1000, 1, 11, "ँंअआइईउऊएऐओऔकखगघङचछजझञटठडढणतथदधनपफबभमयरलवशषसहािीुूृेैोौ्", 927),
  ]
  private func isMark(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.properties.generalCategory {
    case .nonspacingMark, .spacingMark, .enclosingMark: true
    default: false
    }
  }

  func testFivePoolsUseLiteralWordsAndKeepEveryRequiredKeyAndOldStarter() {
    for (language, count, minimum, maximum, keys, marks) in references {
      let words = language.ownedPracticeLexicon()
      let legacy = language == .nepali || language == .nepali1k ? nepaliLegacy : koreanLegacy
      XCTAssertEqual(words.count, count, language.rawValue)
      XCTAssertEqual(Set(words).count, count)
      XCTAssertEqual(words.map(\.utf16.count).min(), minimum)
      XCTAssertEqual(words.map(\.utf16.count).max(), maximum)
      XCTAssertEqual(Set(words.joined().unicodeScalars), Set((keys + legacy.joined()).unicodeScalars))
      XCTAssertTrue(Set(legacy).isSubset(of: Set(words)))
      XCTAssertEqual(words.filter { $0.unicodeScalars.contains(where: isMark) }.count, marks)
      if language == .nepali || language == .nepali1k {
        XCTAssertEqual(words.map(\.count).min(), 1)
        XCTAssertEqual(words.map(\.count).max(), language == .nepali ? 5 : 6)
      }
      XCTAssertTrue(words.allSatisfy { $0 == $0.precomposedStringWithCanonicalMapping && !$0.contains(where: \.isWhitespace) })
      XCTAssertTrue(words.allSatisfy { $0.unicodeScalars.contains { $0.properties.isAlphabetic && !isMark($0) } })
      XCTAssertFalse(words.contains { $0.contains("힣") || $0.contains("훠") || $0.contains("काकाकाकाककक") })
    }
  }

  func testShortestAndLongestTargetsKeepRawUnitsInInputResultAndRepeat() throws {
    for (language, _, _, _, _, _) in references {
      let words = language.ownedPracticeLexicon().sorted { $0.utf16.count < $1.utf16.count }
      for target in [try XCTUnwrap(words.first), try XCTUnwrap(words.last)] {
        let entries = language.ownedPracticeLexicon(), index = try XCTUnwrap(entries.firstIndex(of: target))
        var session = TestSessionFactory.make(configuration: .words(1, language: language), nextRandomWordIndex: { index })
        XCTAssertEqual(Array(session.prompt.utf16), Array(target.utf16))
        session.insertBatch(target, at: Date(timeIntervalSinceReferenceDate: 925_400_000))
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.errors, 0)
        let result = try XCTUnwrap(session.result())
        XCTAssertEqual(Array(result.prompt.utf16), Array(target.utf16))
        XCTAssertEqual(try JSONDecoder().decode(CompletedTestResult.self, from: JSONEncoder().encode(result)), result)
        XCTAssertEqual(Array(session.repeatedAttempt().prompt.utf16), Array(target.utf16))
      }
    }
  }

  func testMarkedNepaliTargetsRetainPrebaseVowelsAndConjunctUnits() throws {
    for language in [TypingLanguage.nepali, .nepali1k] {
      let words = language.ownedPracticeLexicon()
      for scalar in ["ि", "्"] {
        let target = try XCTUnwrap(words.first { $0.unicodeScalars.contains { String($0) == scalar } }, "\(language.rawValue): missing scalar \(scalar)")
        let index = try XCTUnwrap(words.firstIndex(of: target))
        var session = TestSessionFactory.make(configuration: .words(1, language: language), nextRandomWordIndex: { index })
        XCTAssertEqual(Array(session.prompt.utf16), Array(target.utf16))
        session.insertBatch(target, at: Date(timeIntervalSinceReferenceDate: 925_400_000))
        XCTAssertEqual(session.outcome, .completed)
        XCTAssertEqual(session.errors, 0)
        XCTAssertEqual(Array(try XCTUnwrap(session.result()).prompt.utf16), Array(target.utf16))
      }
    }
  }

  func testOldSyntheticTargetsStayLiteralInStoredResultsAndReplay() throws {
    for (language, target) in [(TypingLanguage.korean1k, "쟈빛가"), (.nepali1k, "टञता")] {
      var session = TypingSession(configuration: .words(1, language: language), prompt: target, sourceFields: [target])
      session.insertBatch(target, at: Date(timeIntervalSinceReferenceDate: 925_400_000))
      let result = try XCTUnwrap(session.result())
      XCTAssertEqual(result.prompt, target)
      XCTAssertEqual(session.repeatedAttempt().prompt, target)
      XCTAssertEqual(TypingReplay.typedText(events: result.replayEvents, through: result.elapsedDuration), target)
    }
  }

  func testPinnedSourcesAndFullNativeLicenseChoicesAreReadable() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", root.appendingPathComponent("Scripts/prepare-ko-ne-corpora.py").path, "--check-bundled"]
    try process.run(); process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    for notice in [CorpusLicenseNotice.korean, .nepali] {
      let text = try XCTUnwrap(notice.read(resourceDirectory: root.appendingPathComponent("Resources")))
      for credit in ["English Wiktionary contributors", "Tatoeba", "CC BY-SA 4.0", "CC BY 2.0 France"] {
        XCTAssertTrue(text.contains(credit), credit)
      }
    }
    let korean = try XCTUnwrap(CorpusLicenseNotice.korean.read(resourceDirectory: root.appendingPathComponent("Resources")))
    XCTAssertTrue(korean.contains("wordfreq 3.1.1"))
    XCTAssertTrue(korean.contains("small_ko.msgpack.gz"))
  }

  func testFrequencyOnlySyllableHasLiteralProvenanceAndCompletes() throws {
    // Independent wordfreq token, not a reference word value.
    let target = "안팎", words = TypingLanguage.korean5k.ownedPracticeLexicon()
    let index = try XCTUnwrap(words.firstIndex(of: target))
    var session = TestSessionFactory.make(configuration: .words(1, language: .korean5k), nextRandomWordIndex: { index })
    XCTAssertEqual(session.prompt, target)
    session.insertBatch(target, at: Date(timeIntervalSinceReferenceDate: 925_400_000))
    XCTAssertEqual(session.outcome, .completed)
    XCTAssertEqual(session.errors, 0)
    XCTAssertEqual(session.result()?.prompt, target)
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let rows = try String(contentsOf: root.appendingPathComponent("Resources/KoreanCorpusSources.txt"), encoding: .utf8)
    let row = try XCTUnwrap(rows.split(separator: "\n").first { $0.hasPrefix(target + "\t") })
    XCTAssertTrue(row.hasPrefix(target + "\twordfreq\t"))
    XCTAssertTrue(row.contains("\t544\tNFC-whole-token\t"))
  }
}
