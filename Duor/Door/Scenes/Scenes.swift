import SwiftUI

/// What you see through the doorway. Each scene paints itself into the door opening.
enum ScenePainter {
    static func paint(_ scene: InsideScene, in context: inout GraphicsContext, rect: CGRect) {
        context.drawLayer { layer in
            layer.clip(to: Path(rect))
            switch scene {
            case .livingRoom: livingRoom(in: &layer, rect: rect)
            case .greatHall: greatHall(in: &layer, rect: rect)
            case .beach: beach(in: &layer, rect: rect)
            case .forest: forest(in: &layer, rect: rect)
            case .space: space(in: &layer, rect: rect)
            case .brickWall: brickWall(in: &layer, rect: rect)
            }
        }
    }
}

/// The moving parts of each scene, drawn on top of the still background every frame.
///
/// Two kinds of life:
/// - **Ambient:** always there, gently moving (a swaying lamp, rolling waves, torch flames,
///   twinkling stars).
/// - **Visitors:** someone passing by now and then (a cat, a knight, a seagull, a UFO…).
///   Visits are a pure function of time: each period gets a random start, direction and lane
///   from a seed, so nothing has to be stored and every frame is cheap to compute.
///
/// With `catLovers` on, every scene also gets a cat with a little story (see `Cats.swift`).
///
/// Each scene's file draws both its still background (`ScenePainter`) and its life. Critters and
/// cats are drawn with the origin at their feet, facing right.
enum SceneLife {
    static func paint(
        _ scene: InsideScene, in context: inout GraphicsContext, rect: CGRect, time: TimeInterval,
        catLovers: Bool = false
    ) {
        context.drawLayer { layer in
            layer.clip(to: Path(rect))
            switch scene {
            case .livingRoom: livingRoom(in: &layer, rect: rect, time: time)
            case .greatHall: greatHall(in: &layer, rect: rect, time: time, catLovers: catLovers)
            case .beach: beach(in: &layer, rect: rect, time: time, catLovers: catLovers)
            case .forest: forest(in: &layer, rect: rect, time: time, catLovers: catLovers)
            case .space: space(in: &layer, rect: rect, time: time, catLovers: catLovers)
            case .brickWall: brickWall(in: &layer, rect: rect, time: time, catLovers: catLovers)
            }
        }
    }

    struct Visit {
        /// 0 at the start of the visit, 1 at the end.
        let progress: Double
        /// 1 walking right, -1 walking left.
        let facing: CGFloat
        /// 0...1, a random lane (height) for this visit.
        let lane: CGFloat
        /// 0, 1 or 2: which version of the visit this is (e.g. near, far, or just a peek).
        let variant: Int

        /// Horizontal position, entering and leaving just outside the scene.
        func x(in rect: CGRect, margin: CGFloat) -> CGFloat {
            let travel = CGFloat(progress)
            let from = rect.minX - margin
            let to = rect.maxX + margin
            return facing > 0 ? from + (to - from) * travel : to - (to - from) * travel
        }
    }

    /// Whether a visitor is passing at `time`, and where. Each `period` holds one visit of
    /// `duration` at a random moment, in a random direction; `salt` keeps visitors independent.
    static func visit(time: TimeInterval, period: Double, duration: Double, salt: UInt32) -> Visit? {
        let cycle = (time / period).rounded(.down)
        var random = NoiseSource(seed: UInt32(truncatingIfNeeded: Int64(cycle)) &* 2_654_435_761 &+ salt &* 97)
        let start = Double(random.unit()) * (period - duration)
        let phase = time - cycle * period - start
        guard phase >= 0, phase <= duration else { return nil }
        let facing: CGFloat = random.unit() < 0.5 ? 1 : -1
        let lane = CGFloat(random.unit())
        return Visit(progress: phase / duration, facing: facing, lane: lane, variant: Int(random.nextUInt() % 3))
    }

    /// Draws a critter in its own coordinates: origin at its feet, facing right (mirrored if not).
    static func critter(
        in context: inout GraphicsContext, at point: CGPoint, facing: CGFloat, draw: (inout GraphicsContext) -> Void
    ) {
        context.drawLayer { layer in
            layer.translateBy(x: point.x, y: point.y)
            layer.scaleBy(x: facing, y: 1)
            draw(&layer)
        }
    }

    static func smooth(_ value: Double) -> Double {
        let t = min(max(value, 0), 1)
        return t * t * (3 - 2 * t)
    }
}

/// A small picture of a scene, for the settings.
struct InsideSceneArt: View {
    let scene: InsideScene

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            ScenePainter.paint(scene, in: &context, rect: rect)
            SceneLife.paint(scene, in: &context, rect: rect, time: 0)
        }
    }
}

#Preview {
    HStack {
        ForEach(InsideScene.allCases) { scene in
            InsideSceneArt(scene: scene).frame(width: 120, height: 200)
        }
    }
}
