// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'clipboard_utils.dart';

Future<void> sendKeyCombination(
  WidgetTester tester,
  SingleActivator activator,
) async {
  final List<LogicalKeyboardKey> modifiers = <LogicalKeyboardKey>[
    if (activator.control) LogicalKeyboardKey.control,
    if (activator.shift) LogicalKeyboardKey.shift,
    if (activator.alt) LogicalKeyboardKey.alt,
    if (activator.meta) LogicalKeyboardKey.meta,
  ];
  for (final LogicalKeyboardKey modifier in modifiers) {
    await tester.sendKeyDownEvent(modifier);
  }
  await tester.sendKeyDownEvent(activator.trigger);
  await tester.sendKeyUpEvent(activator.trigger);
  await tester.pump();
  for (final LogicalKeyboardKey modifier in modifiers.reversed) {
    await tester.sendKeyUpEvent(modifier);
  }
}

Iterable<SingleActivator> allModifierVariants(LogicalKeyboardKey trigger) {
  const Iterable<bool> trueFalse = <bool>[false, true];
  return trueFalse.expand((bool shift) {
    return trueFalse.expand((bool control) {
      return trueFalse.expand((bool alt) {
        return trueFalse.map((bool meta) => SingleActivator(trigger, shift: shift, control: control, alt: alt, meta: meta));
      });
    });
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final MockClipboard mockClipboard = MockClipboard();

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, mockClipboard.handleMethodCall);
    await Clipboard.setData(const ClipboardData(text: 'empty'));
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  const String testText =
      'Now is the time for\n' // 20
      'all good people\n'     // 20 + 16 => 36
      'to come to the aid\n'  // 36 + 19 => 55
      'of their country.';    // 55 + 17 => 72
  const String testCluster = '👨‍👩‍👦👨‍👩‍👦👨‍👩‍👦'; // 8 * 3

  // Exactly 20 characters each line.
  const String testSoftwrapText =
      '0123456789ABCDEFGHIJ'
      '0123456789ABCDEFGHIJ'
      '0123456789ABCDEFGHIJ'
      '0123456789ABCDEFGHIJ';
  final TextEditingController controller = TextEditingController(text: testText);

  final FocusNode focusNode = FocusNode();
  Widget buildEditableText({
    TextAlign textAlign = TextAlign.left,
    bool readOnly = false,
    bool obscured = false,
    TextStyle style = const TextStyle(fontSize: 10.0),
  }) {
    return MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          // Softwrap at exactly 20 characters.
          width: 201,
          height: 200,
          child: EditableText(
            controller: controller,
            showSelectionHandles: true,
            autofocus: true,
            focusNode: focusNode,
            style: style,
            textScaleFactor: 1,
            // Avoid the cursor from taking up width.
            cursorWidth: 0,
            cursorColor: Colors.blue,
            backgroundCursorColor: Colors.grey,
            selectionControls: materialTextSelectionControls,
            keyboardType: TextInputType.text,
            maxLines: obscured ? 1 : null,
            readOnly: readOnly,
            textAlign: textAlign,
            obscureText: obscured,
          ),
        ),
      ),
    );
  }

  testWidgets(
    'Movement/Deletion shortcuts do nothing when the selection is invalid',
    (WidgetTester tester) async {
      await tester.pumpWidget(buildEditableText());
      controller.text = testText;
      controller.selection = const TextSelection.collapsed(offset: -1);
      await tester.pump();

      const List<LogicalKeyboardKey> triggers = <LogicalKeyboardKey>[
        LogicalKeyboardKey.backspace,
        LogicalKeyboardKey.delete,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.end,
      ];

      for (final SingleActivator activator in triggers.expand(allModifierVariants)) {
        await sendKeyCombination(tester, activator);
        await tester.pump();
        expect(controller.text, testText, reason: activator.toString());
        expect(controller.selection, const TextSelection.collapsed(offset: -1), reason: activator.toString());
      }
    },
    skip: kIsWeb, // [intended] on web these keys are handled by the browser.
    variant: TargetPlatformVariant.all(),
  );

  group('Common text editing shortcuts: ',
    () {
      final TargetPlatformVariant allExceptApple = TargetPlatformVariant.all(excluding: <TargetPlatform>{TargetPlatform.macOS, TargetPlatform.iOS});

      group('backspace', () {
        const LogicalKeyboardKey trigger = LogicalKeyboardKey.backspace;

        testWidgets('backspace', (WidgetTester tester) async {
          controller.text = testText;
          // Move the selection to the beginning of the 2nd line (after the newline
          // character).
          controller.selection = const TextSelection.collapsed(
            offset: 20,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, const SingleActivator(trigger));

          expect(
            controller.text,
            'Now is the time forall good people\n'
            'to come to the aid\n'
            'of their country.',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 19),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('backspace readonly', (WidgetTester tester) async {
          controller.text = testText;
          controller.selection = const TextSelection.collapsed(
            offset: 20,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText(readOnly: true));
          await sendKeyCombination(tester, const SingleActivator(trigger));

          expect(controller.text, testText);

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 20, affinity: TextAffinity.upstream),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('backspace at start', (WidgetTester tester) async {
          controller.text = testText;
          controller.selection = const TextSelection.collapsed(
            offset: 0,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, const SingleActivator(trigger));

          expect(
            controller.text,
            'Now is the time for\n'
            'all good people\n'
            'to come to the aid\n'
            'of their country.',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 0),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('backspace at end', (WidgetTester tester) async {
          controller.text = testText;
          controller.selection = const TextSelection.collapsed(
            offset: 72,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, const SingleActivator(trigger));

          expect(
            controller.text,
            'Now is the time for\n'
            'all good people\n'
            'to come to the aid\n'
            'of their country',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 71),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('backspace inside of a cluster', (WidgetTester tester) async {
          controller.text = testCluster;
          controller.selection = const TextSelection.collapsed(
            offset: 1,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, const SingleActivator(trigger));

          expect(
            controller.text,
            '👨‍👩‍👦👨‍👩‍👦',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 0),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('backspace at cluster boundary', (WidgetTester tester) async {
          controller.text = testCluster;
          controller.selection = const TextSelection.collapsed(
            offset: 8,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, const SingleActivator(trigger));

          expect(
            controller.text,
            '👨‍👩‍👦👨‍👩‍👦',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 0),
          );
        }, variant: TargetPlatformVariant.all());
      });

      group('delete: ', () {
        const LogicalKeyboardKey trigger = LogicalKeyboardKey.delete;

        testWidgets('delete', (WidgetTester tester) async {
          controller.text = testText;
          // Move the selection to the beginning of the 2nd line (after the newline
          // character).
          controller.selection = const TextSelection.collapsed(
            offset: 20,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, const SingleActivator(trigger));

          expect(
            controller.text,
            'Now is the time for\n'
            'll good people\n'
            'to come to the aid\n'
            'of their country.',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 20),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('delete readonly', (WidgetTester tester) async {
          controller.text = testText;
          controller.selection = const TextSelection.collapsed(
            offset: 20,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText(readOnly: true));
          await sendKeyCombination(tester, const SingleActivator(trigger));

          expect(controller.text, testText);

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 20, affinity: TextAffinity.upstream),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('delete at start', (WidgetTester tester) async {
          controller.text = testText;
          controller.selection = const TextSelection.collapsed(
            offset: 0,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, const SingleActivator(trigger));

          expect(
            controller.text,
            'ow is the time for\n'
            'all good people\n'
            'to come to the aid\n'
            'of their country.',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 0),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('delete at end', (WidgetTester tester) async {
          controller.text = testText;
          controller.selection = const TextSelection.collapsed(
            offset: 72,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, const SingleActivator(trigger));

          expect(
            controller.text,
            'Now is the time for\n'
            'all good people\n'
            'to come to the aid\n'
            'of their country.',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 72, affinity: TextAffinity.upstream),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('delete inside of a cluster', (WidgetTester tester) async {
          controller.text = testCluster;
          controller.selection = const TextSelection.collapsed(
            offset: 1,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, const SingleActivator(trigger));

          expect(
            controller.text,
            '👨‍👩‍👦👨‍👩‍👦',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 0),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('delete at cluster boundary', (WidgetTester tester) async {
          controller.text = testCluster;
          controller.selection = const TextSelection.collapsed(
            offset: 8,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, const SingleActivator(trigger));

          expect(
            controller.text,
            '👨‍👩‍👦👨‍👩‍👦',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 8),
          );
        }, variant: TargetPlatformVariant.all());
      });

      group('Non-collapsed delete', () {
        // This shares the same logic as backspace.
        const LogicalKeyboardKey trigger = LogicalKeyboardKey.delete;

        testWidgets('inside of a cluster', (WidgetTester tester) async {
          controller.text = testCluster;
          controller.selection = const TextSelection(
            baseOffset: 9,
            extentOffset: 12,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, const SingleActivator(trigger));

          expect(
            controller.text,
            '👨‍👩‍👦👨‍👩‍👦',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 8),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('at the boundaries of a cluster', (WidgetTester tester) async {
          controller.text = testCluster;
          controller.selection = const TextSelection(
            baseOffset: 8,
            extentOffset: 16,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, const SingleActivator(trigger));

          expect(
            controller.text,
            '👨‍👩‍👦👨‍👩‍👦',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 8),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('cross-cluster', (WidgetTester tester) async {
          controller.text = testCluster;
          controller.selection = const TextSelection(
            baseOffset: 1,
            extentOffset: 9,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, const SingleActivator(trigger));

          expect(
            controller.text,
            '👨‍👩‍👦',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 0),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('cross-cluster obscured text', (WidgetTester tester) async {
          controller.text = testCluster;
          controller.selection = const TextSelection(
            baseOffset: 1,
            extentOffset: 9,
          );

          await tester.pumpWidget(buildEditableText(obscured: true));
          await sendKeyCombination(tester, const SingleActivator(trigger));

          expect(
            controller.text,
            '👨‍👩‍👦👨‍👩‍👦',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 1),
          );
        }, variant: TargetPlatformVariant.all());
      });

      group('word modifier + backspace', () {
        const LogicalKeyboardKey trigger = LogicalKeyboardKey.backspace;
        SingleActivator wordModifierBackspace() {
          final bool isApple = defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;
          return SingleActivator(trigger, control: !isApple, alt: isApple);
        }

        testWidgets('WordModifier-backspace', (WidgetTester tester) async {
          controller.text = testText;
          // Place the caret before "people".
          controller.selection = const TextSelection.collapsed(
            offset: 29,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, wordModifierBackspace());

          expect(
            controller.text,
            'Now is the time for\n'
            'all people\n'
            'to come to the aid\n'
            'of their country.',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 24),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('readonly', (WidgetTester tester) async {
          controller.text = testText;
          controller.selection = const TextSelection.collapsed(
            offset: 29,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText(readOnly: true));
          await sendKeyCombination(tester, wordModifierBackspace());

          expect(controller.text, testText);

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 29, affinity: TextAffinity.upstream),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('at start', (WidgetTester tester) async {
          controller.text = testText;
          controller.selection = const TextSelection.collapsed(
            offset: 0,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, wordModifierBackspace());

          expect(
            controller.text,
            'Now is the time for\n'
            'all good people\n'
            'to come to the aid\n'
            'of their country.',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 0),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('at end', (WidgetTester tester) async {
          controller.text = testText;
          controller.selection = const TextSelection.collapsed(
            offset: 72,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, wordModifierBackspace());

          expect(
            controller.text,
            'Now is the time for\n'
            'all good people\n'
            'to come to the aid\n'
            'of their country',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 71),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('inside of a cluster', (WidgetTester tester) async {
          controller.text = testCluster;
          controller.selection = const TextSelection.collapsed(
            offset: 1,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, wordModifierBackspace());

          expect(
            controller.text,
            '👨‍👩‍👦👨‍👩‍👦',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 0),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('at cluster boundary', (WidgetTester tester) async {
          controller.text = testCluster;
          controller.selection = const TextSelection.collapsed(
            offset: 8,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, wordModifierBackspace());

          expect(
            controller.text,
            '👨‍👩‍👦👨‍👩‍👦',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 0),
          );
        }, variant: TargetPlatformVariant.all());
      });

      group('word modifier + delete', () {
        const LogicalKeyboardKey trigger = LogicalKeyboardKey.delete;
        SingleActivator wordModifierDelete() {
          final bool isApple = defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;
          return SingleActivator(trigger, control: !isApple, alt: isApple);
        }

        testWidgets('WordModifier-delete', (WidgetTester tester) async {
          controller.text = testText;
          // Place the caret after "all".
          controller.selection = const TextSelection.collapsed(
            offset: 23,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, wordModifierDelete());

          expect(
            controller.text,
            'Now is the time for\n'
            'all people\n'
            'to come to the aid\n'
            'of their country.',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 23),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('readonly', (WidgetTester tester) async {
          controller.text = testText;
          controller.selection = const TextSelection.collapsed(
            offset: 23,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText(readOnly: true));
          await sendKeyCombination(tester, wordModifierDelete());

          expect(controller.text, testText);

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 23, affinity: TextAffinity.upstream),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('at start', (WidgetTester tester) async {
          controller.text = testText;
          controller.selection = const TextSelection.collapsed(
            offset: 0,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, wordModifierDelete());

          expect(
            controller.text,
            ' is the time for\n'
            'all good people\n'
            'to come to the aid\n'
            'of their country.',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 0),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('at end', (WidgetTester tester) async {
          controller.text = testText;
          controller.selection = const TextSelection.collapsed(
            offset: 72,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, wordModifierDelete());

          expect(controller.text, testText);
          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 72, affinity: TextAffinity.upstream),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('inside of a cluster', (WidgetTester tester) async {
          controller.text = testCluster;
          controller.selection = const TextSelection.collapsed(
            offset: 1,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, wordModifierDelete());

          expect(
            controller.text,
            '👨‍👩‍👦👨‍👩‍👦',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 0),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('at cluster boundary', (WidgetTester tester) async {
          controller.text = testCluster;
          controller.selection = const TextSelection.collapsed(
            offset: 8,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, wordModifierDelete());

          expect(
            controller.text,
            '👨‍👩‍👦👨‍👩‍👦',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 8),
          );
        }, variant: TargetPlatformVariant.all());
      });

      group('line modifier + backspace', () {
        const LogicalKeyboardKey trigger = LogicalKeyboardKey.backspace;
        SingleActivator lineModifierBackspace() {
          final bool isApple = defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;
          return SingleActivator(trigger, meta: isApple, alt: !isApple);
        }

        testWidgets('alt-backspace', (WidgetTester tester) async {
          controller.text = testText;
          // Place the caret before "people".
          controller.selection = const TextSelection.collapsed(
            offset: 29,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, lineModifierBackspace());

          expect(
            controller.text,
            'Now is the time for\n'
            'people\n'
            'to come to the aid\n'
            'of their country.',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 20),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('softwrap line boundary, upstream', (WidgetTester tester) async {
          controller.text = testSoftwrapText;
          // Place the caret at the beginning of the 3rd line.
          controller.selection = const TextSelection.collapsed(
            offset: 40,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, lineModifierBackspace());

          expect(
            controller.text,
            '0123456789ABCDEFGHIJ'
            '0123456789ABCDEFGHIJ'
            '0123456789ABCDEFGHIJ'
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 20),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('softwrap line boundary, downstream', (WidgetTester tester) async {
          controller.text = testSoftwrapText;
          // Place the caret at the beginning of the 3rd line.
          controller.selection = const TextSelection.collapsed(
            offset: 40,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, lineModifierBackspace());

          expect(controller.text, testSoftwrapText);

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 40),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('readonly', (WidgetTester tester) async {
          controller.text = testText;
          controller.selection = const TextSelection.collapsed(
            offset: 29,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText(readOnly: true));
          await sendKeyCombination(tester, lineModifierBackspace());

          expect(controller.text, testText);

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 29, affinity: TextAffinity.upstream),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('at start', (WidgetTester tester) async {
          controller.text = testText;
          controller.selection = const TextSelection.collapsed(
            offset: 0,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, lineModifierBackspace());

          expect(
            controller.text,
            'Now is the time for\n'
            'all good people\n'
            'to come to the aid\n'
            'of their country.',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 0),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('at end', (WidgetTester tester) async {
          controller.text = testText;
          controller.selection = const TextSelection.collapsed(
            offset: 72,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, lineModifierBackspace());

          expect(
            controller.text,
            'Now is the time for\n'
            'all good people\n'
            'to come to the aid\n'
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 55),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('inside of a cluster', (WidgetTester tester) async {
          controller.text = testCluster;
          controller.selection = const TextSelection.collapsed(
            offset: 1,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, lineModifierBackspace());

          expect(
            controller.text,
            '👨‍👩‍👦👨‍👩‍👦',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 0),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('at cluster boundary', (WidgetTester tester) async {
          controller.text = testCluster;
          controller.selection = const TextSelection.collapsed(
            offset: 8,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, lineModifierBackspace());

          expect(
            controller.text,
            '👨‍👩‍👦👨‍👩‍👦',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 0),
          );
        }, variant: TargetPlatformVariant.all());
      });

      group('line modifier + delete', () {
        const LogicalKeyboardKey trigger = LogicalKeyboardKey.delete;
        SingleActivator lineModifierDelete() {
          final bool isApple = defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;
          return SingleActivator(trigger, meta: isApple, alt: !isApple);
        }

        testWidgets('alt-delete', (WidgetTester tester) async {
          controller.text = testText;
          // Place the caret after "all".
          controller.selection = const TextSelection.collapsed(
            offset: 23,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, lineModifierDelete());

          expect(
            controller.text,
            'Now is the time for\n'
            'all\n'
            'to come to the aid\n'
            'of their country.',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 23),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('softwrap line boundary, upstream', (WidgetTester tester) async {
          controller.text = testSoftwrapText;
          // Place the caret at the beginning of the 3rd line.
          controller.selection = const TextSelection.collapsed(
            offset: 40,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, lineModifierDelete());

          expect(controller.text, testSoftwrapText);

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 40, affinity: TextAffinity.upstream),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('softwrap line boundary, downstream', (WidgetTester tester) async {
          controller.text = testSoftwrapText;
          // Place the caret at the beginning of the 3rd line.
          controller.selection = const TextSelection.collapsed(
            offset: 40,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, lineModifierDelete());

          expect(
            controller.text,
            '0123456789ABCDEFGHIJ'
            '0123456789ABCDEFGHIJ'
            '0123456789ABCDEFGHIJ'
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 40),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('readonly', (WidgetTester tester) async {
          controller.text = testText;
          controller.selection = const TextSelection.collapsed(
            offset: 23,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText(readOnly: true));
          await sendKeyCombination(tester, lineModifierDelete());

          expect(controller.text, testText);

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 23, affinity: TextAffinity.upstream),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('at start', (WidgetTester tester) async {
          controller.text = testText;
          controller.selection = const TextSelection.collapsed(
            offset: 0,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, lineModifierDelete());

          expect(
            controller.text,
            '\n'
            'all good people\n'
            'to come to the aid\n'
            'of their country.',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 0),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('at end', (WidgetTester tester) async {
          controller.text = testText;
          controller.selection = const TextSelection.collapsed(
            offset: 72,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, lineModifierDelete());

          expect(controller.text, testText);
          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 72, affinity: TextAffinity.upstream),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('inside of a cluster', (WidgetTester tester) async {
          controller.text = testCluster;
          controller.selection = const TextSelection.collapsed(
            offset: 1,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, lineModifierDelete());

          expect(
            controller.text,
            isEmpty,
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 0),
          );
        }, variant: TargetPlatformVariant.all());

        testWidgets('at cluster boundary', (WidgetTester tester) async {
          controller.text = testCluster;
          controller.selection = const TextSelection.collapsed(
            offset: 8,
            affinity: TextAffinity.upstream,
          );

          await tester.pumpWidget(buildEditableText());
          await sendKeyCombination(tester, lineModifierDelete());

          expect(
            controller.text,
            '👨‍👩‍👦',
          );

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 8),
          );
        }, variant: TargetPlatformVariant.all());
      });

      group('Arrow Movement', () {
        group('left', () {
          const LogicalKeyboardKey trigger = LogicalKeyboardKey.arrowLeft;

          testWidgets('at start', (WidgetTester tester) async {
            controller.text = testText;
            controller.selection = const TextSelection.collapsed(
              offset: 0,
            );

            await tester.pumpWidget(buildEditableText());

            for (final SingleActivator activator in allModifierVariants(trigger)) {
              await sendKeyCombination(tester, activator);
              await tester.pump();

              expect(
                controller.selection,
                const TextSelection.collapsed(offset: 0),
                reason: activator.toString(),
              );
            }
          }, variant: TargetPlatformVariant.all());

          testWidgets('base arrow key movement', (WidgetTester tester) async {
            controller.text = testText;
            controller.selection = const TextSelection.collapsed(
              offset: 20,
            );
            await tester.pumpWidget(buildEditableText());
            await sendKeyCombination(tester, const SingleActivator(trigger));
            await tester.pump();

            expect(controller.selection, const TextSelection.collapsed(
              offset: 19,
            ));
          }, variant: TargetPlatformVariant.all());

          testWidgets('word modifier + arrow key movement', (WidgetTester tester) async {
            controller.text = testText;
            controller.selection = const TextSelection.collapsed(
              offset: 7,   // Before the first "the"
            );
            await tester.pumpWidget(buildEditableText());
            await sendKeyCombination(tester, const SingleActivator(trigger, control: true));
            await tester.pump();

            expect(controller.selection, const TextSelection.collapsed(
              offset: 4,
            ));
          }, variant: allExceptApple);

          testWidgets('line modifier + arrow key movement', (WidgetTester tester) async {
            controller.text = testText;
            controller.selection = const TextSelection.collapsed(
              offset: 24,   // Before the "good".
            );
            await tester.pumpWidget(buildEditableText());
            await sendKeyCombination(tester, const SingleActivator(trigger, alt: true));
            await tester.pump();

            expect(controller.selection, const TextSelection.collapsed(
              offset: 20,
            ));
          }, variant: allExceptApple);
        });

        group('right', () {
          const LogicalKeyboardKey trigger = LogicalKeyboardKey.arrowRight;

          testWidgets('at end', (WidgetTester tester) async {
            controller.text = testText;
            controller.selection = const TextSelection.collapsed(
              offset: 72,
            );

            await tester.pumpWidget(buildEditableText());

            for (final SingleActivator activator in allModifierVariants(trigger)) {
              await sendKeyCombination(tester, activator);
              await tester.pump();

              expect(controller.selection.isCollapsed, isTrue, reason: activator.toString());
              expect(controller.selection.baseOffset, 72, reason: activator.toString());
            }
          }, variant: TargetPlatformVariant.all());

          testWidgets('base arrow key movement', (WidgetTester tester) async {
            controller.text = testText;
            controller.selection = const TextSelection.collapsed(
              offset: 20,
            );
            await tester.pumpWidget(buildEditableText());
            await sendKeyCombination(tester, const SingleActivator(trigger));
            await tester.pump();

            expect(controller.selection, const TextSelection.collapsed(
              offset: 21,
              affinity: TextAffinity.upstream,
            ));
          }, variant: TargetPlatformVariant.all());

          testWidgets('word modifier + arrow key movement', (WidgetTester tester) async {
            controller.text = testText;
            controller.selection = const TextSelection.collapsed(
              offset: 7,   // Before the first "the"
            );
            await tester.pumpWidget(buildEditableText());
            await sendKeyCombination(tester, const SingleActivator(trigger, control: true));
            await tester.pump();

            expect(controller.selection, const TextSelection.collapsed(
              offset: 10,
              affinity: TextAffinity.upstream,
            ));
          }, variant: allExceptApple);

         testWidgets('line modifier + arrow key movement', (WidgetTester tester) async {
            controller.text = testText;
            controller.selection = const TextSelection.collapsed(
              offset: 24,   // Before the "good".
            );
            await tester.pumpWidget(buildEditableText());
            await sendKeyCombination(tester, const SingleActivator(trigger, alt: true));
            await tester.pump();

            expect(controller.selection, const TextSelection.collapsed(
              offset: 35, // Before the newline character.
              affinity: TextAffinity.upstream,
            ));
          }, variant: allExceptApple);
        });

        group('With initial non-collapsed selection', () {
          testWidgets('base arrow key movement', (WidgetTester tester) async {
            controller.text = testText;
            // The word "all" is selected.
            controller.selection = const TextSelection(
              baseOffset: 20,
              extentOffset: 23,
            );
            await tester.pumpWidget(buildEditableText());
            await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowLeft));
            await tester.pump();

            expect(controller.selection, const TextSelection.collapsed(
              offset: 20,
            ));

            // The word "all" is selected.
            controller.selection = const TextSelection(
              baseOffset: 23,
              extentOffset: 20,
            );
            await tester.pump();
            await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowLeft));
            await tester.pump();
            expect(controller.selection, const TextSelection.collapsed(
              offset: 20,
            ));

            // The word "all" is selected.
            controller.selection = const TextSelection(
              baseOffset: 20,
              extentOffset: 23,
            );
            await tester.pump();
            await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowRight));
            await tester.pump();
            expect(controller.selection, const TextSelection.collapsed(
              offset: 23,
            ));

            // The word "all" is selected.
            controller.selection = const TextSelection(
              baseOffset: 23,
              extentOffset: 20,
            );
            await tester.pump();
            await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowRight));
            await tester.pump();
            expect(controller.selection, const TextSelection.collapsed(
              offset: 23,
            ));
          }, variant: TargetPlatformVariant.all());

          testWidgets('word modifier + arrow key movement', (WidgetTester tester) async {
            controller.text = testText;
            // "good" to "come" is selected.
            controller.selection = const TextSelection(
              baseOffset: 24,
              extentOffset: 43,
            );
            await tester.pumpWidget(buildEditableText());
            await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true));
            await tester.pump();

            expect(controller.selection, const TextSelection.collapsed(
              offset: 39, // Before "come".
            ));

            // "good" to "come" is selected.
            controller.selection = const TextSelection(
              baseOffset: 43,
              extentOffset: 24,
            );
            await tester.pump();
            await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true));
            await tester.pump();
            expect(controller.selection, const TextSelection.collapsed(
              offset: 20, // Before "all".
              //offset: 39, // Before "come".
            ));

            // "good" to "come" is selected.
            controller.selection = const TextSelection(
              baseOffset: 24,
              extentOffset: 43,
            );
            await tester.pump();
            await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowRight, control: true));
            await tester.pump();
            expect(controller.selection, const TextSelection.collapsed(
              offset: 46, // After "to".
              affinity: TextAffinity.upstream,
            ));

            // "good" to "come" is selected.
            controller.selection = const TextSelection(
              baseOffset: 43,
              extentOffset: 24,
            );
            await tester.pump();
            await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowRight, control: true));
            await tester.pump();
            expect(controller.selection, const TextSelection.collapsed(
              offset: 28, // After "good".
              affinity: TextAffinity.upstream,
            ));
          }, variant: allExceptApple);

         testWidgets('line modifier + arrow key movement', (WidgetTester tester) async {
            controller.text = testText;
            // "good" to "come" is selected.
            controller.selection = const TextSelection(
              baseOffset: 24,
              extentOffset: 43,
            );
            await tester.pumpWidget(buildEditableText());
            await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true));
            await tester.pump();

            expect(controller.selection, const TextSelection.collapsed(
              offset: 36, // Before "to".
            ));

            // "good" to "come" is selected.
            controller.selection = const TextSelection(
              baseOffset: 43,
              extentOffset: 24,
            );
            await tester.pump();
            await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true));
            await tester.pump();
            expect(controller.selection, const TextSelection.collapsed(
              offset: 20, // Before "all".
            ));

            // "good" to "come" is selected.
            controller.selection = const TextSelection(
              baseOffset: 24,
              extentOffset: 43,
            );
            await tester.pump();
            await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true));
            await tester.pump();
            expect(controller.selection, const TextSelection.collapsed(
              offset: 54, // After "aid".
              affinity: TextAffinity.upstream,
            ));

            // "good" to "come" is selected.
            controller.selection = const TextSelection(
              baseOffset: 43,
              extentOffset: 24,
            );
            await tester.pump();
            await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true));
            await tester.pump();
            expect(controller.selection, const TextSelection.collapsed(
              offset: 35, // After "people".
              affinity: TextAffinity.upstream,
            ));
          }, variant: allExceptApple);
        });

        group('vertical movement', () {
          testWidgets('at start', (WidgetTester tester) async {
            controller.text = testText;
            controller.selection = const TextSelection.collapsed(
              offset: 0,
            );

            await tester.pumpWidget(buildEditableText());

            for (final SingleActivator activator in allModifierVariants(LogicalKeyboardKey.arrowUp)) {
              await sendKeyCombination(tester, activator);
              await tester.pump();

              expect(controller.text, testText);
              expect(
                controller.selection,
                const TextSelection.collapsed(offset: 0),
                reason: activator.toString(),
              );
            }
          }, variant: TargetPlatformVariant.all());

          testWidgets('at end', (WidgetTester tester) async {
            controller.text = testText;
            controller.selection = const TextSelection.collapsed(
              offset: 72,
            );

            await tester.pumpWidget(buildEditableText());

            for (final SingleActivator activator in allModifierVariants(LogicalKeyboardKey.arrowDown)) {
              await sendKeyCombination(tester, activator);
              await tester.pump();

              expect(controller.text, testText);
              expect(controller.selection.baseOffset, 72, reason: activator.toString());
              expect(controller.selection.extentOffset, 72, reason: activator.toString());
            }
          }, variant: TargetPlatformVariant.all());

          testWidgets('run', (WidgetTester tester) async {
            controller.text =
              'aa\n'     // 3
              'a\n'      // 3 + 2 = 5
              'aa\n'     // 5 + 3 = 8
              'aaa\n'    // 8 + 4 = 12
              'aaaa';    // 12 + 4 = 16

            controller.selection = const TextSelection.collapsed(
              offset: 2,
            );
            await tester.pumpWidget(buildEditableText());
            await tester.pump(); // Wait for autofocus to take effect.

            await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowDown));
            await tester.pump();
            expect(controller.selection, const TextSelection.collapsed(
              offset: 4,
              affinity: TextAffinity.upstream,
            ));

            await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowDown));
            await tester.pump();
            expect(controller.selection, const TextSelection.collapsed(
              offset: 7,
              affinity: TextAffinity.upstream,
            ));

            await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowDown));
            await tester.pump();
            expect(controller.selection, const TextSelection.collapsed(
              offset: 10,
            ));

            await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowDown));
            await tester.pump();
            expect(controller.selection, const TextSelection.collapsed(
              offset: 14,
            ));

            await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowDown));
            await tester.pump();
            expect(controller.selection, const TextSelection.collapsed(
              offset: 16,
            ));

            await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowUp));
            await tester.pump();
            expect(controller.selection, const TextSelection.collapsed(
              offset: 10,
            ));

            await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowUp));
            await tester.pump();
            expect(controller.selection, const TextSelection.collapsed(
              offset: 7,
              affinity: TextAffinity.upstream,
            ));

            await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowUp));
            await tester.pump();
            expect(controller.selection, const TextSelection.collapsed(
              offset: 4,
              affinity: TextAffinity.upstream,
            ));

            await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowUp));
            await tester.pump();
            expect(controller.selection, const TextSelection.collapsed(
              offset: 2,
              affinity: TextAffinity.upstream,
            ));

            await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowUp));
            await tester.pump();
            expect(controller.selection, const TextSelection.collapsed(
              offset: 0,
            ));

            await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowDown));
            await tester.pump();
            expect(controller.selection, const TextSelection.collapsed(
              offset: 4,
              affinity: TextAffinity.upstream,
            ));
          }, variant: TargetPlatformVariant.all());

          testWidgets('run can be interrupted by layout changes', (WidgetTester tester) async {
            controller.text =
              'aa\n'     // 3
              'a\n'      // 3 + 2 = 5
              'aa\n'     // 5 + 3 = 8
              'aaa\n'    // 8 + 4 = 12
              'aaaa';    // 12 + 4 = 16

            controller.selection = const TextSelection.collapsed(
              offset: 2,
            );
            await tester.pumpWidget(buildEditableText());

            await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowUp));
            await tester.pump();
            expect(controller.selection, const TextSelection.collapsed(
              offset: 0,
            ));

            // Layout changes.
            await tester.pumpWidget(buildEditableText(textAlign: TextAlign.right));
            await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowDown));
            await tester.pump();

            expect(controller.selection, const TextSelection.collapsed(
              offset: 3,
            ));
          }, variant: TargetPlatformVariant.all());

          testWidgets('run can be interrupted by selection changes', (WidgetTester tester) async {
            controller.text =
              'aa\n'     // 3
              'a\n'      // 3 + 2 = 5
              'aa\n'     // 5 + 3 = 8
              'aaa\n'    // 8 + 4 = 12
              'aaaa';    // 12 + 4 = 16

            controller.selection = const TextSelection.collapsed(
              offset: 2,
            );
            await tester.pumpWidget(buildEditableText());

            await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowUp));
            await tester.pump();
            expect(controller.selection, const TextSelection.collapsed(
              offset: 0,
            ));

            controller.selection = const TextSelection.collapsed(
              offset: 1,
            );
            await tester.pump();
            controller.selection = const TextSelection.collapsed(
              offset: 0,
            );
            await tester.pump();

            await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowDown));
            await tester.pump();
            expect(controller.selection, const TextSelection.collapsed(
              offset: 3,   // Would have been 4 if the run wasn't interrupted.
            ));
          }, variant: TargetPlatformVariant.all());

          testWidgets('long run with fractional text height', (WidgetTester tester) async {
            controller.text = "${'źdźbło\n' * 49}źdźbło";
            controller.selection = const TextSelection.collapsed(offset: 2);
            await tester.pumpWidget(buildEditableText(style: const TextStyle(fontSize: 13.0, height: 1.17)));

            for (int i = 1; i <= 49; i++) {
              await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowDown));
              await tester.pump();
              expect(
                controller.selection,
                TextSelection.collapsed(offset: 2 + i * 7),
                reason: 'line $i',
              );
            }

            for (int i = 49; i >= 1; i--) {
              await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowUp));
              await tester.pump();
              expect(
                controller.selection,
                TextSelection.collapsed(offset: 2 + (i - 1) * 7),
                reason: 'line $i',
              );
            }
          }, variant: TargetPlatformVariant.all());
        });
      });
    },
    skip: kIsWeb, // [intended] on web these keys are handled by the browser.
  );

  group('macOS shortcuts', () {
    final TargetPlatformVariant macOSOnly = TargetPlatformVariant.only(TargetPlatform.macOS);

    testWidgets('word modifier + arrowLeft', (WidgetTester tester) async {
      controller.text = testText;
      controller.selection = const TextSelection.collapsed(
        offset: 7,   // Before the first "the"
      );
      await tester.pumpWidget(buildEditableText());
      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true));
      await tester.pump();

      expect(controller.selection, const TextSelection.collapsed(
        offset: 4,
      ));
    }, variant: macOSOnly);

    testWidgets('word modifier + arrowRight', (WidgetTester tester) async {
      controller.text = testText;
      controller.selection = const TextSelection.collapsed(
        offset: 7,   // Before the first "the"
      );
      await tester.pumpWidget(buildEditableText());
      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true));
      await tester.pump();

      expect(controller.selection, const TextSelection.collapsed(
        offset: 10,
        affinity: TextAffinity.upstream,
      ));
    }, variant: macOSOnly);

    testWidgets('line modifier + arrowLeft', (WidgetTester tester) async {
      controller.text = testText;
      controller.selection = const TextSelection.collapsed(
        offset: 24,   // Before the "good".
      );
      await tester.pumpWidget(buildEditableText());
      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true));
      await tester.pump();

      expect(controller.selection, const TextSelection.collapsed(
        offset: 20,
      ));
    }, variant: macOSOnly);

    testWidgets('line modifier + arrowRight', (WidgetTester tester) async {
      controller.text = testText;
      controller.selection = const TextSelection.collapsed(
        offset: 24,   // Before the "good".
      );
      await tester.pumpWidget(buildEditableText());
      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowRight, meta: true));
      await tester.pump();

      expect(controller.selection, const TextSelection.collapsed(
        offset: 35, // Before the newline character.
        affinity: TextAffinity.upstream,
      ));
    }, variant: macOSOnly);

    testWidgets('word modifier + arrow key movement', (WidgetTester tester) async {
      controller.text = testText;
      // "good" to "come" is selected.
      controller.selection = const TextSelection(
        baseOffset: 24,
        extentOffset: 43,
      );
      await tester.pumpWidget(buildEditableText());
      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true));
      await tester.pump();

      expect(controller.selection, const TextSelection.collapsed(
        offset: 39, // Before "come".
      ));

      // "good" to "come" is selected.
      controller.selection = const TextSelection(
        baseOffset: 43,
        extentOffset: 24,
      );
      await tester.pump();
      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true));
      await tester.pump();
      expect(controller.selection, const TextSelection.collapsed(
        offset: 20, // Before "all".
        //offset: 39, // Before "come".
      ));

      // "good" to "come" is selected.
      controller.selection = const TextSelection(
        baseOffset: 24,
        extentOffset: 43,
      );
      await tester.pump();
      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true));
      await tester.pump();
      expect(controller.selection, const TextSelection.collapsed(
        offset: 46, // After "to".
        affinity: TextAffinity.upstream,
      ));

      // "good" to "come" is selected.
      controller.selection = const TextSelection(
        baseOffset: 43,
        extentOffset: 24,
      );
      await tester.pump();
      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true));
      await tester.pump();
      expect(controller.selection, const TextSelection.collapsed(
        offset: 28, // After "good".
        affinity: TextAffinity.upstream,
      ));
    }, variant: macOSOnly);

    testWidgets('line modifier + arrow key movement', (WidgetTester tester) async {
      controller.text = testText;
      // "good" to "come" is selected.
      controller.selection = const TextSelection(
        baseOffset: 24,
        extentOffset: 43,
      );
      await tester.pumpWidget(buildEditableText());
      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true));
      await tester.pump();

      expect(controller.selection, const TextSelection.collapsed(
        offset: 36, // Before "to".
      ));

      // "good" to "come" is selected.
      controller.selection = const TextSelection(
        baseOffset: 43,
        extentOffset: 24,
      );
      await tester.pump();
      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true));
      await tester.pump();
      expect(controller.selection, const TextSelection.collapsed(
        offset: 20, // Before "all".
      ));

      // "good" to "come" is selected.
      controller.selection = const TextSelection(
        baseOffset: 24,
        extentOffset: 43,
      );
      await tester.pump();
      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowRight, meta: true));
      await tester.pump();
      expect(controller.selection, const TextSelection.collapsed(
        offset: 54, // After "aid".
        affinity: TextAffinity.upstream,
      ));

      // "good" to "come" is selected.
      controller.selection = const TextSelection(
        baseOffset: 43,
        extentOffset: 24,
      );
      await tester.pump();
      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowRight, meta: true));
      await tester.pump();
      expect(controller.selection, const TextSelection.collapsed(
        offset: 35, // After "people".
        affinity: TextAffinity.upstream,
      ));
    }, variant: macOSOnly);
  }, skip: kIsWeb); // [intended] on web these keys are handled by the browser.

  group('Web does not accept', () {
    final TargetPlatformVariant allExceptApple = TargetPlatformVariant.all(excluding: <TargetPlatform>{ TargetPlatform.iOS, TargetPlatform.macOS });
    const TargetPlatformVariant appleOnly = TargetPlatformVariant(<TargetPlatform>{ TargetPlatform.macOS, TargetPlatform.iOS });
    group('macOS shortcuts', () {

      testWidgets('word modifier + arrowLeft', (WidgetTester tester) async {
        controller.text = testText;
        controller.selection = const TextSelection.collapsed(
          offset: 7,   // Before the first "the"
        );
        await tester.pumpWidget(buildEditableText());
        await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true));
        await tester.pump();

        expect(controller.selection, const TextSelection.collapsed(offset: 7));
      }, variant: appleOnly);

      testWidgets('word modifier + arrowRight', (WidgetTester tester) async {
        controller.text = testText;
        controller.selection = const TextSelection.collapsed(
          offset: 7,   // Before the first "the"
        );
        await tester.pumpWidget(buildEditableText());
        await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true));
        await tester.pump();

        expect(controller.selection, const TextSelection.collapsed(offset: 7));
      }, variant: appleOnly);

      testWidgets('line modifier + arrowLeft', (WidgetTester tester) async {
        controller.text = testText;
        controller.selection = const TextSelection.collapsed(
          offset: 24,   // Before the "good".
        );
        await tester.pumpWidget(buildEditableText());
        await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true));
        await tester.pump();

        expect(controller.selection, const TextSelection.collapsed(offset: 24,));
      }, variant: appleOnly);

      testWidgets('line modifier + arrowRight', (WidgetTester tester) async {
        controller.text = testText;
        controller.selection = const TextSelection.collapsed(
          offset: 24,   // Before the "good".
        );
        await tester.pumpWidget(buildEditableText());
        await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowRight, meta: true));
        await tester.pump();

        expect(controller.selection, const TextSelection.collapsed(
          offset: 24, // Before the newline character.
        ));
      }, variant: appleOnly);

      testWidgets('word modifier + arrow key movement', (WidgetTester tester) async {
        controller.text = testText;
        controller.selection = const TextSelection(
          baseOffset: 24,
          extentOffset: 43,
        );
        await tester.pumpWidget(buildEditableText());
        await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true));
        await tester.pump();

        expect(controller.selection, const TextSelection(
          baseOffset: 24,
          extentOffset: 43,
        ));

        controller.selection = const TextSelection(
          baseOffset: 43,
          extentOffset: 24,
        );
        await tester.pump();
        await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true));
        await tester.pump();
        expect(controller.selection, const TextSelection(
          baseOffset: 43,
          extentOffset: 24,
        ));

        controller.selection = const TextSelection(
          baseOffset: 24,
          extentOffset: 43,
        );
        await tester.pump();
        await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true));
        await tester.pump();
        expect(controller.selection, const TextSelection(
          baseOffset: 24,
          extentOffset: 43,
        ));

        // "good" to "come" is selected.
        controller.selection = const TextSelection(
          baseOffset: 43,
          extentOffset: 24,
        );
        await tester.pump();
        await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true));
        await tester.pump();
        expect(controller.selection, const TextSelection(
          baseOffset: 43,
          extentOffset: 24,
        ));
      }, variant: appleOnly);

      testWidgets('line modifier + arrow key movement', (WidgetTester tester) async {
        controller.text = testText;
        // "good" to "come" is selected.
        controller.selection = const TextSelection(
          baseOffset: 24,
          extentOffset: 43,
        );
        await tester.pumpWidget(buildEditableText());
        await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true));
        await tester.pump();

        expect(controller.selection, const TextSelection(
          baseOffset: 24,
          extentOffset: 43,
        ));

        // "good" to "come" is selected.
        controller.selection = const TextSelection(
          baseOffset: 43,
          extentOffset: 24,
        );
        await tester.pump();
        await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true));
        await tester.pump();
        expect(controller.selection, const TextSelection(
          baseOffset: 43,
          extentOffset: 24,
        ));

        // "good" to "come" is selected.
        controller.selection = const TextSelection(
          baseOffset: 24,
          extentOffset: 43,
        );
        await tester.pump();
        await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowRight, meta: true));
        await tester.pump();
        expect(controller.selection, const TextSelection(
          baseOffset: 24,
          extentOffset: 43,
        ));

        // "good" to "come" is selected.
        controller.selection = const TextSelection(
          baseOffset: 43,
          extentOffset: 24,
        );
        await tester.pump();
        await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.arrowRight, meta: true));
        await tester.pump();
        expect(controller.selection, const TextSelection(
          baseOffset: 43,
          extentOffset: 24,
        ));
      }, variant: appleOnly);
    });

    testWidgets('vertical movement', (WidgetTester tester) async {
      controller.text = testText;
      controller.selection = const TextSelection.collapsed(
        offset: 0,
      );

      await tester.pumpWidget(buildEditableText());

      for (final SingleActivator activator in allModifierVariants(LogicalKeyboardKey.arrowDown)) {
        await sendKeyCombination(tester, activator);
        await tester.pump();

        expect(controller.text, testText);
        expect(
          controller.selection,
          const TextSelection.collapsed(offset: 0),
          reason: activator.toString(),
        );
      }
    }, variant: TargetPlatformVariant.all());

    testWidgets('horizontal movement', (WidgetTester tester) async {
      controller.text = testText;
      controller.selection = const TextSelection.collapsed(
        offset: 0,
      );

      await tester.pumpWidget(buildEditableText());

      for (final SingleActivator activator in allModifierVariants(LogicalKeyboardKey.arrowRight)) {
        await sendKeyCombination(tester, activator);
        await tester.pump();

        expect(controller.selection, const TextSelection.collapsed(offset: 0));
      }
    }, variant: TargetPlatformVariant.all());

    testWidgets('select all non apple', (WidgetTester tester) async {
      controller.text = testText;
      controller.selection = const TextSelection.collapsed(
        offset: 0,
      );

      await tester.pumpWidget(buildEditableText());
      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.keyA, control: true));
      await tester.pump();

      expect(controller.selection, const TextSelection.collapsed(offset: 0));
    }, variant: allExceptApple);

    testWidgets('select all apple', (WidgetTester tester) async {
      controller.text = testText;
      controller.selection = const TextSelection.collapsed(
        offset: 0,
      );

      await tester.pumpWidget(buildEditableText());
      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.keyA, meta: true));
      await tester.pump();

      expect(controller.selection, const TextSelection.collapsed(offset: 0));
    }, variant: appleOnly);

    testWidgets('copy non apple', (WidgetTester tester) async {
      controller.text = testText;
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 4,
      );

      await tester.pumpWidget(buildEditableText());
      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.keyC, control: true));
      await tester.pump();

      final Map<String, dynamic> clipboardData = mockClipboard.clipboardData as Map<String, dynamic>;
      expect(clipboardData['text'], 'empty');
    }, variant: allExceptApple);

    testWidgets('copy apple', (WidgetTester tester) async {
      controller.text = testText;
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 4,
      );

      await tester.pumpWidget(buildEditableText());
      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.keyC, meta: true));
      await tester.pump();

      final Map<String, dynamic> clipboardData = mockClipboard.clipboardData as Map<String, dynamic>;
      expect(clipboardData['text'], 'empty');
    }, variant: appleOnly);

    testWidgets('cut non apple', (WidgetTester tester) async {
      controller.text = testText;
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 4,
      );

      await tester.pumpWidget(buildEditableText());
      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.keyX, control: true));
      await tester.pump();

      final Map<String, dynamic> clipboardData = mockClipboard.clipboardData as Map<String, dynamic>;
      expect(clipboardData['text'], 'empty');
      expect(controller.selection, const TextSelection(
        baseOffset: 0,
        extentOffset: 4,
      ));
    }, variant: allExceptApple);

    testWidgets('cut apple', (WidgetTester tester) async {
      controller.text = testText;
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 4,
      );

      await tester.pumpWidget(buildEditableText());
      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.keyX, meta: true));
      await tester.pump();

      final Map<String, dynamic> clipboardData = mockClipboard.clipboardData as Map<String, dynamic>;
      expect(clipboardData['text'], 'empty');
      expect(controller.selection, const TextSelection(
        baseOffset: 0,
        extentOffset: 4,
      ));
    }, variant: appleOnly);

    testWidgets('paste non apple', (WidgetTester tester) async {
      controller.text = testText;
      controller.selection = const TextSelection.collapsed(offset: 0);
      mockClipboard.clipboardData = <String, dynamic>{
        'text': 'some text',
      };
      await tester.pumpWidget(buildEditableText());
      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.keyV, control: true));
      await tester.pump();
      expect(controller.selection, const TextSelection.collapsed(offset: 0));
      expect(controller.text, testText);
    }, variant: allExceptApple);

    testWidgets('paste apple', (WidgetTester tester) async {
      controller.text = testText;
      controller.selection = const TextSelection.collapsed(offset: 0);
      mockClipboard.clipboardData = <String, dynamic>{
        'text': 'some text',
      };
      await tester.pumpWidget(buildEditableText());
      await sendKeyCombination(tester, const SingleActivator(LogicalKeyboardKey.keyV, meta: true));
      await tester.pump();
      expect(controller.selection, const TextSelection.collapsed(offset: 0));
      expect(controller.text, testText);
    }, variant: appleOnly);

  }, skip: !kIsWeb);// [intended] specific tests target web.
}
