"""Validate the reviewed device IPA before publishing it from GitHub Actions."""
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import sys
import zipfile


def verify_arm64_device(data):
    magic = data[:4]
    if magic in (bytes.fromhex('cafebabe'), bytes.fromhex('cafebabf')):
        count = struct.unpack_from('>I', data, 4)[0]
        assert 0 < count <= 16, 'Invalid universal Mach-O header'
        wide = magic == bytes.fromhex('cafebabf')
        stride = 32 if wide else 20
        slices = []
        for index in range(count):
            entry = 8 + index * stride
            cpu = struct.unpack_from('>I', data, entry)[0]
            offset, size = struct.unpack_from('>QQ' if wide else '>II', data, entry + 8)
            assert size >= 32 and offset + size <= len(data)
            if cpu == 0x100000c:
                slices.append(data[offset:offset + size])
        assert slices, 'Universal binary has no arm64 slice'
        for part in slices:
            verify_arm64_device(part)
        return
    assert magic == bytes.fromhex('cffaedfe'), 'Unsupported Mach-O format: ' + magic.hex()
    assert struct.unpack_from('<I', data, 4)[0] == 0x100000c, 'Not arm64'
    commands = struct.unpack_from('<I', data, 16)[0]
    assert commands < 1024
    cursor, device = 32, False
    for _ in range(commands):
        command, size = struct.unpack_from('<II', data, cursor)
        assert size >= 8 and cursor + size <= len(data)
        if command == 0x32:  # LC_BUILD_VERSION distinguishes iOS from Simulator.
            assert struct.unpack_from('<I', data, cursor + 8)[0] == 2, 'Not an iOS device binary'
            device = True
        elif command == 0x25:  # Legacy LC_VERSION_MIN_IPHONEOS.
            device = True
        cursor += size
    assert device, 'Missing iOS deployment target'


def verify(folder):
    folder = Path(folder)
    packages = list(folder.glob('*.ipa'))
    assert len(packages) == 1, 'Expected one IPA'
    package = packages[0]
    digest = hashlib.file_digest(package.open('rb'), 'sha256').hexdigest()
    expected, filename = (folder / 'SHA256SUMS.txt').read_text().strip().split()
    assert (digest, package.name) == (expected, filename)
    with zipfile.ZipFile(package) as archive:
        assert archive.testzip() is None, 'ZIP integrity failed'
        main = 'Payload/Runner.app/'
        info = plistlib.loads(archive.read(main + 'Info.plist'))
        assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS']
        assert info['CFBundleShortVersionString'] == '0.5.6'
        assert info['CFBundleVersion'] == '2278'
        assert info['CFBundleIdentifier'] == 'org.mewx.wenku8Flutter.sourcePreview'
        assert not any(name.endswith('libcpp.so') for name in archive.namelist())
        widget = main + 'PlugIns/ReadingWidgets.appex/'
        widget_info = plistlib.loads(archive.read(widget + 'Info.plist'))
        assert widget_info['CFBundleVersion'] == '2278'
        for binary in [main + info['CFBundleExecutable'],
                       main + 'Frameworks/App.framework/App',
                       main + 'Frameworks/Flutter.framework/Flutter',
                       widget + widget_info['CFBundleExecutable']]:
            data = archive.read(binary)
            verify_arm64_device(data)
    result = {'filename': package.name, 'bytes': package.stat().st_size,
              'sha256': digest, 'version': '0.5.6', 'build': '2278',
              'bundle': info['CFBundleIdentifier'],
              'widget_bundle': widget_info['CFBundleIdentifier'],
              'crc': 'passed', 'arm64': 'passed',
              'source_commit': (folder / 'SOURCE_COMMIT.txt').read_text().strip()}
    (folder / 'BUILD_VALIDATION.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))


if __name__ == '__main__':
    verify(sys.argv[1])
