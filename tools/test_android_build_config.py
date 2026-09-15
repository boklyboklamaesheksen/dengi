#!/usr/bin/env python3
"""Exercise the Gradle configuration in an isolated stub project, not an APK build."""
import argparse
import base64
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--gradle', required=True, help='Path to Gradle 8.14+')
    args = parser.parse_args()
    gradle = str(Path(args.gradle).resolve())
    with tempfile.TemporaryDirectory(prefix='rabochiy-config-') as tmp:
        root = Path(tmp)
        android = root / 'android'
        android.mkdir()
        (root / 'config').mkdir()
        (root / 'pubspec.yaml').write_text('version: 1.0.1+3\n')
        (android / 'local.properties').write_text('flutter.versionName=1.0.0\nflutter.versionCode=2\n')
        (android / 'settings.gradle').write_text("rootProject.name = 'configuration-test'\n")
        shutil.copy(ROOT / 'android/flutter-build-config.gradle', android)
        (android / 'build.gradle').write_text('''
apply from: 'flutter-build-config.gradle'
tasks.register('compileFlutterBuildDebug') {
    doLast {
        assert project.ext.rabochiyVersionName == '1.0.1'
        assert project.ext.rabochiyVersionCode == 3
        def decoded = project.property('dart-defines').split(',').collect {
            new String(Base64.decoder.decode(it), 'UTF-8')
        }
        assert decoded.contains('RABOCHIY_SIGNING_SECRET=' + project.property('expected'))
        println 'CONFIGURATION_OK'
    }
}
''')
        environment = {k: v for k, v in os.environ.items() if k != 'RABOCHIY_SIGNING_SECRET'}

        def run(arguments, expected_success, env=None):
            result = subprocess.run([gradle, '-q', '-p', str(android), *arguments],
                                    env=env or environment, capture_output=True, text=True, timeout=120)
            output = result.stdout + result.stderr
            if (result.returncode == 0) != expected_success:
                raise AssertionError(output)
            return output

        run(['tasks'], True)
        output = run(['compileFlutterBuildDebug', '-Pexpected=unused'], False)
        assert 'Missing RABOCHIY_SIGNING_SECRET' in output
        secrets = root / 'config/build-secrets.json'
        secrets.write_text(json.dumps({'RABOCHIY_SIGNING_SECRET': 'local-test-value'}))
        assert 'CONFIGURATION_OK' in run(['compileFlutterBuildDebug', '-Pexpected=local-test-value'], True)
        encoded = base64.b64encode(b'RABOCHIY_SIGNING_SECRET=cli-test-value').decode()
        assert 'CONFIGURATION_OK' in run(['compileFlutterBuildDebug', '-Pexpected=cli-test-value',
                                        '-Pdart-defines=' + encoded], True)
        env = dict(environment, RABOCHIY_SIGNING_SECRET='environment-test-value')
        assert 'CONFIGURATION_OK' in run(['compileFlutterBuildDebug', '-Pexpected=environment-test-value'], True, env)
        secrets.write_text('{broken json')
        assert 'must be a JSON object' in run(['tasks'], False)
        print('6 Gradle configuration scenarios passed; stale local.properties cannot lower version 1.0.1 (3).')


if __name__ == '__main__':
    main()
