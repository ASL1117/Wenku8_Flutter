"""Validate the reviewed device IPA before publishing it from GitHub Actions."""
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import sys
import zipfile


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
            assert data[:4] == bytes.fromhex('cffaedfe'), binary
            assert struct.unpack_from('<I', data, 4)[0] == 0x100000c, binary
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
