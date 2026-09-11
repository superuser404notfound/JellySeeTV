import SwiftUI

/// Sodalite#104: what the live rail says in words, for whichever transport is on screen.
///
/// The two ends of the block, the wall clock of the frame on screen tracking the knob between them,
/// and the programme that follows. One implementation, because the first round of this issue shipped
/// with the tvOS view holding its own copy of the rail arithmetic and the copy drifted: the badge and
/// the knob ended up answering different questions about the same edge. The two transports differ in
/// type scale and in nothing else, so that is the only thing they pass in.
struct LiveRailLabels: View {
    let viewModel: PlayerViewModel
    /// `.callout` on the ten-foot bar, `.caption` on the phone, matching what each transport already
    /// gives the two slots this row replaces.
    var font: Font = .callout
    var rowHeight: CGFloat = 30

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    Text(PlayerViewModel.clockLabel(for: viewModel.liveRailBlock.start))
                    Spacer(minLength: 0)
                    Text(PlayerViewModel.clockLabel(for: viewModel.liveRailBlock.end))
                }
                .font(font)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.7))

                // Hidden rather than pushed aside near the ends: there it would say what the end label
                // beside it already says, and a clock sliding out from under its own knob reads worse
                // than one that steps aside. The margin is a share of the width, so the phone hides it
                // sooner than the television does, which is the right answer on a 350pt rail.
                if let playheadClock, !clockCollides(width: width) {
                    HStack(spacing: 8) {
                        if viewModel.seekReadout?.direction == -1 { SeekReadoutView(viewModel: viewModel) }
                        Text(playheadClock)
                            .font(font)
                            .fontWeight(.medium)
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        if viewModel.seekReadout?.direction == 1 { SeekReadoutView(viewModel: viewModel) }
                    }
                    .fixedSize()
                    .position(x: knobX(width), y: rowHeight / 2)
                }
            }
        }
        .frame(height: rowHeight)
    }

    private func knobX(_ width: CGFloat) -> CGFloat {
        max(0, min(width, width * CGFloat(viewModel.liveDisplayedProgress)))
    }

    private func clockCollides(width: CGFloat) -> Bool {
        let margin = max(60, width * 0.22)
        let x = knobX(width)
        return x < margin || x > width - margin
    }

    /// The wall clock of the frame on screen, or of the position a scrub is pointing at.
    private var playheadClock: String? {
        let block = viewModel.liveRailBlock
        guard block.seconds > 0 else { return nil }
        return PlayerViewModel.clockLabel(for: block.wallClock(at: viewModel.liveDisplayedProgress))
    }

}

/// Sodalite#104: what follows the block, under the rail that marks its end, which is the thing it
/// counts toward.
struct LiveNextUpLine: View {
    let viewModel: PlayerViewModel
    var font: Font = .callout

    var body: some View {
        if let next = viewModel.liveNextProgram, let starts = next.startDate {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(Self.text(name: next.name, startsIn: starts.timeIntervalSince(Date())))
                    .font(font)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
    }

    /// "In 101 minutes: The OT", or the name alone once the countdown would read as zero.
    static func text(name: String, startsIn seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        guard minutes >= 1 else {
            return String(format: String(localized: "livetv.nextUp.now",
                                         defaultValue: "Next: %@"), name)
        }
        let inWords = Duration.seconds(minutes * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .wide))
        return String(format: String(localized: "livetv.nextUp",
                                     defaultValue: "In %1$@: %2$@"), inWords, name)
    }
}

/// Sodalite#104: a press and a hold, in the two languages they actually speak.
///
/// A press names its interval, because the destination is known before it lands, and counts itself,
/// because a burst of four is the thing a viewer is keeping track of. A hold names its rate and
/// nothing else: a 15x to 240x scan has no countable step, so a fixed-interval glyph over it would be
/// a lie. Nothing draws here on the touch transport, where a skip commits on the tap that asked for
/// it and flashes its own HUD.
struct SeekReadoutView: View {
    let viewModel: PlayerViewModel

    var body: some View {
        switch viewModel.seekReadout {
        case .press(let seconds, let count, let direction):
            VStack(spacing: 2) {
                Image(systemName: "\(direction < 0 ? "gobackward" : "goforward").\(seconds)")
                    .font(.callout)
                if count > 1 {
                    Text(verbatim: "\(count)x")
                        .font(.caption2)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(.white)
            .transition(.opacity)
        case .hold(let rate, let direction):
            HStack(spacing: 4) {
                Image(systemName: direction < 0 ? "chevron.left.2" : "chevron.right.2")
                    .font(.callout)
                Text(verbatim: "\(rate)x")
                    .font(.caption)
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .transition(.opacity)
        case nil:
            EmptyView()
        }
    }
}
