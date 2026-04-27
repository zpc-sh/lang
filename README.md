# lang

MoonBit runtime for multi-model AI agents, spanning protocol codecs, node/runtime substrate, and AI session identity.

This repository is **dualistic at its core**: `mulsp` (runtime session identity/state machine) and `muyata` (cognitive profile/intent envelope).

---

## 📝 Basic Project Info

### Project Name
`lang` (`zpc/lang` in `moon.mod.json`)

### Short Description
`lang` is a MoonBit-first runtime and protocol substrate for AI agents.
It models *who an agent is* (`mulsp`) and *how it thinks/acts* (`muyata`) while integrating with protocols and node infrastructure.

### Long Description / Motivation
The project provides typed, serializable primitives for multi-agent execution across distributed surfaces.  
It exists to make agent identity, lifecycle transitions, capability scoping, and cognitive intent explicit and auditable instead of implicit.

---

## ☯️ Dual Core Architecture

### 1) `mulsp` — Runtime Identity Wrapper
- **Path:** `/home/runner/work/lang/lang/mulsp/mulsp.mbt`
- Models session identity, lifecycle (`Dormant → Attached → Active → ...`), delegation, and capability scope.
- Uses immutable transition APIs and binary wire format (`MLSP` magic).

### 2) `muyata` — AI-Shaped Cognitive Profile
- **Path:** `/home/runner/work/lang/lang/muyata/muyata.mbt`
- Models overlay/family/mode/tier, work intent, execution surface, and commitments.
- Supports profile cloning and binary wire format (`MUYA` magic).

Together:
- `mulsp` answers: **“Which session is this, and what can it do right now?”**
- `muyata` answers: **“What kind of mind/work profile is attached?”**

---

## ⚙️ Technical Details

### Tech Stack / Frameworks
- **Language:** MoonBit (`.mbt`)
- **Build/Test Tool:** `moon`
- **Dependency (declared):** `moonbitlang/async` (`moon.mod.json`)

### System Requirements
- MoonBit toolchain with `moon` installed
- Unix-like environment recommended for local development (Linux/macOS)
- Additional runtime/toolchain requirements: _TBD (add exact MoonBit version)_

### Dependencies / Packages
- Primary external dependency: `moonbitlang/async`
- Internal packages include: `mulsp`, `muyata`, `node`, `lsp`, `nntp`, `gopher`, `proto`, `spore`, `cave`, `loci/claude`, `yata/*`, etc.

---

## 🚀 Setup & Installation

### Prerequisites
- Git
- MoonBit CLI (`moon`)

### Installation
```bash
git clone https://github.com/zpc-sh/lang.git
cd lang
```

### Build / Test
```bash
moon test
```

### Configuration
- No `.env`-based config is currently documented at root.
- Add environment/config documentation here as runtime configuration stabilizes.

---

## 🧪 Usage

### How to Run the Project
Current verified entrypoint for contributors:
```bash
moon test
```

For package-level exploration, inspect:
- `/home/runner/work/lang/lang/mulsp/mulsp.mbt`
- `/home/runner/work/lang/lang/muyata/muyata.mbt`

### Example Inputs / Outputs
- `MulspState` can be created, transitioned, and serialized/deserialized.
- `MuyataProfile` can be constructed by tier/intent and serialized/deserialized.
- Add concrete CLI/runtime examples once native runtime (`net` milestone) is finalized.

### Screenshots / GIFs
No repository screenshots/assets detected.

### Demo Links
No deployed demo links detected.

---

## ✨ Features

✅ Key Features
- Dual identity model: lifecycle state (`mulsp`) + cognitive intent profile (`muyata`)
- Typed wire serialization for core identity/profile objects
- Package-oriented MoonBit architecture covering protocols and node substrate
- Spec-driven testing pattern in parts of the repo (`*_spec.mbt` + `*_spec_test.mbt`)

⚠️ Limitations / Coming Soon
- `net` package milestone is in progress
- Some roadmap features in `task.md` are not yet complete
- CI workflow configuration not detected in repository root

---

## 🤝 Contribution & Community

### How to Contribute
1. Fork the repository
2. Create a branch
3. Make changes with tests
4. Open a pull request

### Issue / Bug Reporting
- Use GitHub Issues: `https://github.com/zpc-sh/lang/issues`

### Community Links
- GitHub Discussions/Discord/Slack: _Not specified yet (add links)_

---

## 🧪 Testing & Deployment

### Testing
```bash
moon test
```

### Deployment
- No deployment pipeline or hosting target documented yet.
- Add CI/CD and release flow once runtime/server milestones are productionized.

---

## 📈 Project Management

### Roadmap / Future Plans
- See `/home/runner/work/lang/lang/task.md` for milestone planning (M1–M4).

### Changelog / Versioning
- Current module version in `moon.mod.json`: `0.1.0`
- Changelog file: _Not yet present (recommended: `CHANGELOG.md`)_

---

## 🏅 Badges (Optional)

_Add as needed:_
- Build status badge
- License badge
- Stars/Forks/Issues badges
- MoonBit/tooling badges

---

## 📚 Meta Information

### License
- Repository includes a **Superposition License** form with SPDX collapse state documented as `Apache-2.0` in `LICENSE.mbt.md`.
- See:
  - `/home/runner/work/lang/lang/LICENSE`
  - `/home/runner/work/lang/lang/LICENSE.mbt.md`
  - `/home/runner/work/lang/lang/LICENSE-EXECUTABLE.md`

### Acknowledgements
- Credits noted in license text: **Loc & Claude (ZPC)**

### Contact
- GitHub: `https://github.com/zpc-sh`
- Add maintainer email/site/other handles here.
