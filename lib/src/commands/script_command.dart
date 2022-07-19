// Copyright (c) 2022, Very Good Ventures
// https://verygood.ventures
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

// ignore_for_file: avoid_positional_boolean_parameters

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cli_menu/cli_menu.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:yaml/yaml.dart';

/// {@template script_command}
///
/// `flutter_scripts script`
/// A [Command] to run a script in the pubspec.yaml.
/// {@endtemplate}
class ScriptCommand extends Command<int> {
  /// {@macro script_command}
  ScriptCommand({
    Logger? logger,
  }) : _logger = logger ?? Logger() {
    argParser
      ..addOption(
        'command',
        abbr: 'c',
        help: 'Command to run',
      )
      ..addFlag(
        'quiet',
        abbr: 'q',
        help: 'Quiet mode',
      )
      ..addFlag(
        'parallel',
        abbr: 'p',
        help: 'Run in parallel',
      )
      ..addOption(
        'path',
        help: 'Path to project',
      );
  }

  @override
  String get description => 'Run a script in a pubspec.yaml file';

  @override
  String get name => 'run';

  final Logger _logger;

  @override
  Future<int> run() async {
    var workingPath = argResults!['path'] as String?;
    final quiet = argResults!['quiet'] as bool? ?? false;
    final parallel = argResults!['parallel'] as bool? ?? false;

    // Get script working path
    workingPath ??= Directory.current.path;

    final file = File('$workingPath/pubspec.yaml');
    if (!file.existsSync()) {
      _logger.err('pubspec.yaml not found!');
      return ExitCode.software.code;
    }
    final doc = loadYaml(file.readAsStringSync()) as YamlMap;
    // Scripts
    final scripts = doc['scripts'] as YamlMap?;
    if (scripts == null) {
      _logger.err('No scripts key found!');
      return ExitCode.software.code;
    }
    final commandMap = <String, dynamic>{};
    scripts.forEach((key, value) {
      commandMap[key as String] = value;
    });
    var command = argResults!['command'] as String?;
    if (command == null) {
      // Select a command
      _logger.info('Select a command');
      final commands = commandMap.keys.toList();
      if (commands.isEmpty) {
        _logger.err('No commands found!');
        return ExitCode.software.code;
      }
      final menu = Menu(commands.toList());
      final result = menu.choose();
      command = result.value;
    }
    // Run command
    final commandValue = commandMap[command];
    if (commandValue == null) {
      _logger.err('Command not valid!');
      return ExitCode.software.code;
    }

    final logging = quiet ? null : _logger;
    return runDynamic(
      command,
      commandValue,
      logging,
      workingPath,
      parallel,
    );
  }
}

Future<int> runDynamic(
  String command,
  dynamic value,
  Logger? _logger,
  String workingPath,
  bool parallel,
) async {
  if (value is String) {
    await runCommands(
      command,
      getSubCommands(value),
      workingPath,
      _logger,
      parallel,
    );
    return ExitCode.success.code;
  }
  if (value is YamlList) {
    final expandedCommands = <String>[];
    for (final command in value) {
      expandedCommands.addAll(getSubCommands(command));
    }
    await runCommands(
      command,
      expandedCommands,
      workingPath,
      _logger,
      parallel,
    );
    return ExitCode.success.code;
  }
  _logger?.err('Invalid command type: $command -> ${value.runtimeType}');
  return ExitCode.software.code;
}

List<String> getSubCommands(dynamic value) {
  final subCommands = <String>[];
  if (value is String) {
    for (final item in value.split(' && ')) {
      subCommands.add(item.trim());
    }
  }
  return subCommands;
}

Future<void> runCommands(
  String command,
  List<String> commands,
  String path,
  Logger? _logger,
  bool parallel,
) async {
  if (parallel) {
    _logger?.info('Running: $command in parallel');
    final futures = <Future<void>>[];
    for (final command in commands) {
      futures.add(runCommand(command, path, _logger));
    }
    await Future.wait(futures);
    return;
  }
  var idx = 0;
  for (final item in commands) {
    final counter = '${idx + 1}/${commands.length}';
    _logger?.info('Running: $command -> $item ($counter)');
    await runCommand(item, path, _logger);
    idx++;
  }
}

Future<void> runCommand(
  String command,
  String path,
  Logger? _logger,
) async {
  final parts = command.split(' ');
  // Run command in process
  final process = await Process.start(
    parts[0],
    parts.length > 1 ? parts.skip(1).toList() : [],
    workingDirectory: path,
  );
  process.stdout.transform(utf8.decoder).listen(_logger?.info);
  process.stderr.transform(utf8.decoder).listen(_logger?.err);
  await process.exitCode;
}
