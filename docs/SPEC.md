# Product spec (locked)

See the kickoff brief in the project chat / PR description. Summary:

- Native Swift; no Pyodide; no WKWebView inference; no MusicXML
- Decoder never on GPU/WebGPU/Metal/CoreML
- Do not requantize published decoder; do not invent token vocabulary
- MIDI: SMF format 1, 480 TPQ, metrical division; web-player-compatible subset
- Gate 1: C-scale staff tokens match Python homr oracle before UI work
