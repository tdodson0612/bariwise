//lib/logger.dart

import 'package:logger/logger.dart';

final logger = Logger(
  printer: PrettyPrinter(
    methodCount: 1, // number of stack trace lines
    errorMethodCount: 5, // error stack trace lines
    lineLength: 80, // width of log lines
    colors: true, // enable colors
    printEmojis: true, // enable emojis
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart, // replaces printTime: true
  ),
);