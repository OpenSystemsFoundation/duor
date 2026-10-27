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

    @Test func mouseIsThereFirstAndTheCatSneaksUpBehindIt() throws {
        let first = try #require(CatStory.mouse(at: 0))
        #expect(first.across < 0)
        #expect(CatStory.pounce(at: 0) == nil)
        for t in times(to: CatStory.firstPounce.lowerBound - 0.01) {
            guard let cat = CatStory.pounce(at: t), let mouse = CatStory.mouse(at: t) else { continue }
            #expect(cat.across < mouse.across - 0.15)
            #expect(!mouse.facesBack)
        }
        let beforeLeap = times(to: CatStory.firstPounce.lowerBound - 0.01).compactMap { CatStory.pounce(at: $0) }
        #expect(beforeLeap.contains { $0.pose == .stalk })
        #expect(beforeLeap.contains { $0.pose == .wiggle })
        #expect(!beforeLeap.contains { $0.pose == .leap })
    }

    @Test func mouseJumpsAndDodgesTheFirstPounce() throws {
        let start = try #require(CatStory.mouse(at: CatStory.firstPounce.lowerBound))
        let jumped = times(to: CatStory.firstPounce.upperBound).filter {
            $0 > CatStory.firstPounce.lowerBound && (CatStory.mouse(at: $0)?.lift ?? 0) > 0.5
        }
        #expect(!jumped.isEmpty)
        let cat = try #require(CatStory.pounce(at: CatStory.firstPounce.upperBound))
        let mouse = try #require(CatStory.mouse(at: CatStory.firstPounce.upperBound))
        // The cat lands right where the mouse was; the mouse is well ahead by then.
        #expect(abs(cat.across - start.across) < 0.01)
        #expect(mouse.across > cat.across + 0.2)
    }

    @Test func mouseTauntsTheCatBetweenPounces() {
        let between = stride(from: CatStory.firstPounce.upperBound, to: CatStory.secondPounce.lowerBound, by: 0.05)
        let taunting = between.compactMap { CatStory.mouse(at: $0) }.filter { $0.facesBack && $0.lift > 0.1 }
        #expect(!taunting.isEmpty)
    }

    @Test func mouseRunsUnderTheSecondLeap() throws {
        let middle = (CatStory.secondPounce.lowerBound + CatStory.secondPounce.upperBound) / 2
        let cat = try #require(CatStory.pounce(at: middle))
        let mouse = try #require(CatStory.mouse(at: middle))
        #expect(cat.pose == .leap)
        #expect(cat.lift > 0.8)
        #expect(abs(cat.across - mouse.across) < 0.1)
        let landed = try #require(CatStory.pounce(at: CatStory.secondPounce.upperBound))
        let fled = try #require(CatStory.mouse(at: CatStory.secondPounce.upperBound))
        #expect(fled.across < landed.across - 0.2)
        #expect(fled.running && fled.facesBack)
    }

    @Test func catWatchesTheMouseGetAway() {
        let watching = times(to: CatStory.pounceDuration).filter {
            CatStory.mouse(at: $0) != nil && CatStory.pounce(at: $0)?.looksBack == true
        }
        #expect(!watching.isEmpty)
    }

    @Test func mouseRunsRightOffTheScreen() throws {
        let frames = times(to: CatStory.pounceDuration).compactMap { CatStory.mouse(at: $0) }
        let last = try #require(frames.last)
        #expect(last.across < 0)
    }

    @Test func pounceIsOverByTheEndOfTheVisit() {
        #expect(CatStory.pounce(at: CatStory.pounceDuration) == nil)
        #expect(CatStory.mouse(at: CatStory.pounceDuration) == nil)
    }
}
