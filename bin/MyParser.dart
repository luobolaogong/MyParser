//import 'package:MyParser/MyParser.dart' as MyParser;
import 'dart:io';

import 'package:args/args.dart';
import 'package:dart_midi/dart_midi.dart';
import 'package:petitparser/petitparser.dart';
//import 'logging.dart';
import 'package:logging/logging.dart';

import 'MyMidiWriter.dart';
import 'PetitParsers.dart';
import 'Note.dart';

void main(List<String> arguments) {

  //
  // Set up logging
  //
  Logger.root.level = Level.INFO;
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
  List<String> piecesOfMusic = [...argResults[pieces], ...argResults[files]]; // can't change to var

  // Read SnareLang notes from all files specified, and process them
  // into a list of Note objects
  var notes = getNotesFromTextNoteFiles(piecesOfMusic, log);

  // Apply shortcuts to the list of Note objects to have all their properties so
  // that noteOn and noteOff midi events can be more easily created.
  // Every note needs a duration.
  applyShortcuts(notes);

  final ticksPerBeat = 10080;
  //  final ticksPerBeat = 840;
  //  final ticksPerBeat = 480;

  // Create Midi header
  var myMidiWriter = MyMidiWriter();
  var midiHeaderOut =  myMidiWriter.fillInHeader(ticksPerBeat); // 840 ticks per beat seems good


  // Create Midi tracks
  final bpm = 82;
  final numerator = 4;
  final denominator = 4;
  final nominalVolume = 50;
  var tracks = myMidiWriter.fillInTracks(numerator, denominator, bpm, ticksPerBeat, notes, nominalVolume);


  // Add the header and tracks list into a MidiFile, and write it
  var midiFileOut = MidiFile(tracks, midiHeaderOut);
  var midiWriterCopy = MidiWriter();
  var midiFileOutFile = File(argResults[midi]);
  midiWriterCopy.writeMidiToFile(midiFileOut, midiFileOutFile); // will crash here
  print('Done writing midifile ${midiFileOutFile.path}');
}

List<Note> getNotesFromTextNoteFiles(List<String> piecesOfMusic, Logger log) {
  List<String> textNotesList;
  List<Note> notes = []; // don't change this to var because that's "dynamic"
  //
  // Loop through each piece of music listed on command line and collect all trackEvents.
  // Currently all of them are noteOn or noteOff events, but in near future will have tempos
  // and time signatures, and dynamics, and repeats, and ...
  //
  // Is it better to process a file at a time and for each one add noteOn and noteOff events
  // to a list which eventually gets written to a midi file, or is it better to merge the
  // contents of the text files into one big string of text notes, and then process them once
  // to create the track events?  Seems easier to do it by merging files up front.
  //
  // Would that complicate things if each file has its own tempos and time signatures and
  // repeats and things?  I don't think so.  So I think I'm going to change the way this is
  // done currently.
  //
  var contentsOfAllSnareLangTextFiles = StringBuffer();
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
    contentsOfAllSnareLangTextFiles.write(fileContents);
  }

  //
  // Break the tune into a list of SnareLang notes delimited by white
  //
  textNotesList = contentsOfAllSnareLangTextFiles.toString().split(RegExp(r'\s+'));

  // Create note parser
  var petitParsers = PetitParsers();
  var noteParser = petitParsers.noteParser;

  //
  // Run through each SnareLang note, and call the parser on it and generate a
  // note object, and if successful add the object to a list of objects.
  // Hey, before adding it to the list, why not process it to handle shortcuts
  // and also volumes?
  //
  Note note;
  textNotesList.forEach((textNote) {
    final result = noteParser.parse(textNote); // This is the top parser, right?  It returns a Note that has a value that's a Note, or it should.
    if (result.isFailure || result.position == 0 || result.buffer == '') {
      log.fine('textNote is not a note, it is -->$textNote<--');
    }
    else {
      note = Note();
      note = result.value; // IS THIS CORREC?  ALWAYS A NOTE?  AND ALWAYS HAS A DURATION?????????
      log.info('In loop and just created a Note based on the result of calling noteParser on ${textNote},  ${note.describe()}\n');
      notes.add(note);
    }
  });
  return notes;
}

///
/// Apply shortcuts, meaning that missing properties of duration and type for a text note get filled in from the previous
/// note.  This would include notes specified by ".", which means use previous note's duration and type.  This will be
/// expanded to volume/velocity later.
/// Also, when the note type is not specified, swap hand order from the previous note.
///
void applyShortcuts(List<Note> notes) {
  //var previousType = NoteType.leftTap; // will change to right.  Bad logic?
  Note note;
  Note previousNote = notes[0];
  for (var noteCtr = 0; noteCtr < notes.length; noteCtr++) {
    note = notes[noteCtr];
    if (noteCtr > 1) {
      previousNote = notes[noteCtr - 1];
    }
    if (note.duration == null || note.type == NoteType.previousNoteDurationOrType) {
      note.duration = previousNote.duration;
    }
    if (note.type == null || note.type == NoteType.previousNoteDurationOrType) {
      note.type = previousNote.type;
      // Also swap hands
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
    }
    if (note.velocity == null || note.velocity == NoteType.previousNoteDurationOrType) {
      note.velocity = previousNote.velocity;
    }
  }
  return;
}