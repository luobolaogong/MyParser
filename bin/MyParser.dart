//import 'package:MyParser/MyParser.dart' as MyParser;
import 'dart:io';

import 'package:args/args.dart';
import 'package:dart_midi/dart_midi.dart';
import 'package:petitparser/petitparser.dart';
//import 'logging.dart';
import 'package:logging/logging.dart';

import 'MyMidiWriter.dart';
import 'Note.dart';

void main(List<String> arguments) {
  Logger.root.level = Level.SHOUT;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });
  final log = Logger('MyParser');

  //
  // Handle command line args/options/flags
  //
  const pieces = 'pieces';
  const files = 'files';
  const midi = 'midi';
  var now = DateTime.now();
  ArgResults argResults;
  var timeStampedMidiOutCurDirName =
      'Tune${now.year}${now.month}${now.day}${now.hour}${now.minute}.midi';
  final parser = ArgParser()
    ..addMultiOption(pieces,
        abbr: 'p',
        help:
            'List as many input SnareLang input pieces/files you want, separated by commas, without spaces.',
        valueHelp: '<path1>,<path2>,...')
    ..addMultiOption(files,
        abbr: 'f',
        help:
            'List as many input SnareLang input files/pieces you want, separated by commas, without spaces.',
        valueHelp: '<path1>,<path2>,...')
    ..addOption(midi,
        abbr: 'm',
        defaultsTo: timeStampedMidiOutCurDirName,
        help:
            'This is the output midi file name and path.  Defaults to "Tune<dateAndTime>.midi"');
    // how do you add a --help option?
  argResults = parser.parse(arguments);

  if (argResults.rest.isNotEmpty) {
    print('Ignoring command line arguments: -->${argResults.rest}<-- and aborting ...');
    print('Usage:\n${parser.usage}');
    print(
        'Example: <thisProg> -p Tunes/BadgeOfScotland.snl,Tunes/RowanTree.snl,Tunes/ScotlandTheBrave.snl --midi midifiles/BadgeSet.mid');
    exitCode = 2; // does anything?
    return;
  }
  // Since allow for different args to do same thing, combine them.
  var piecesOfMusic = [...argResults[pieces], ...argResults[files]];

  // Set up lists of notes which will be gathered.  Currently we're going to concatenate notes (trackEvents) from all files
  // listed, and place them in one track that gets written as part of the midi file.
  List<Note> notes = []; // don't change this to var because that's "dynamic"
  List<Note> notesAllTunesInList = [];



  //
  // DEFINE PARSERS
  // Seems that the following stuff should be in a file of its own.  The parsers
  // Define the PetitParsers
  //
  var fillInThisNote = Note(); // create as needed.  Correct?????????????????????


  final articulationParser =
      pattern('>^').map((value, {hasSideEffects = true}) {
//    print(
//        'in articulationParser.map() and articulation value is ->${value}<--');
    switch (value) {
      case '>':
        fillInThisNote.articulation = NoteArticulation.accent;
        break;
      case '^':
        fillInThisNote.articulation = NoteArticulation.bigAccent;
        break;
    }
  });

  // what the heck, does this thing get called?  It should, but I don't see it happening.
  final wholeNumberParser =
      digit().plus().flatten().trim().map((value, {hasSideEffects = true}) {
    final theWholeNumber = int.parse(value);
    log.fine(
        'Hey, in wholeNumberParser, and returning $theWholeNumber, and that is NOT a number: ${theWholeNumber.isNaN}');
    return theWholeNumber; // new and probably useless
  });

  final durationParser =
      (wholeNumberParser & (char(':') & wholeNumberParser).optional())
          .flatten('somekineflattenproblem')
          .trim()
          .map((value, {hasSideEffects = true}) {
    var parts = value.split(':');
    fillInThisNote.duration.firstNumber = int.parse(parts[0]);
    if (parts.length == 2) {
      fillInThisNote.duration.secondNumber = int.parse(parts[1]);
    }
  });

  final noteTypeParser =
      pattern('TtFfDdZz.').map((value, {hasSideEffects = true}) {
    switch (value[0]) {
      case 'T':
        fillInThisNote.type = NoteType.rightTap;
        break;
      case 't':
        fillInThisNote.type = NoteType.leftTap;
        break;
      case 'F':
        fillInThisNote.type = NoteType.rightFlam;
        break;
      case 'f':
        fillInThisNote.type = NoteType.leftFlam;
        break;
      case 'D':
        fillInThisNote.type = NoteType.rightDrag;
        break;
      case 'd':
        fillInThisNote.type = NoteType.leftDrag;
        break;
      case 'Z': // maybe change to a B so that we can use Z for a "Tuz"? (tap buzz)
        fillInThisNote.type = NoteType.rightBuzz;
        break;
      case 'z':
        fillInThisNote.type = NoteType.leftBuzz;
        break;
      case '.':
        fillInThisNote.type = NoteType.previousNoteDurationOrType;
        break;
      default:
        log.fine(
            'Hey, this shoulda been a failure cause got -->${value[0]}<-- and will return null');
        break;
    }
  });

  final noteParser = (articulationParser.optional() &
          durationParser.optional() &
          noteTypeParser.optional())
      .flatten()
      .trim()
      .map((value, {hasSideEffects = true}) {
    return fillInThisNote; // how about returning an object?  This does trickle up to the value of noteParser when called
  });







  //
  // TAKE CARE OF MIDIFILE HEADER
  //

  //  final ticksPerBeat = 480;
  final ticksPerBeat = 10080;
//  final ticksPerBeat = 840;
  final bpm = 98;
  final numerator = 4;
  final denominator = 4;

  // So now we've got a list of updated notes based on previous notes, which is what we need to
  // write midi.
  var myMidiWriter = MyMidiWriter();
  var midiHeaderOut =  myMidiWriter.fillInHeader(ticksPerBeat); // 840 ticks per beat seems good





  //
  // Loop through each piece of music listed on command line and collect all trackEvents.
  // Currently all of them are noteOn or noteOff events, but in near future will have tempos
  // and time signatures, and dynamics, and repeats, and ...
  //
  List<String> textNotesList;
  for (var piece in piecesOfMusic) {
    print('Processing input file: $piece ...');
    var inputFile = File(piece);
    if (!inputFile.existsSync()) {
      print('File does not exist at ${inputFile.path}');
      continue;
    }
    var fileContents = inputFile.readAsStringSync(); // per line better?
    if (fileContents.length == 0) {
      continue;
    }
    //
    // Break the tune into a list of SnareLang notes delimited by white
    //
    textNotesList = fileContents.split(RegExp(r'\s+'));
//    final textNotesList = fileContents.split(RegExp(r'\s+'));

    //
    // Run through each SnareLang note, and call the parser on it and generate a
    // note object, and if successful add the object to a list of objects.
    //
    Note note;
    textNotesList.forEach((textNote) {
      final result = noteParser.parse(textNote);
//      print('wowowow textNote is $textNote and result from parse is ${result.value.duration.firstNumber}');
      if (result.isFailure || result.position == 0 || result.buffer == '') {
        log.fine('textNote is not a note, it is -->$textNote<--');
      }
      else {
//        print('Hodelly, just parsed $textNote and result.value.duration.firstNumber is ${result.value.duration.firstNumber}');
        // evidentally, result.value is not the same thing as a Note, even though it looks like it.
        // So, have to create and copy the values in.
        note = Note();
        note.articulation = result.value.articulation;
        note.duration.firstNumber = result.value.duration.firstNumber;
        note.duration.secondNumber = result.value.duration.secondNumber;
        note.type = result.value.type;
        notes.add(note);
//        notes.add(result.value); // result.value should be a Note object  IS THIS RIGHT?????????????????????????????????
      }
//      if (result.isSuccess &&
//          result.value != null &&  // null or '' ?
//          result.buffer != '' &&
//          result.position == textNote.length) {
//        notes.add(result.value); // result.value should be a Note object
//      } else { // failure is position is 0, or buffer is ""
//        log.fine('logged this in MyParser.dart ... should be failure and skip this note -->${textNote}<-- because result is whatever it is, take alook');
//      }
    });
    textNotesList.clear();






    //
    // Apply the shortcuts, like ".", and apply hand order changes.
    // This requires keeping track of previous note.
    //
    var previousDurationFirstNumber = 4; // strange
    var previousDurationSecondNumber = 4;
    var previousArticulation;
    var previousType = NoteType.leftTap; // will change to right.  Bad logic?
    //log.fine('Here are the ${notes.length} note objects:');
    notes.forEach((note) {
//      print('holy smokes note.duration.firstNumber is ${note.duration.firstNumber}');
      previousArticulation = (note.articulation == null) ? previousArticulation : note.articulation;
      if (note.articulation == null) {
        previousArticulation = note.articulation;
      }
      // We want to keep track of the current duration and type (and not articulation)
      // so that if either of those are missing, we just use the previous note's
      // duration and type.  So, we need to make sure that "previous" values of
      // duration and type are updated after we're done using them.
      // So, if current duration is null, set it to be the previous duration,
      // else update previous.  Do the same for Type, but not Articulation.
      // Also, if the type isn't specified then the opposite hand should be
      // specified if it's a tap, flam, drag, buzz, or tapRoll

// Do we need to do anything with durations?  They seem to be right already after the parse for some reason
//      print('Previous note duration: ${previousDurationFirstNumber}:${previousDurationSecondNumber}');
//      if (note.duration == null || note.duration.firstNumber == null) {
//        note.duration.firstNumber = previousDurationFirstNumber;
//        note.duration.secondNumber = previousDurationSecondNumber;
//      } else {
//        previousDurationFirstNumber = note.duration.firstNumber;
//        previousDurationSecondNumber = note.duration.secondNumber;
//        print('Updated, now Previous note duration: ${previousDurationFirstNumber}:${previousDurationSecondNumber}');
//      }
      // Swap the hand order for the note if the type is not specified.
      // Following is bad logic.  What if first note is "."?  Then default is T, but then that gets changed to t
      if (note.type == null || note.type == NoteType.previousNoteDurationOrType) {
        // check the following.  And change to a switch?  Also should be a faster way to flip the bit between left and right
        note.type = previousType;
        if (note.type == NoteType.rightTap) {
          note.type = NoteType.leftTap;
        } else if (note.type == NoteType.leftTap) {
          note.type = NoteType.rightTap;
        } else if (note.type == NoteType.rightFlam) {
          note.type = NoteType.leftFlam;
        } else if (note.type == NoteType.leftFlam) {
          note.type = NoteType.rightFlam;
        } else if (note.type == NoteType.rightDrag) {
          note.type = NoteType.leftDrag;
        } else if (note.type == NoteType.leftDrag) {
          note.type = NoteType.rightDrag;
        } else if (note.type == NoteType.rightBuzz) {
          note.type = NoteType.leftBuzz;
        } else if (note.type == NoteType.leftBuzz) {
          note.type = NoteType.rightBuzz;
        } else if (note.type == NoteType.rightTapRoll) {
          // TapRoll should be a "Tuz", maybe and the timing is different for Tuzzes. or handorder, as in XZz rather than TzZ
          note.type = NoteType.leftTapRoll;
        } else if (note.type == NoteType.leftTapRoll) {
          note.type = NoteType.rightTapRoll;
        }
        previousType = note.type; // ?????
      } else {
        previousType = note.type;
      }
    });
    notesAllTunesInList.addAll(notes); // how many times does this happen?
    notes.clear(); // new
  }

  var tracks = myMidiWriter.fillInTracks(
      numerator, denominator, bpm, ticksPerBeat, notesAllTunesInList);

  // Add the header and tracks list into a MidiFile, and write it
  var midiFileOut = MidiFile(tracks, midiHeaderOut);
  var midiWriterCopy = MidiWriter();
  var midiFileOutFile = File(argResults[midi]);
  midiWriterCopy.writeMidiToFile(midiFileOut, midiFileOutFile);
  print('Done writing midifile ${midiFileOutFile.path}');
}
