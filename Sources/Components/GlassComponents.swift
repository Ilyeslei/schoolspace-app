//
//  GlassComponents.swift
//  SchoolSpaceApp
//
//  Composants Liquid Glass réutilisables : boutons, cartes, etc.
//  Utilise .glassEffect, GlassEffectContainer, matériaux natifs iOS 26
//

import SwiftUI

// MARK: - Bouton Liquid Glass principal

struct GlassButton: View {
    let icon: String
    let title: String
    let subtitle: String?
    let action: () -> Void
    @State private var isPressed = false

    init(icon: String, title: String, subtitle: String? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icône dans un cercle
                ZStack {
                    Circle()
                        .fill(Color("AccentColor").opacity(0.15))
                        .frame(width: 48, height: 48)

                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color("AccentColor"))
                }

                // Textes
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 8)

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(GlassButtonStyle())
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

// Style de bouton personnalisé pour l'effet pressé
struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Carte InfoCard (pour usage futur)

struct InfoCard: View {
    let icon: String
    let label: String
    let title: String
    let subtitle: String
    let value: String
    let suffix: String

    init(
        icon: String,
        label: String,
        title: String,
        subtitle: String,
        value: String,
        suffix: String
    ) {
        self.icon = icon
        self.label = label
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.suffix = suffix
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Ligne du haut : icône + label
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color("AccentColor").opacity(0.15))
                        .frame(width: 28, height: 28)

                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color("AccentColor"))
                }

                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)
            }

            // Titre principal
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            // Sous-titre
            Text(subtitle)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)

            // Valeur + suffixe
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(suffix)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.tertiary)

                Spacer(minLength: 8)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

// MARK: - Conteneur pour grouper les effets de verre

struct GlassContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            content
        }
    }
}

// MARK: - Champ de saisie style verre

struct GlassTextField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String?
    let keyboardType: UIKeyboardType
    let autocapitalization: TextInputAutocapitalization
    let onSubmit: (() -> Void)?

    init(
        placeholder: String,
        text: Binding<String>,
        icon: String? = nil,
        keyboardType: UIKeyboardType = .default,
        autocapitalization: TextInputAutocapitalization = .sentences,
        onSubmit: (() -> Void)? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.icon = icon
        self.keyboardType = keyboardType
        self.autocapitalization = autocapitalization
        self.onSubmit = onSubmit
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: 24)
            }

            TextField(placeholder, text: $text)
                .font(.system(size: 17))
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autocapitalization)
                .disableAutocorrection(true)
                .onSubmit {
                    onSubmit?()
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}

// MARK: - Bouton d'action principal (pleine largeur)

struct PrimaryGlassButton: View {
    let title: String
    let icon: String?
    let isLoading: Bool
    let isDisabled: Bool
    let action: () -> Void

    init(
        title: String,
        icon: String? = nil,
        isLoading: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                }

                Text(title)
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .disabled(isLoading || isDisabled)
        .glassEffect(.regular.tint(Color("AccentColor")), in: .rect(cornerRadius: 16))
        .opacity(isDisabled ? 0.5 : 1.0)
    }
}

// MARK: - Barre de navigation en verre

struct GlassNavigationBar<Leading: View, Trailing: View>: View {
    let title: String
    let leading: Leading
    let trailing: Trailing

    init(
        title: String,
        @ViewBuilder leading: () -> Leading = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            leading
            Spacer()
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
        }
    }
}

// MARK: - Modifier pour coins arrondis constants

extension View {
    func glassCard(cornerRadius: CGFloat = 18) -> some View {
        self
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}