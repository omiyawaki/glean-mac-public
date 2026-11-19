# glean-mac

A native macOS (SwiftUI) frontend for [glean](https://github.com/omiyawaki/glean-public),
my plain-text reference manager, and for the paper-intake pipeline that feeds
it. It is a local-first app: the library is readable and searchable offline,
and changes made while offline are queued and synced later.

I built it because the CLI and terminal UI are good for scripting but poor for
reading: I wanted to triage new papers, read PDFs and review the filter's
borderline decisions in one native window.

## What it does

- **Library.** Browse and search the whole reference library, with record
  details, citation relations, citation and BibTeX copy actions, and export.
- **Intake and review.** Shows papers the intake pipeline is considering and a
  "maybe" queue for borderline relevance decisions. Accept or reject with a
  keystroke.
- **PDF backlog.** A work list of papers that still need a PDF. Drop a PDF on
  an entry, or open the publisher page in the built-in web viewer and let the
  app capture the download and attach it.
- **Reader.** PDF viewer with a dark mode and a web viewer that injects
  [Dark Reader](https://darkreader.org/) (MIT) to theme publisher pages.
- **Local-first sync.** A local read-model of the library, a pending-operation
  store and a sync worker that replays queued actions when the backend is
  reachable.

## Architecture

```
SwiftUI views  ->  stores (Library*, Backlog*, Intake*, Review*)
                     |-- LocalLibraryIndexReader   read model of the library
                     |-- PendingOperationStore     durable queue of offline actions
                     '-- PendingOperationSyncWorker replays the queue
                  GleanBackendEndpoints  ->  HTTP + server-sent events to the
                                             glean / paper-intake backend
```

Sources are in `Sources/GleanMac`; tests are in `Tests/GleanMacTests`
(about 12,300 lines of app code and 6,600 lines of tests).

## Build and run

Requires macOS 26 and the Swift 6.2 toolchain.

```bash
swift test
swift run
./build-app.sh        # builds and wraps the binary as an .app bundle
```

`Package.swift` pulls the shared design-system and updater code from
[apple-app-tools-public](https://github.com/omiyawaki/apple-app-tools-public)
as a remote SwiftPM dependency (tracking its `main` branch). `build-app.sh`
also runs that repository's `apple-app-tools` command-line tool to package the
`.app`; point `APPLE_APP_TOOLS_REPO` at a local clone of it.

## Backend configuration

The app talks to a [glean](https://github.com/omiyawaki/glean-public) web
service (library API) and a paper-intake service (intake and review API).
Both base URLs default to localhost and can be changed without rebuilding:

| Setting | Environment variable | `UserDefaults` key | Default |
| --- | --- | --- | --- |
| Intake service | `GLEAN_INTAKE_URL` | `GleanIntakeURL` | `http://localhost:8765` |
| Library service | `GLEAN_LIBRARY_URL` | `GleanLibraryURL` | `http://localhost:8766` |

An app launched from Finder does not see shell variables, so set the
`UserDefaults` keys instead, for example
`defaults write <bundle id> GleanIntakeURL http://host:8765`. The bundled
`Resources/Info.plist` only allows plain HTTP to local-network addresses; add
an `NSExceptionDomains` entry (or use HTTPS) for any other host.

## Third-party code

`Sources/GleanMac/Resources/darkreader.js` is [Dark Reader](https://darkreader.org/)
v4.9.125, MIT licensed. Its license text is in
[`THIRD_PARTY_LICENSES/darkreader-LICENSE.txt`](THIRD_PARTY_LICENSES/darkreader-LICENSE.txt).

## License

MIT. See [LICENSE](LICENSE).
