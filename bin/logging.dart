//import 'package:logging/logging.dart';
//
//// create Logger by name 'MyApp'
//final log = Logger('MyApp');
//void initLogging() {
//  // disable hierarchical logger
//  hierarchicalLoggingEnabled = false;
//  // change to another level as needed.
//  Logger.root.level = Level.INFO;
//  // skip logging stactrace below the SEVERE level.
//  recordStackTraceAtLevel = Level.SEVERE;
//  assert(() {
//    recordStackTraceAtLevel = Level.WARNING;
//    // print all logs on debug build.
//    Logger.root.level = Level.ALL;
//    return true;
//  }());
//}
//
//Logger.root.onRecord.listen((event) {
//print("${event.time}: [${event.level}] [${event.loggerName}] ${event.message}");
//});
