// SPDX-FileCopyrightText: 2026 Mattia Egloff <mattia.egloff@pm.me>
//
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreImage.CIFilterBuiltins
import SwiftUI

struct PresentationNodeView: View {
    /// Floor for a QR another device has to read off this screen. A dense
    /// multi-stage exchange payload has to survive a peer's camera at an
    /// angle, through screen glare, so this is deliberately generous: on a
    /// compact device the QR lands exactly on this floor, which makes it
    /// the real size control.
    static let minimumScannableQr: CGFloat = 260

    let node: PresentationNode
    let surfaceID: String
    let minimumTarget: CGFloat
    let useFrontCamera: Bool
    let onCameraPermissionDenied: () -> Void
    let focusedBinding: FocusState<String?>.Binding
    let onEvent: (PresentationEvent) -> Void
    /// Whether this node's field held focus at the last change. Only a
    /// field that had it can report losing it.
    @State private var hadFocus = false

    var body: some View {
        switch node {
        case let .text(value):
            Text(value.content)
                .font(textRoleStyle(for: value.style).font)
                .foregroundStyle(
                    textRoleStyle(for: value.style).muted
                        ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
                )
                .accessibilityLabel(value.accessibility.label)
        case let .input(value):
            input(value)
        case let .toggle(value):
            Toggle(
                value.label,
                isOn: Binding(
                    get: { value.value },
                    set: { changed in
                        sendValue(value.bindingID, .boolean(changed))
                    }
                )
            )
            .disabled(!value.enabled)
            .accessibilityLabel(value.accessibility.label)
        case let .choice(value):
            Picker(
                value.label,
                selection: Binding(
                    get: { value.selected },
                    set: { changed in
                        sendValue(value.bindingID, .choice(changed))
                    }
                )
            ) {
                Text("—").tag(String?.none)
                ForEach(value.options) { option in
                    Text(option.label).tag(String?.some(option.id))
                }
            }
            .disabled(!value.enabled)
            .accessibilityLabel(value.accessibility.label)
        case let .group(value):
            GroupBox(value.label ?? "") {
                if value.axis == .horizontal {
                    HStack {
                        children(value.children)
                    }
                } else {
                    VStack(alignment: .leading) {
                        children(value.children)
                    }
                }
            }
            // A label on a container that is not itself an accessibility
            // element propagates down and overwrites every child's label,
            // so each line reads back as the container's. `.contain` makes
            // this a container whose children keep their own labels and
            // stay individually reachable
            // (`2026-08-16-ios-rows-are-not-buttons`).
            .accessibilityElement(children: .contain)
            .accessibilityLabel(value.accessibility.label)
        case let .list(value):
            VStack(alignment: .leading, spacing: 8) {
                if let label = value.label {
                    Text(label).font(.headline)
                }
                ForEach(value.rows) { row in
                    PresentationRowView(
                        row: row,
                        surfaceID: surfaceID,
                        minimumTarget: minimumTarget,
                        useFrontCamera: useFrontCamera,
                        onCameraPermissionDenied: onCameraPermissionDenied,
                        focusedBinding: focusedBinding,
                        onEvent: onEvent
                    )
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(value.accessibility.label)
        case let .image(value):
            image(value)
        case let .status(value):
            status(value)
        case let .qr(value):
            qr(value)
        case let .confirmation(value):
            confirmation(value)
        case let .slider(value):
            VStack(alignment: .leading) {
                Text(value.label)
                Slider(
                    value: Binding(
                        get: { value.value },
                        set: { changed in
                            sendValue(value.bindingID, .number(changed))
                        }
                    ),
                    in: value.minimum ... value.maximum,
                    step: value.step ?? 0.001
                )
                .accessibilityLabel(value.accessibility.label)
            }
        case let .progress(value):
            VStack(alignment: .leading) {
                if let label = value.label {
                    Text(label)
                }
                if let progress = value.value {
                    ProgressView(value: progress)
                } else {
                    ProgressView()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(value.accessibility.label)
        case .divider:
            Divider()
        }
    }

    private func input(_ value: PresentationNode.Input) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if value.inputKind == .password || value.inputKind == .pin {
                SecureField(
                    value.label,
                    text: textBinding(value)
                )
                .focused(focusedBinding, equals: value.bindingID)
                .accessibilityLabel(value.accessibility.label)
            } else {
                TextField(
                    value.label,
                    text: textBinding(value),
                    prompt: value.placeholder.map(Text.init)
                )
                .textContentType(textContentType(for: value.inputKind))
                .focused(focusedBinding, equals: value.bindingID)
                .accessibilityLabel(value.accessibility.label)
            }
            if let error = value.validationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .submitLabel(.done)
        .onSubmit {
            onEvent(
                .inputSubmitted(
                    surfaceID: surfaceID,
                    bindingID: value.bindingID
                )
            )
        }
        // SwiftUI models focus as one "which binding" value, so a field
        // learns it lost focus by watching that value move off itself.
        // The deployment target is iOS 15, where `onChange` reports only
        // the new value, so the "was it us?" half is tracked here — the
        // same flag Compose needs for a different reason.
        .onChange(of: focusedBinding.wrappedValue) { current in
            if hadFocus, current != value.bindingID {
                onEvent(
                    .inputFocusEnded(
                        surfaceID: surfaceID,
                        bindingID: value.bindingID
                    )
                )
            }
            hadFocus = current == value.bindingID
        }
        .disabled(!value.enabled)
    }

    private func textBinding(
        _ value: PresentationNode.Input
    ) -> Binding<String> {
        Binding(
            get: { value.value },
            set: { changed in
                let limited = value.maxLength.map {
                    String(changed.prefix($0))
                } ?? changed
                sendValue(value.bindingID, .text(limited))
            }
        )
    }

    @ViewBuilder
    private func image(_ value: PresentationNode.Image) -> some View {
        let content = PresentationImageContent(value: value)
            .frame(minWidth: minimumTarget, minHeight: minimumTarget)
        if let action = value.activation {
            Button {
                sendAction(action)
            } label: {
                content
            }
            .buttonStyle(.plain)
            .disabled(!action.enabled)
            .accessibilityLabel(action.accessibilityLabel)
        } else {
            content.accessibilityLabel(value.accessibility.label)
        }
    }

    private func status(_ value: PresentationNode.Status) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(value.title).font(.headline)
                if let detail = value.detail {
                    Text(detail).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let badge = value.badge {
                Text(badge).font(.caption)
            }
            if let action = value.activation {
                Button(action.label) {
                    sendAction(action)
                }
                .disabled(!action.enabled)
            }
        }
        .padding(8)
        .background(toneColor(value.tone).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(value.accessibility.label)
    }

    private func qr(_ value: PresentationNode.QrCode) -> some View {
        VStack {
            if let label = value.label {
                Text(label).font(.headline)
            }
            if value.purpose == .display,
               let payload = value.payloads.first,
               let image = qrImage(payload) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    // A peer reads this off the screen with a camera, so it
                    // must not be the element that yields when the viewport
                    // is tight. Against a fixed-size camera preview it was
                    // the only flexible child and collapsed to ~104pt on a
                    // 667pt screen, well under what a dense multi-stage
                    // payload resolves at
                    // (`2026-08-17-ios-exchange-qr-collapses`).
                    .frame(
                        minWidth: Self.minimumScannableQr,
                        maxWidth: 320,
                        minHeight: Self.minimumScannableQr,
                        maxHeight: 320
                    )
                    .layoutPriority(1)
                    .accessibilityLabel(value.accessibility.label)
            } else if value.purpose == .capture {
                MultipartCameraPreview(
                    onChunkScanned: {
                        sendValue(value.id, .text($0))
                    },
                    useFrontCamera: useFrontCamera,
                    onPermissionDenied: onCameraPermissionDenied
                )
                .id(useFrontCamera)
                // Flexible, so the preview is what gives way rather than the
                // QR beside it — a hard 250pt also squeezed the sibling
                // action buttons down to one character per line.
                // Deliberately small: the viewfinder only has to be big
                // enough to aim with. Scanning reads the camera's own frames,
                // not this view, so every point given back here buys QR size
                // on a compact screen.
                .frame(
                    minWidth: 100,
                    maxWidth: 180,
                    minHeight: 100,
                    maxHeight: 180
                )
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(value.accessibility.label)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func confirmation(
        _ value: PresentationNode.Confirmation
    ) -> some View {
        VStack(alignment: .leading) {
            Text(value.warning)
            HStack {
                Spacer()
                actionButton(value.cancel)
                actionButton(value.confirm)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(value.accessibility.label)
    }

    private func actionButton(_ action: PresentationAction) -> some View {
        Button(action.label) {
            sendAction(action)
        }
        .disabled(!action.enabled)
        .accessibilityLabel(action.accessibilityLabel)
    }

    private func children(_ nodes: [PresentationNode]) -> some View {
        ForEach(identifyPresentationNodes(nodes)) { identified in
            PresentationNodeView(
                node: identified.node,
                surfaceID: surfaceID,
                minimumTarget: minimumTarget,
                useFrontCamera: useFrontCamera,
                onCameraPermissionDenied: onCameraPermissionDenied,
                focusedBinding: focusedBinding,
                onEvent: onEvent
            )
        }
    }

    private func sendAction(_ action: PresentationAction) {
        onEvent(
            .actionActivated(
                surfaceID: surfaceID,
                interactionID: action.interactionID
            )
        )
    }

    private func sendValue(
        _ bindingID: String,
        _ value: PresentationInputValue
    ) {
        onEvent(
            .valueChanged(
                surfaceID: surfaceID,
                bindingID: bindingID,
                value: value
            )
        )
    }

    private func toneColor(_ tone: PresentationTone) -> Color {
        switch tone {
        case .neutral: .secondary
        case .accent: .accentColor
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }

    private func textContentType(
        for kind: PresentationInputKind
    ) -> UITextContentType? {
        switch kind {
        case .email: .emailAddress
        case .phone: .telephoneNumber
        case .url: .URL
        case .password, .pin: .password
        default: nil
        }
    }

    private func qrImage(_ value: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        guard let output = filter.outputImage else { return nil }
        let representation = CIContext().createCGImage(
            output.transformed(by: .init(scaleX: 10, y: 10)),
            from: output.extent.applying(.init(scaleX: 10, y: 10))
        )
        return representation.map {
            UIImage(cgImage: $0)
        }
    }
}

private struct PresentationImageContent: View {
    let value: PresentationNode.Image

    var body: some View {
        if value.shape == .circle {
            content.clipShape(Circle())
        } else {
            content.clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var content: some View {
        Group {
            if let data = value.data, let image = UIImage(data: Data(data)) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .brightness(Double(value.brightness - 1))
            } else {
                Text(value.fallbackText ?? "")
            }
        }
    }
}

private struct PresentationRowView: View {
    /// Shell-minted handle so tests and device automation can find and
    /// activate a row without matching localized copy. Core's opaque ids stay
    /// out of it. Only activatable rows carry it — a static row is content,
    /// not an affordance.
    static let identifier = "presentationRow"

    /// Shell-minted handle for the controls Core parks in a row, minted for
    /// the same reason as `identifier` above: tests need to find them
    /// without matching localized copy.
    static let controlIdentifier = "presentationRowControl"

    let row: PresentationRow
    let surfaceID: String
    let minimumTarget: CGFloat
    let useFrontCamera: Bool
    let onCameraPermissionDenied: () -> Void
    let focusedBinding: FocusState<String?>.Binding
    let onEvent: (PresentationEvent) -> Void

    var body: some View {
        HStack {
            rowContent
            // Rendered as a sibling of `rowContent`, never inside it: an
            // activatable row wraps its content in a Button, and a control
            // nested in a Button is not independently operable.
            controls
            if !row.secondaryActions.isEmpty {
                Menu {
                    ForEach(row.secondaryActions) { action in
                        Button(action.label) {
                            activate(action)
                        }
                        .disabled(!action.enabled)
                    }
                } label: {
                    // The glyph alone sized the button to 19x6pt: probing the
                    // live hierarchy on an iPhone SE, only a tap within a few
                    // points of dead centre opened the menu and ±5pt missed.
                    // `contentShape` makes the whole frame hittable rather
                    // than just the drawn dots.
                    Image(systemName: "ellipsis")
                        .frame(
                            minWidth: minimumTarget,
                            minHeight: minimumTarget
                        )
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Row actions")
            }
        }
        .padding(8)
        .background(row.selected ? Color.accentColor.opacity(0.12) : .clear)
    }

    /// The controls Core attached to this row.
    ///
    /// Decoded but never rendered until 2026-08-20, which left every
    /// settings toggle on iOS as text that did nothing
    /// (`_private/docs/problems/2026-08-20-ios-settings-toggles-render-no-control/`).
    private var controls: some View {
        ForEach(identifyPresentationNodes(row.controls)) { identified in
            PresentationNodeView(
                node: identified.node,
                surfaceID: surfaceID,
                minimumTarget: minimumTarget,
                useFrontCamera: useFrontCamera,
                onCameraPermissionDenied: onCameraPermissionDenied,
                focusedBinding: focusedBinding,
                onEvent: onEvent
            )
            .accessibilityIdentifier(Self.controlIdentifier)
        }
    }

    /// The row's own content, as a single accessibility element carrying
    /// the Core-supplied label.
    ///
    /// An activatable row is a real `Button` rather than a tap gesture: the
    /// gesture form left the row a plain stack, so VoiceOver announced it as
    /// text with no hint that it could be activated, and the exchange-mode
    /// picker was unreachable to anything driving the app by accessibility
    /// (`2026-08-16-ios-rows-are-not-buttons`).
    @ViewBuilder
    private var rowContent: some View {
        if let action = row.activation {
            Button {
                activate(action)
            } label: {
                summaryContent
            }
            .buttonStyle(.plain)
            .disabled(!row.enabled || !action.enabled)
            .accessibilityLabel(row.accessibility.label)
            .accessibilityIdentifier(Self.identifier)
        } else {
            summaryContent
                // Without this the label below would propagate to each child
                // `Text` instead of describing the row, so every line read
                // back as the row's label.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.accessibility.label)
        }
    }

    private var summaryContent: some View {
        HStack {
            if let data = row.imageData, let image = UIImage(data: Data(data)) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: minimumTarget, height: minimumTarget)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
            } else if let fallback = row.fallbackText {
                Text(fallback)
                    .frame(width: minimumTarget, height: minimumTarget)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Circle())
            }
            VStack(alignment: .leading) {
                Text(row.title).font(.headline)
                if let subtitle = row.subtitle {
                    Text(subtitle).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let detail = row.detail {
                Text(detail).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func activate(_ action: PresentationAction) {
        onEvent(
            .actionActivated(
                surfaceID: surfaceID,
                interactionID: action.interactionID
            )
        )
    }
}
