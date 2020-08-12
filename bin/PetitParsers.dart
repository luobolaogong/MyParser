import 'package:logging/logging.dart';
import 'package:petitparser/petitparser.dart';

import 'Note.dart';

class PetitParsers {
  var noteParser;
  final log = Logger('MyMidiWriter');
  // This seems bad:
  //Note fillInThisNote; // create as needed.  Correct?????????????????????

  ///
  /// Define and initialize the petit parsers.
  ///
  PetitParsers() {
    //
    // ArticulationParser
    //
    final articulationParser =
    pattern('>^').map((value, {hasSideEffects = true}) {
      NoteArticulation noteArticulation;
      switch (value) {
        case '>':
          noteArticulation = NoteArticulation.accent;
          break;
        case '^':
          noteArticulation = NoteArticulation.bigAccent;
          break;
      }
      log.info('In ArticulationParser, and value is ${value} and fillInThisNote.articulation is ${noteArticulation}');
      return noteArticulation;
    });

    //
    // WholeNumberParser
    //
    // what the heck, does this thing get called?  It should, but I don't see it happening.
    final wholeNumberParser =
    digit().plus().flatten().trim().map((value, {hasSideEffects = true}) {
      final theWholeNumber = int.parse(value);
      log.info(
          'Hey, in wholeNumberParser, and returning $theWholeNumber, and that is NOT a number: ${theWholeNumber.isNaN}');
      log.info('In WholeNumberParser, and value is ${value} and returning ${theWholeNumber}');
      return theWholeNumber;
    });

    //
    // DurationParser
    //
    final durationParser =
    (wholeNumberParser & (char(':') & wholeNumberParser).optional())
        .map((value, {hasSideEffects = true}) {
      var noteDuration= NoteDuration();

      noteDuration.firstNumber = value[0];
      if (value.length == 3) {
        noteDuration.secondNumber = value[2];
      }
      log.info('In DurationParser, and value is ${value} and returning duration ${noteDuration.describe()}');
      return noteDuration; // experiment 8/11/20  but who receives this?
//      return fillInThisNote.duration; // experiment 8/11/20  but who receives this?
    });

    //
    // NoteTypeParser
    //
    final noteTypeParser =
    pattern('TtFfDdZzr.').map((value, {hasSideEffects = true}) {
      NoteType noteType;
      switch (value[0]) {
        case 'T':
          noteType = NoteType.rightTap;
          break;
        case 't':
          noteType = NoteType.leftTap;
          break;
        case 'F':
          noteType = NoteType.rightFlam;
          break;
        case 'f':
          noteType = NoteType.leftFlam;
          break;
        case 'D':
          noteType = NoteType.rightDrag;
          break;
        case 'd':
          noteType = NoteType.leftDrag;
          break;
        case 'Z': // maybe change to a B so that we can use Z for a "Tuz"? (tap buzz)
          noteType = NoteType.rightBuzz;
          break;
        case 'z':
          noteType = NoteType.leftBuzz;
          break;
        case 'r':
          noteType = NoteType.rest;
          break;
        case '.':
          noteType = NoteType.previousNoteDurationOrType;
          break;
        default:
          log.fine(
              'Hey, this shoulda been a failure cause got -->${value[0]}<-- and will return null');
          break;
      }
      log.info('In NoteTypeParser and value is ${value} and noteType is ${noteType}');
      return noteType; // experiment 8/11/20
    });

    //
    // NoteParser, the root one, I think.
    //
    noteParser = (articulationParser.optional() & durationParser.optional() & noteTypeParser.optional())
        .map((value, {hasSideEffects = true}) {
      var note = Note();
      note.articulation = value[0];
      note.duration = value[1];
      note.type = value[2];
      return note; // this is the resulting object that gets returned by calling this parser, in the Result.value field, kluged by descendant parsers
    });
  }
}