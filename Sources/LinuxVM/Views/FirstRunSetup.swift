import SwiftUI

/// Shown once on first launch: the user chooses the login applied to every VM
/// they create. Cannot be dismissed without choosing.
struct FirstRunSetup: View {
    @EnvironmentObject var creds: CredentialsStore
    @State private var username = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var reveal = false

    private var passwordsMatch: Bool { password == confirm }
    private var usernameOK: Bool {
        username.isEmpty || CredentialsStore.isValidUsername(username)
    }
    private var valid: Bool {
        CredentialsStore.isValidUsername(username) && password.count >= 4 && passwordsMatch
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.indigo.gradient).frame(width: 64, height: 64)
                    Image(systemName: "person.badge.key.fill").font(.system(size: 26)).foregroundStyle(.white)
                }
                Text("Welcome to Linux VM").font(.title2.bold())
                Text("Choose the login for the VMs you create. It's stored securely in your Keychain and applied to every new VM.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 20)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                LabeledContent("Username") {
                    TextField("e.g. dev", text: $username)
                        .textFieldStyle(.roundedBorder).frame(width: 240)
                }
                LabeledContent("Password") {
                    Group {
                        if reveal { TextField("password", text: $password) }
                        else { SecureField("password", text: $password) }
                    }
                    .textFieldStyle(.roundedBorder).frame(width: 240)
                }
                LabeledContent("Confirm") {
                    HStack {
                        Group {
                            if reveal { TextField("repeat", text: $confirm) }
                            else { SecureField("repeat", text: $confirm) }
                        }
                        .textFieldStyle(.roundedBorder).frame(width: 240)
                        Button { reveal.toggle() } label: {
                            Image(systemName: reveal ? "eye.slash" : "eye")
                        }.buttonStyle(.borderless)
                    }
                }
                if !usernameOK {
                    Label("Username must be lowercase, start with a letter, and use only a–z, 0–9, _ or -",
                          systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !confirm.isEmpty && !passwordsMatch {
                    Label("Passwords don't match", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.red)
                }
            }
            .padding(24)

            Divider()
            HStack {
                Spacer()
                Button("Get Started") {
                    creds.username = username
                    creds.password = password
                    creds.save()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!valid)
            }
            .padding(16)
        }
        .frame(width: 460)
        .interactiveDismissDisabled(true)
    }
}
