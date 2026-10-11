import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/mobile/widgets/dialog.dart';

void main() {
  testWidgets('desktop server fields retain names without visible inner labels',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    for (final label in ['ID Server', 'Relay Server', 'API Server', 'Key']) {
      await tester.pumpWidget(MaterialApp(
        home: Material(child: serverSettingsTextFormField(
          label: label,
          controller: controller,
          errorMsg: '',
          showLabelText: false,
          autofocus: true,
        )),
      ));
      expect(tester.getSemantics(find.byType(TextField)).getSemanticsData().label,
          label);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  }, semanticsEnabled: true);

  testWidgets('server settings text fields preserve literal input',
      (tester) async {
    final controller = TextEditingController(text: 'AbCdR1c1E=');
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: serverSettingsTextFormField(
          label: 'Key',
          controller: controller,
          errorMsg: '',
          autofocus: true,
        ),
      ),
    ));

    final textField = tester.widget<TextField>(find.byType(TextField));

    expect(textField.controller, controller);
    expect(textField.autofocus, isTrue);
    expect(textField.keyboardType, TextInputType.visiblePassword);
    expect(textField.textCapitalization, TextCapitalization.none);
    expect(textField.autocorrect, isFalse);
    expect(textField.enableSuggestions, isFalse);
    expect(textField.smartDashesType, SmartDashesType.disabled);
    expect(textField.smartQuotesType, SmartQuotesType.disabled);
    expect(textField.enableIMEPersonalizedLearning, isFalse);
    expect(
      textField.spellCheckConfiguration,
      const SpellCheckConfiguration.disabled(),
    );
  });
}
