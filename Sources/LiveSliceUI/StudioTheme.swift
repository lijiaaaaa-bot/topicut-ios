// Why: one palette and a handful of motion primitives (glow backdrop, ring, primary button) so
// every screen moves and looks the same way. Colours are constants, not a theming system; the
// animations are short spring curves applied to real state, never decorative fakes of progress.

import SwiftUI

enum StudioTheme {
    static let background = Color(red: 0.035, green: 0.045, blue: 0.075)
    static let surface = Color(red: 0.075, green: 0.09, blue: 0.135)
    static let raised = Color(red: 0.105, green: 0.12, blue: 0.17)
    /// Primary action colour: a cool blue, deliberately not amber/yellow.
    static let accent = Color(red: 0.29, green: 0.56, blue: 1)
    static let cyan = Color(red: 0.35, green: 0.78, blue: 0.95)
    static let violet = Color(red: 0.56, green: 0.42, blue: 1)
    static let success = Color(red: 0.25, green: 0.82, blue: 0.54)
    static let muted = Color.white.opacity(0.62)

    static let accentGradient = LinearGradient(
        colors: [cyan, accent, violet], startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// The one spring used for layout and state changes across the app.
    static let motion: Animation = .spring(response: 0.42, dampingFraction: 0.86)
}

struct StudioCard: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            }
    }
}

extension View {
    func studioCard(padding: CGFloat = 18) -> some View {
        modifier(StudioCard(padding: padding))
    }

    /// Transparent, title-less navigation bar on iOS; the macOS build has no such bar to style.
    @ViewBuilder
    func studioBar() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline).toolbarBackground(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    /// Full-screen on iPhone; sheet on macOS (where `fullScreenCover` is unavailable).
    @ViewBuilder
    func studioCover<Content: View>(
        isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented, content: content)
        #else
        self.sheet(isPresented: isPresented, content: content)
        #endif
    }

    /// Plain text entry for identifiers (URLs, model names): no autocorrect, no capitalisation.
    @ViewBuilder
    func identifierField() -> some View {
        #if os(iOS)
        self.autocorrectionDisabled().textInputAutocapitalization(.never)
        #else
        self.autocorrectionDisabled()
        #endif
    }
}

/// Two slowly drifting colour blobs behind the idle and processing screens. `intensity` lets the
/// processing screen breathe a little brighter than the idle one.
struct GlowBackdrop: View {
    var intensity: Double = 1

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    Circle()
                        .fill(StudioTheme.accent.opacity(0.42 * intensity))
                        .frame(width: size.width * 0.9)
                        .blur(radius: 90)
                        .offset(x: sin(t / 7) * size.width * 0.18, y: -size.height * 0.22 + cos(t / 9) * 40)
                    Circle()
                        .fill(StudioTheme.violet.opacity(0.32 * intensity))
                        .frame(width: size.width * 0.8)
                        .blur(radius: 100)
                        .offset(x: cos(t / 8) * size.width * 0.2, y: size.height * 0.28 + sin(t / 6) * 36)
                }
                .frame(width: size.width, height: size.height)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

/// A gradient progress ring. `value == nil` spins (work without a fraction, e.g. the LLM call).
struct StudioRing: View {
    let value: Double?
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
            if let value {
                arc(trim: max(0.015, min(1, value)))
                    .rotationEffect(.degrees(-90))
                    .animation(StudioTheme.motion, value: value)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 60)) { context in
                    arc(trim: 0.28)
                        .rotationEffect(.degrees((context.date.timeIntervalSinceReferenceDate * 220).truncatingRemainder(dividingBy: 360)))
                }
            }
        }
    }

    private func arc(trim: Double) -> some View {
        Circle()
            .trim(from: 0, to: trim)
            .stroke(StudioTheme.accentGradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .shadow(color: StudioTheme.accent.opacity(0.45), radius: 12)
    }
}

/// Gradient capsule for the one primary action on a screen; scales on press.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: LinearGradient = StudioTheme.accentGradient

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(tint, in: Capsule())
            .shadow(color: StudioTheme.accent.opacity(configuration.isPressed ? 0.15 : 0.35), radius: 18, y: 8)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Full-width green save bar matching the workbench mock (photo + 保存到相册).
struct SaveBarButtonStyle: ButtonStyle {
    var tint: Color = StudioTheme.success

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(tint, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Zoom-morph id from the workbench preview into the EDL edit sheet.
enum WorkbenchMorph {
    static let edit = "clip-edit"
}

/// Circular Liquid Glass glyph used by the workbench trailing toolbar.
struct GlassToolbarIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .contentShape(Circle())
            .workbenchGlassCircle()
    }
}

extension View {
    /// Cool-blue refractive circle via system glass (`glassEffect`).
    @ViewBuilder
    func workbenchGlassCircle() -> some View {
        self.glassEffect(
            .regular.interactive().tint(StudioTheme.accent.opacity(0.38)),
            in: Circle()
        )
        .overlay {
            Circle().strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.58),
                        StudioTheme.accent.opacity(0.45),
                        Color.white.opacity(0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.8
            )
        }
    }

    func workbenchGlassCapsule() -> some View {
        self.glassEffect(.regular.interactive(), in: Capsule())
    }

    @ViewBuilder
    func workbenchEditMorph(namespace: Namespace.ID) -> some View {
        #if os(iOS)
        self.navigationTransition(.zoom(sourceID: WorkbenchMorph.edit, in: namespace))
        #else
        self
        #endif
    }

    @ViewBuilder
    func workbenchEditSource(namespace: Namespace.ID) -> some View {
        #if os(iOS)
        self.matchedTransitionSource(id: WorkbenchMorph.edit, in: namespace)
        #else
        self
        #endif
    }
}

extension ToolbarContent {
    /// Own glass circle so the look button is not a shared toolbar pill.
    func workbenchSeparateGlassItem() -> some ToolbarContent {
        #if os(iOS)
        self.sharedBackgroundVisibility(.hidden)
        #else
        self
        #endif
    }
}

/// Quiet secondary action (text only).
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(StudioTheme.muted)
            .padding(.vertical, 10)
            .padding(.horizontal, 18)
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}
