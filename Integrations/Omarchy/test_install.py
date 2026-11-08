import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest


class InstallTests(unittest.TestCase):
    @unittest.skipUnless(sys.platform == 'linux' and shutil.which('gio'),
                         'Launching desktop entries requires Linux and GIO')
    def test_desktop_entries_launch_the_installed_binary_with_special_home_characters(self):
        for name in ['home $cash`tick"quote\\slash', 'home %f $cash`tick"quote\\slash',
                     'home %f= $cash`tick"quote\\slash']:
            with self.subTest(home=name), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                home = root / name
                config, data = root / 'config', root / 'data'
                binary = root / 'record-arguments'
                binary.write_text('#!/bin/sh\nprintf \'%s\\n\' "$0" "$@" > "$HOME/receipt.tmp"\n'
                                  'mv "$HOME/receipt.tmp" "$HOME/receipt"\n')
                binary.chmod(0o755)
                environment = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(config), XDG_DATA_HOME=str(data))
                script = Path(__file__).resolve().parents[1] / 'Linux/install.py'
                result = subprocess.run(['python3', str(script), '--binary', str(binary), '--cli', '/usr/bin/true'],
                                        env=environment, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                receipt = home / 'receipt'
                entries = [(data / 'applications/com.gdpais.sharingan.desktop', '--usage'),
                           (config / 'autostart/com.gdpais.sharingan.desktop', '--background')]
                for entry, argument in entries:
                    with self.subTest(argument=argument):
                        receipt.unlink(missing_ok=True)
                        result = subprocess.run(['gio', 'launch', str(entry)], env=environment,
                                                capture_output=True, text=True, timeout=10)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        deadline = time.monotonic() + 3
                        while not receipt.exists() and time.monotonic() < deadline:
                            time.sleep(0.01)
                        self.assertTrue(receipt.exists(), 'The installed executable did not record its invocation')
                        self.assertEqual(receipt.read_text().splitlines(),
                                         [str(home / '.local/bin/sharingan-linux'), argument])

    def test_desktop_commands_escape_special_characters_in_the_home_path(self):
        cases = [
            ('has space', 'has space'),
            ('has$cash', r'has\\$cash'),
            ('has`tick', r'has\\`tick'),
            ('has"quote', r'has\\"quote'),
            (r'has\slash', r'has\\\\slash'),
            ('has%f', 'has%%f'),
            ('has%f=path', 'has%%f=path'),
        ]
        for name, escaped in cases:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                home = root / name
                config, data = root / 'config', root / 'data'
                environment = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(config), XDG_DATA_HOME=str(data))
                script = Path(__file__).resolve().parents[1] / 'Linux/install.py'
                result = subprocess.run(['python3', str(script), '--binary', '/usr/bin/true',
                                         '--cli', '/usr/bin/true'], env=environment,
                                        capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stderr)
                executable = r'/bin/sh -c "exec \\"\\$@\\"" sharingan ' if '%' in name else ''
                command = f'Exec={executable}"{root}/{escaped}/.local/bin/sharingan-linux"'
                launcher = (data / 'applications/com.gdpais.sharingan.desktop').read_text()
                self.assertEqual([line for line in launcher.splitlines() if line.startswith('Exec=')],
                                 [command + ' --usage', command + ' --settings', command + ' --spending'])
                startup = (config / 'autostart/com.gdpais.sharingan.desktop').read_text()
                self.assertIn(command + ' --background', startup.splitlines())

    def test_reinstall_preserves_the_desktop_entry_hidden_setting(self):
        cases = [
            ('Hidden=true\n', True),
            ('Hidden = true\n', True),
            ('Hidden\t=\ttrue\n', True),
            ('Hidden=false\n', False),
            ('# Hidden=true\nHidden=false\n', False),
            ('Comment=Set Hidden=true to disable startup\nHidden=false\n', False),
            ('X-Hidden=true\nHidden=false\n', False),
            ('Hidden=false\n[Desktop Action Settings]\nHidden=true\n', False),
            ('[Desktop Action Settings]\nHidden=true\n', False),
            ('hidden=true\n', False),
        ]
        for entry, disabled in cases:
            with self.subTest(entry=entry), tempfile.TemporaryDirectory() as temporary:
                home = Path(temporary)
                config, data = home / 'config', home / 'data'
                startup = config / 'autostart/com.gdpais.sharingan.desktop'
                startup.parent.mkdir(parents=True)
                startup.write_text('[Desktop Entry]\nType=Application\nName=Sharingan\n' + entry)
                environment = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(config), XDG_DATA_HOME=str(data))
                script = Path(__file__).resolve().parents[1] / 'Linux/install.py'
                for _ in range(2):
                    result = subprocess.run(['python3', str(script), '--binary', '/usr/bin/true',
                                             '--cli', '/usr/bin/true'], env=environment,
                                            capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn(f'Hidden={str(disabled).lower()}', startup.read_text().splitlines())

    def test_xdg_directories_use_defaults_unless_absolute(self):
        for value in [None, '', 'relative', 'absolute']:
            with self.subTest(value=value), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                home, working = root / 'home', root / 'working'
                working.mkdir()
                config = root / 'config' if value == 'absolute' else home / '.config'
                data = root / 'data' if value == 'absolute' else home / '.local/share'
                preferences = config / 'sharingan/linux.json'
                environment = {'PATH': os.environ['PATH'], 'HOME': str(home)}
                for key, directory in [('XDG_CONFIG_HOME', config), ('XDG_DATA_HOME', data),
                                       ('XDG_BIN_HOME', root / 'bin')]:
                    if value is not None:
                        environment[key] = str(directory) if value == 'absolute' else value
                script = Path(__file__).resolve().parents[1] / 'Linux/install.py'
                command = ['python3', str(script), '--binary', '/usr/bin/true', '--cli', '/usr/bin/true']
                for options in [['--no-autostart'], []]:
                    result = subprocess.run(command + options, cwd=working, env=environment,
                                            capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertTrue(preferences.is_file(), 'Installer ignored the home-directory fallback')
                    if options:
                        saved = json.dumps({'provider': 'claude', 'refreshSeconds': 900})
                        preferences.write_text(saved)
                self.assertEqual(list(working.iterdir()), [], 'Installer wrote files into its working directory')
                self.assertEqual(json.loads(preferences.read_text())['provider'], 'claude')
                self.assertEqual(json.loads(preferences.read_text())['refreshSeconds'], 900)
                backups = list(preferences.parent.glob('linux.json.backup-*'))
                self.assertEqual(len(backups), 1)
                self.assertEqual(backups[0].read_text(), saved)
                self.assertIn('Hidden=true', (config / 'autostart/com.gdpais.sharingan.desktop').read_text())
                self.assertTrue((data / 'applications/com.gdpais.sharingan.desktop').is_file())
                self.assertTrue((data / 'icons/hicolor/scalable/apps/sharingan.svg').is_file())
                self.assertEqual((home / '.local/bin/sharingan-linux').read_bytes(), Path('/usr/bin/true').read_bytes())
                self.assertFalse((root / 'bin').exists())

    def test_migration_and_reinstall_preserve_preferences_and_layout(self):
        with tempfile.TemporaryDirectory(prefix='sharingan install ') as temporary:
            home = Path(temporary)
            config = home / 'config'
            shell = config / 'omarchy/shell.json'
            shell.parent.mkdir(parents=True)
            shell.write_text(json.dumps({'bar': {'layout': {'right': [
                {'id': 'gdpais.sharingan', 'provider': 'claude', 'refreshSeconds': 900, 'allAccounts': True},
                {'id': 'omarchy.clock'}]}}, 'idle': {'lock': 123}}))
            script = Path(__file__).with_name('install.py')
            environment = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(config), XDG_DATA_HOME=str(home/'data'))
            for _ in range(2):
                subprocess.run(['python3', str(script), '--executable', '/usr/bin/true',
                                '--desktop-binary', '/usr/bin/true'], env=environment, check=True, capture_output=True)
            result = json.loads(shell.read_text())
            self.assertEqual(result['idle'], {'lock': 123})
            self.assertEqual([e['id'] for e in result['bar']['layout']['right']], ['gdpais.sharingan', 'omarchy.clock'])
            entry = result['bar']['layout']['right'][0]
            self.assertEqual(set(entry), {'id', 'desktopExecutable'})
            settings = json.loads((config/'sharingan/linux.json').read_text())
            self.assertEqual(settings['provider'], 'claude')
            self.assertEqual(settings['refreshSeconds'], 900)
            self.assertTrue(settings['allAccounts'])
            self.assertFalse(settings['showTray'])
            self.assertEqual(len(list((shell.parent / 'plugins').glob('*/manifest.json'))), 1)
            sources = Path(__file__).resolve().parents[2] / 'Sources/Sharingan/Resources'
            installed = shell.parent / 'plugins/gdpais.sharingan/icons'
            logos = sorted(sources.glob('ProviderIcon-*.svg'))
            self.assertTrue(logos)
            self.assertEqual(sorted(path.name for path in installed.iterdir()), [path.name for path in logos])
            for logo in logos:
                self.assertEqual((installed / logo.name).read_bytes(), logo.read_bytes())
            self.assertEqual(len(list((shell.parent / 'backups').iterdir())), 1)
            self.assertEqual((config/'sharingan/linux.json').stat().st_mode & 0o077, 0)
            launcher = (home/'data/applications/com.gdpais.sharingan.desktop').read_text()
            self.assertIn(f'Exec="{home}/.local/bin/sharingan-linux" --settings', launcher)
            self.assertTrue((config/'autostart/com.gdpais.sharingan.desktop').exists())

    def test_dotfiles_symlinks_survive_and_receive_the_change(self):
        with tempfile.TemporaryDirectory(prefix='sharingan symlink ') as temporary:
            home = Path(temporary)
            config, data = home / 'config', home / 'data'
            managed = home / 'dotfiles'
            (managed / 'omarchy').mkdir(parents=True)
            (managed / 'sharingan').mkdir()
            (managed / 'autostart').mkdir()
            tracked = managed / 'omarchy/shell.json'
            tracked.write_text(json.dumps({'bar': {'layout': {'right': [
                {'id': 'omarchy.clock', 'format': "'\uf017  'HH:mm"}]}}}, ensure_ascii=False))
            (config / 'omarchy').mkdir(parents=True)
            (config / 'omarchy/shell.json').symlink_to(os.path.relpath(tracked, config / 'omarchy'))
            # A preferences link can predate the install; an autostart link is created by it.
            (config / 'sharingan').mkdir()
            preferences = managed / 'sharingan/linux.json'
            preferences.write_text(json.dumps({'provider': 'claude'}))
            (config / 'sharingan/linux.json').symlink_to(preferences)
            (config / 'autostart').mkdir()
            startup = managed / 'autostart/com.gdpais.sharingan.desktop'
            startup.write_text('[Desktop Entry]\n')
            (config / 'autostart/com.gdpais.sharingan.desktop').symlink_to(startup)
            (data / 'applications').mkdir(parents=True)
            launcher = managed / 'launcher.desktop'
            launcher.write_text('[Desktop Entry]\n')
            (data / 'applications/com.gdpais.sharingan.desktop').symlink_to(launcher)
            script = Path(__file__).resolve().parents[1] / 'Linux/install.py'
            environment = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(config), XDG_DATA_HOME=str(data))
            for _ in range(2):
                subprocess.run(['python3', str(script), '--binary', '/usr/bin/true', '--cli', '/usr/bin/true',
                                '--omarchy'], env=environment, check=True, capture_output=True)
                for link in ['omarchy/shell.json', 'sharingan/linux.json', 'autostart/com.gdpais.sharingan.desktop']:
                    self.assertTrue((config / link).is_symlink(), f'{link} lost its link')
                self.assertTrue((data / 'applications/com.gdpais.sharingan.desktop').is_symlink())
            self.assertIn('gdpais.sharingan',
                          [entry['id'] for entry in json.loads(tracked.read_text())['bar']['layout']['right']])
            self.assertEqual(json.loads(preferences.read_text())['provider'], 'claude')
            self.assertIn('--background', startup.read_text())
            self.assertIn('--settings', launcher.read_text())
            # Rewriting a managed file must not turn its glyphs into escapes and churn the diff.
            self.assertIn('\uf017', tracked.read_text())
            self.assertNotIn('\\uf017', tracked.read_text())
            # Payload-path behaviour is asserted in its own test, which starts from real links.

    def test_utf8_configuration_can_be_reinstalled_in_an_ascii_locale(self):
        for omarchy in [False, True]:
            with self.subTest(omarchy=omarchy), tempfile.TemporaryDirectory(prefix='sharingan encoding ') as temporary:
                home = Path(temporary)
                config, data = home / 'config', home / 'data'
                preferences = config / 'sharingan/linux.json'
                preferences.parent.mkdir(parents=True)
                preferences.write_text(json.dumps({'provider': 'claude', 'note': 'caf\u00e9'}), encoding='utf-8')
                shell = config / 'omarchy/shell.json'
                if omarchy:
                    shell.parent.mkdir(parents=True)
                    shell.write_text(json.dumps({'bar': {'layout': {'right': [
                        {'id': 'omarchy.clock', 'format': "'\uf017  'HH:mm"}]}}}), encoding='utf-8')
                script = Path(__file__).resolve().parents[1] / 'Linux/install.py'
                environment = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(config), XDG_DATA_HOME=str(data),
                                   LC_ALL='C', PYTHONUTF8='0', PYTHONCOERCECLOCALE='0')
                command = ['python3', str(script), '--binary', '/usr/bin/true', '--cli', '/usr/bin/true']
                if omarchy:
                    command.append('--omarchy')
                for _ in range(2):
                    result = subprocess.run(command, env=environment, capture_output=True)
                    self.assertEqual(result.returncode, 0, result.stderr.decode('utf-8', errors='replace'))
                self.assertEqual(json.loads(preferences.read_text(encoding='utf-8'))['note'], 'caf\u00e9')
                if omarchy:
                    self.assertIn('\uf017', shell.read_text(encoding='utf-8'))

    def test_installer_payload_paths_replace_links_instead_of_writing_through_them(self):
        with tempfile.TemporaryDirectory(prefix='sharingan payload ') as temporary:
            home = Path(temporary)
            config, data = home / 'config', home / 'data'
            decoy = home / 'decoy'
            decoy.mkdir()
            binary_target = decoy / 'sharingan-linux'
            binary_target.write_text('original')
            (home / '.local/bin').mkdir(parents=True)
            (home / '.local/bin/sharingan-linux').symlink_to(binary_target)
            plugin_target = decoy / 'plugin'
            plugin_target.mkdir()
            (config / 'omarchy/plugins').mkdir(parents=True)
            (config / 'omarchy/plugins/gdpais.sharingan').symlink_to(plugin_target)
            (config / 'omarchy').mkdir(parents=True, exist_ok=True)
            (config / 'omarchy/shell.json').write_text('{}')
            script = Path(__file__).resolve().parents[1] / 'Linux/install.py'
            environment = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(config), XDG_DATA_HOME=str(data))
            subprocess.run(['python3', str(script), '--binary', '/usr/bin/true', '--cli', '/usr/bin/true',
                            '--omarchy'], env=environment, check=True, capture_output=True)
            self.assertFalse((home / '.local/bin/sharingan-linux').is_symlink())
            self.assertEqual(binary_target.read_text(), 'original')
            self.assertFalse((config / 'omarchy/plugins/gdpais.sharingan').is_symlink())
            self.assertEqual(list(plugin_target.iterdir()), [])

    def test_a_broken_plugin_link_does_not_abort_the_install(self):
        with tempfile.TemporaryDirectory(prefix='sharingan broken ') as temporary:
            home = Path(temporary)
            config, data = home / 'config', home / 'data'
            (config / 'omarchy/plugins').mkdir(parents=True)
            (config / 'omarchy/plugins/gdpais.sharingan').symlink_to(home / 'gone')
            (config / 'omarchy/shell.json').write_text('{}')
            script = Path(__file__).resolve().parents[1] / 'Linux/install.py'
            environment = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(config), XDG_DATA_HOME=str(data))
            subprocess.run(['python3', str(script), '--binary', '/usr/bin/true', '--cli', '/usr/bin/true',
                            '--omarchy'], env=environment, check=True, capture_output=True)
            self.assertTrue((config / 'omarchy/plugins/gdpais.sharingan/manifest.json').is_file())

    def test_standalone_install_does_not_require_omarchy(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            environment = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home/'config'), XDG_DATA_HOME=str(home/'data'))
            script = Path(__file__).resolve().parents[1] / 'Linux/install.py'
            subprocess.run(['python3', str(script), '--binary', '/usr/bin/true', '--cli', '/usr/bin/true', '--no-autostart'],
                           env=environment, check=True, capture_output=True)
            self.assertFalse((home/'config/omarchy').exists())
            self.assertIn('Hidden=true', (home/'config/autostart/com.gdpais.sharingan.desktop').read_text())


if __name__ == '__main__':
    unittest.main()
