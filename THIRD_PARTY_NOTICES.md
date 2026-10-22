# Research and dependencies

SoundDeck is a new implementation, not a renamed VolumeMixer fork. The following references informed API and hook selection:

- [VolumeMixer](https://github.com/brendonjkding/VolumeMixer), brendonjkding, MIT (2020). In particular, `Tweak.xm` demonstrates app-local AudioUnit, AVPlayer and AVAudioSession hook opportunities. SoundDeck does not use its executable trampolines, MRYIPC, HUD, or last-object volume tracking. The reference's license is reproduced below as attribution.
- [Theos documentation](https://theos.dev/docs/), including [iOS installation](https://theos.dev/docs/installation-ios) and [rootless packaging](https://theos.dev/docs/rootless). The build uses the already-installed native compiler and SDK directly; no Theos source or SDK is redistributed.
- [ElleKit](https://github.com/ellekit/ellekit), supplied by the jailbreak, provides the runtime `MSHookFunction` / `MSHookMessageEx` compatibility interface. It is a package dependency, not vendored code.
- UIKit, AVFoundation, AudioToolbox, MediaPlayer and Celestial are device-provided Apple frameworks. SF Symbols are used through the operating system. No Apple framework binaries, SDKs or symbol artwork are redistributed as source assets.
- `Tests/assets/03may2020-tobefree.mp3` is a separate QA-only stock recording by Tobias “ToBeFree” Frei, [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:03may2020-tobefree.mp3), licensed [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). It is not part of either Debian package; see `Tests/assets/README.md` for attribution.

## VolumeMixer license

MIT License

Copyright (c) 2020 brendonjkding

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
