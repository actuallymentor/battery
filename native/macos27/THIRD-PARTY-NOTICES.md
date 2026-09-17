# Sources and notices

This is independently packaged compatibility code. It is not an official
actuallymentor/battery, Ampere, or Apple release. No original Battery executable,
Apple SDK, or upstream app bundle is redistributed; the original executable is
backed up locally on the user's machine.

The implementation was informed by these primary sources, read 17 September 2026:

- Battery 1.4.0 CLI and GUI protocol:
  `https://github.com/actuallymentor/battery/blob/v1.4.0/battery.sh`
  `https://github.com/actuallymentor/battery/blob/v1.4.0/app/modules/battery.js`
  CLI blob SHA: `6a541819c130fe8ce75a6fb590973859a4ad9ccb`.
  GUI module blob SHA: `5a8763e8cd966913d2ee9d1f17fd14ce239b9e5b`.
- Ampere v0.0.65: native preference keys, notification name, and the need to
  release a powerd registration through PowerUIAgent rather than only clearing
  a preference:
  `https://github.com/az-code-lab/ampere/blob/v0.0.65/Sources/Shared/NativeChargeLimit.swift`
  `https://github.com/az-code-lab/ampere/blob/v0.0.65/Sources/SMCWriter/main.swift`
  SMCWriter blob SHA: `fea745a5f5fab077a54552f07bcb631a9b4b1698`.
- Apple's public IOPowerSources dictionary key definitions:
  `https://github.com/apple-oss-distributions/IOKitUser/blob/main/ps.subproj/IOPSKeys.h`

No SMC register writes, copy of Ampere's licensing logic, or modification of
Ampere's distributed app is included. The native below-80% ceiling technique is
reimplemented here for Battery, with a separate policy and recovery state.

The fixed-ceiling 0.1.1 draft also reads Apple's IORegistry power-source properties
via IOKit; source documentation:
`https://github.com/apple-oss-distributions/xnu/blob/main/iokit/IOKit/pwr_mgt/IOPMPowerSource.h`
No SDK or private Apple header is included.

## Battery upstream MIT notice

MIT License

Copyright (c) 2022 Mentor Palokaj

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

## Ampere MIT notice

MIT License

Copyright (c) 2026 AZ Code Lab

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
