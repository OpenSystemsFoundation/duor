import Testing

@testable import Duor

@Suite("CatStory")
struct CatStoryTests {
    private func times(to end: Double, step: Double = 0.05) -> [Double] {
        Array(stride(from: 0, through: end, by: step))
    }

    // MARK: Beach

    @Test(arguments: [0.0, 0.5, 1.0])
    func sunbatherWalksInLiesDownAndLeaves(lane: Double) throws {
        let spot = CatStory.sunbathingSpot(lane: lane)
        let frames = times(to: CatStory.sunbatherDuration).compactMap { CatStory.sunbather(at: $0, spot: spot) }
        let first = try #require(frames.first)
        let last = try #require(frames.last)
        #expect(first.across < 0)
        #expect(last.across > 0.9)
        let lounging = frames.filter { $0.pose == .sunbathe }
        #expect(lounging.count > 150)
        #expect(lounging.allSatisfy { $0.across == spot })
    }

    @Test func sunbatherIsGoneByTheEndOfTheVisit() {
        for lane in [0.0, 1.0] {
            let spot = CatStory.sunbathingSpot(lane: lane)
            #expect(CatStory.sunbather(at: CatStory.sunbatherDuration, spot: spot) == nil)
        }
    }

    // MARK: Forest

    @Test func rabbitIsThereBeforeTheCat() throws {
        let chases = times(to: CatStory.chaseDuration).map { CatStory.chase(at: $0) }
        let firstRabbit = try #require(chases.firstIndex { $0.rabbit != nil })
        let firstCat = try #require(chases.firstIndex { $0.cat != nil })
        #expect(firstRabbit < firstCat)
    }

    @Test func catStalksSlowlyThenChases() throws {
        let cats = times(to: CatStory.chaseDuration).compactMap { CatStory.chase(at: $0).cat }
        let stalking = cats.filter { $0.pose == .stalk }.map(\.across)
        let sprinting = cats.filter { $0.pose == .sprint }.map(\.across)
        #expect(stalking.count > 40)
        #expect(sprinting.count > 10)
        let creepFrom = try #require(stalking.min())
        let creepTo = try #require(stalking.max())
        let dashFrom = try #require(sprinting.min())
        let dashTo = try #require(sprinting.max())
        let creep = creepTo - creepFrom
        let dash = dashTo - dashFrom
        // The creep covers far less ground in far more time.
        #expect(creep < dash / 2)
    }

    @Test func rabbitBoltsWhenTheCatPounces() {
        let before = CatStory.chase(at: CatStory.chasePounce - 0.1)
        let after = CatStory.chase(at: CatStory.chasePounce + 0.1)
        #expect(before.rabbitHop == 0)
        #expect(after.rabbitHop > 1)
        #expect(after.cat?.pose == .sprint)
    }

    @Test func catNeverCatchesTheRabbit() {
        for t in times(to: CatStory.chaseDuration) {
            let chase = CatStory.chase(at: t)
            if let rabbit = chase.rabbit, let cat = chase.cat {
                #expect(cat.across < rabbit - 0.2)
            }
        }
    }

    @Test func chaseIsOverByTheEndOfTheVisit() {
        let end = CatStory.chase(at: CatStory.chaseDuration)
        #expect(end.rabbit == nil)
        #expect(end.cat == nil)
    }

    // MARK: Brick wall

    @Test func catLooksAroundBeforeItLeaps() {
        let beforeTakeoff = times(to: CatStory.pounceTakeoff - 0.01).compactMap { CatStory.pounce(at: $0) }
        #expect(beforeTakeoff.contains { $0.looksBack })
        #expect(beforeTakeoff.contains { $0.pose == .wiggle })
        #expect(!beforeTakeoff.contains { $0.pose == .leap })
    }

    @Test func leapCrossesToTheOtherSide() throws {
        let takeoff = try #require(CatStory.pounce(at: CatStory.pounceTakeoff))
        let landing = try #require(CatStory.pounce(at: CatStory.pounceLanding))
        let middle = try #require(CatStory.pounce(at: (CatStory.pounceTakeoff + CatStory.pounceLanding) / 2))
        #expect(takeoff.across < 0.5)
        #expect(landing.across > 0.5)
        #expect(middle.pose == .leap)
        #expect(middle.lift > 0.5)
    }

    @Test func mouseAppearsOnlyAfterTheCatLandsAndRunsTheOtherWay() throws {
        #expect(CatStory.mouse(at: CatStory.pounceLanding) == nil)
        let start = try #require(CatStory.mouse(at: CatStory.mouseAppears))
        let later = try #require(CatStory.mouse(at: CatStory.mouseAppears + 0.5))
        #expect(start == CatStory.mouseHoles[0])
        #expect(later < start)
        // The cat jumped away from it: the mouse is behind the cat.
        let cat = try #require(CatStory.pounce(at: CatStory.mouseAppears))
        #expect(cat.across > start)
    }

    @Test func catWatchesTheMouseGetAway() {
        let watching = times(to: CatStory.pounceDuration).filter {
            CatStory.mouse(at: $0) != nil && CatStory.pounce(at: $0)?.looksBack == true
        }
        #expect(!watching.isEmpty)
    }

    @Test func pounceIsOverByTheEndOfTheVisit() {
        #expect(CatStory.pounce(at: CatStory.pounceDuration) == nil)
        #expect(CatStory.mouse(at: CatStory.pounceDuration) == nil)
    }
}
